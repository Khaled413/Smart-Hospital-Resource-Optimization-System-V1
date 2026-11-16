"""
test_fix1_password_management.py - Tests for Fix 1:
- Password complexity validation (min length 12, upper, lower, digits, symbols, anti-pattern)
- Forced redirect to Profile Settings for must_change_password users
- Admin reset password action (step-up auth, temporary password generation, forces change)
- Session invalidation across concurrent sessions upon password change
- Audit log tracking for password changes and admin resets
"""

import pytest
import json
from app import app, validate_password_complexity, generate_secure_temporary_password
from models import db, User, Role, AuditLog


@pytest.fixture(autouse=True)
def setup_db():
    with app.app_context():
        db.create_all()
        from seed_data import seed_database
        seed_database()
        passwords = {
            'admin': 'Admin#2025!',
            'manager': 'Manager#2025!',
            'dr_sarah': 'Doctor#2025!',
            'receptionist': 'Reception#2025!',
            'demo_viewer': 'DemoViewer#2025!'
        }
        for u in User.query.all():
            u.failed_login_attempts = 0
            u.locked_until = None
            u.must_change_password = False
            if u.username in passwords:
                u.set_password(passwords[u.username])
        db.session.commit()
        yield
        for u in User.query.all():
            u.must_change_password = False
            if u.username in passwords:
                u.set_password(passwords[u.username])
        db.session.commit()


@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['RATELIMIT_ENABLED'] = False
    with app.test_client() as c:
        yield c


def login(c, username, password):
    return c.post('/api/auth/login', json={'username': username, 'password': password})


# ─── 1. Password Complexity Validator Tests ────────────────────────────────────

def test_password_complexity_validator():
    """Verify 12-char min length, character classes, sequences, and pattern rejections."""
    # Length < 12
    ok, err = validate_password_complexity("Short#1Aa")
    assert not ok and "at least 12 characters" in err

    # Missing uppercase
    ok, err = validate_password_complexity("alllowercase#1234")
    assert not ok and "uppercase" in err

    # Missing lowercase
    ok, err = validate_password_complexity("ALLLUPPERCASE#1234")
    assert not ok and "lowercase" in err

    # Missing digits
    ok, err = validate_password_complexity("NoDigitsInPassword#")
    assert not ok and "digit" in err

    # Missing special symbols
    ok, err = validate_password_complexity("NoSpecialChars12345")
    assert not ok and "special character" in err

    # Consecutive repeated characters (4+)
    ok, err = validate_password_complexity("Aaaaabbbbb123#Secure")
    assert not ok and "repeated consecutive" in err

    # Simple sequences
    ok, err = validate_password_complexity("Password123456!Secure")
    assert not ok and ("sequence" in err or "common" in err)

    # Common words
    ok, err = validate_password_complexity("Hospital#2025Secure!")
    assert not ok and "common or predictable" in err

    # User identifier leaks
    class DummyUser:
        username = "johndoe"
        email = "johndoe@hospital.org"

    ok, err = validate_password_complexity("JohnDoe#Secure2026!", user=DummyUser())
    assert not ok and "username" in err

    # Fully compliant strong password
    ok, err = validate_password_complexity("MyStr0ng#P@ssw0rd2026!")
    assert ok and err is None


def test_generate_secure_temporary_password():
    """Verify generated temporary passwords meet all complexity rules and are randomized."""
    pwd1 = generate_secure_temporary_password(14)
    pwd2 = generate_secure_temporary_password(14)
    assert len(pwd1) >= 14
    assert pwd1 != pwd2
    ok, _ = validate_password_complexity(pwd1)
    assert ok


# ─── 2. Forced Redirect for must_change_password Users ─────────────────────────

def test_must_change_password_forced_redirect(client):
    """Users flagged with must_change_password=True must be redirected to Profile Settings."""
    with app.app_context():
        user = User.query.filter_by(username='dr_sarah').first()
        user.must_change_password = True
        db.session.commit()

    # Login as dr_sarah
    res_login = login(client, 'dr_sarah', 'Doctor#2025!')
    assert res_login.status_code == 200
    login_data = res_login.get_json()
    assert login_data['must_change_password'] is True
    assert login_data['redirect'] == '/profile'

    # Attempt to browse normal pages (e.g. index, appointments, doctors)
    res_index = client.get('/')
    assert res_index.status_code == 302
    assert '/profile' in res_index.headers['Location']

    res_appts = client.get('/appointments')
    assert res_appts.status_code == 302
    assert '/profile' in res_appts.headers['Location']

    # Attempt to call API endpoints (e.g. /api/beds)
    res_api = client.get('/api/beds')
    assert res_api.status_code == 403
    api_data = res_api.get_json()
    assert api_data['error'] == 'PasswordChangeRequired'
    assert api_data['redirect'] == '/profile'

    # Profile page and profile API must remain accessible!
    assert client.get('/profile').status_code == 200
    assert client.get('/api/user/profile').status_code == 200

    # User updates password to compliant password
    res_change = client.post('/api/auth/change-password', json={
        'current_password': 'Doctor#2025!',
        'new_password': 'Sarah#Clinical2026!'
    })
    assert res_change.status_code == 200
    assert res_change.get_json()['must_change_password'] is False

    # Now dr_sarah can freely access system pages and APIs!
    assert client.get('/').status_code == 200
    assert client.get('/api/beds').status_code == 200


# ─── 3. Invalidation of Other Sessions on Password Change ──────────────────────

def test_session_invalidation_after_password_change():
    """Verify that changing password in one session immediately invalidates concurrent sessions."""
    client1 = app.test_client()
    client2 = app.test_client()

    # Both clients log in as receptionist
    res1 = login(client1, 'receptionist', 'Reception#2025!')
    res2 = login(client2, 'receptionist', 'Reception#2025!')
    assert res1.status_code == 200
    assert res2.status_code == 200

    # Both clients can access /api/beds
    assert client1.get('/api/beds').status_code == 200
    assert client2.get('/api/beds').status_code == 200

    # Client 1 changes the password
    res_change = client1.post('/api/auth/change-password', json={
        'current_password': 'Reception#2025!',
        'new_password': 'ClinicSecure#Pass2026!'
    })
    assert res_change.status_code == 200

    # Client 1 stays authenticated
    assert client1.get('/api/beds').status_code == 200

    # Client 2 makes another request: MUST be rejected with 401 because session is invalidated!
    res_stale = client2.get('/api/beds')
    assert res_stale.status_code == 401


# ─── 4. Admin Reset Password Action ───────────────────────────────────────────

def test_admin_reset_password_generates_temporary_and_forces_change(client):
    """Admin can reset a staff member's password with step-up authentication."""
    # 1. Non-admin cannot call reset password
    login(client, 'receptionist', 'Reception#2025!')
    with app.app_context():
        target_user = User.query.filter_by(username='dr_sarah').first()
        target_uid = target_user.id

    res_forbidden = client.post(f'/api/users/{target_uid}/reset-password', json={
        'admin_password': 'Reception#2025!'
    })
    assert res_forbidden.status_code == 403

    # 2. Admin calls without step-up password
    login(client, 'admin', 'Admin#2025!')
    res_no_stepup = client.post(f'/api/users/{target_uid}/reset-password', json={})
    assert res_no_stepup.status_code == 401
    assert 'Step-up' in res_no_stepup.get_json()['message']

    # 3. Admin calls with correct step-up password
    res_reset = client.post(f'/api/users/{target_uid}/reset-password', json={
        'admin_password': 'Admin#2025!'
    })
    assert res_reset.status_code == 200
    reset_data = res_reset.get_json()
    temp_pwd = reset_data['temporary_password']
    assert len(temp_pwd) >= 14
    assert reset_data['username'] == 'dr_sarah'

    # Target user's DB record must have must_change_password=True
    with app.app_context():
        updated_doc = db.session.get(User, target_uid)
        assert updated_doc.must_change_password is True
        assert updated_doc.check_password(temp_pwd)

    # 4. Target user logs in with temporary password
    doc_client = app.test_client()
    res_doc_login = login(doc_client, 'dr_sarah', temp_pwd)
    assert res_doc_login.status_code == 200
    assert res_doc_login.get_json()['must_change_password'] is True

    # Forced redirect is active
    assert doc_client.get('/').status_code == 302
    assert '/profile' in doc_client.get('/').headers['Location']

    # Check audit log entry was written
    with app.app_context():
        audit = AuditLog.query.filter_by(action='PASSWORD_RESET_ADMIN', resource_id=target_uid).first()
        assert audit is not None
        assert 'Admin admin reset password' in audit.details or 'Administrator admin reset password' in audit.details

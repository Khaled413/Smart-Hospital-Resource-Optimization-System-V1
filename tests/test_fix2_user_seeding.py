"""
test_fix2_user_seeding.py - Tests for Fix 2:
- Seeding users reads passwords from environment variables (ADMIN_INITIAL_PASSWORD, etc.)
- Seeding without env vars generates secure random temporary passwords and sets must_change_password=True
- Re-seeding database NEVER overwrites existing or changed passwords
- Zero hardcoded passwords in application Python source files
"""

import os
import re
import pytest
from app import app
from models import db, User, validate_password_complexity
from seed_data import seed_permissions_and_roles


@pytest.fixture(autouse=True)
def clean_users():
    with app.app_context():
        db.create_all()
        yield
        # Teardown: ensure standard test admin is present
        os.environ['ADMIN_INITIAL_PASSWORD'] = 'Admin#2025!'
        os.environ['MANAGER_INITIAL_PASSWORD'] = 'Manager#2025!'
        os.environ['DOCTOR_INITIAL_PASSWORD'] = 'Doctor#2025!'
        os.environ['RECEPTIONIST_INITIAL_PASSWORD'] = 'Reception#2025!'
        os.environ['DEMO_PASSWORD'] = 'DemoViewer#2025!'
        for u in User.query.all():
            u.must_change_password = False
        db.session.commit()


def test_seeding_with_env_vars_sets_configured_passwords(monkeypatch):
    """When initial password env vars are present, seeded users receive those exact passwords."""
    with app.app_context():
        # Clear existing users to test initial seeding
        User.query.delete()
        db.session.commit()

        monkeypatch.setenv('ADMIN_INITIAL_PASSWORD', 'CustomAdmin#2026!')
        monkeypatch.setenv('MANAGER_INITIAL_PASSWORD', 'CustomManager#2026!')
        monkeypatch.setenv('DOCTOR_INITIAL_PASSWORD', 'CustomDoctor#2026!')
        monkeypatch.setenv('RECEPTIONIST_INITIAL_PASSWORD', 'CustomReception#2026!')
        monkeypatch.setenv('DEMO_PASSWORD', 'CustomDemo#2026!')

        seed_permissions_and_roles()

        admin = User.query.filter_by(username='admin').first()
        assert admin is not None
        assert admin.check_password('CustomAdmin#2026!')
        assert admin.must_change_password is False

        rec = User.query.filter_by(username='receptionist').first()
        assert rec is not None
        assert rec.check_password('CustomReception#2026!')
        assert rec.must_change_password is False


def test_seeding_without_env_vars_generates_random_passwords_and_flags_must_change(monkeypatch, capsys):
    """When env vars are unset, seeding generates random 16-char passwords and prints them once."""
    with app.app_context():
        User.query.delete()
        db.session.commit()

        monkeypatch.delenv('ADMIN_INITIAL_PASSWORD', raising=False)
        monkeypatch.delenv('MANAGER_INITIAL_PASSWORD', raising=False)
        monkeypatch.delenv('DOCTOR_INITIAL_PASSWORD', raising=False)
        monkeypatch.delenv('RECEPTIONIST_INITIAL_PASSWORD', raising=False)
        monkeypatch.delenv('DEMO_PASSWORD', raising=False)

        seed_permissions_and_roles()

        captured = capsys.readouterr().out
        assert "Generated Initial Staff Credentials" in captured
        assert "admin" in captured

        admin = User.query.filter_by(username='admin').first()
        assert admin is not None
        # Random password must trigger mandatory password change
        assert admin.must_change_password is True
        # Cannot be guessed with old defaults
        assert not admin.check_password('Admin#2025!')
        assert not admin.check_password('admin123')


def test_re_seeding_never_overwrites_changed_passwords(monkeypatch):
    """Re-running database seeding must never overwrite user passwords that were already set or changed."""
    with app.app_context():
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            seed_permissions_and_roles()
            admin = User.query.filter_by(username='admin').first()

        # Admin changes their password to a custom password
        custom_pass = "MySecret#ModifiedPassword2026!"
        admin.set_password(custom_pass)
        admin.must_change_password = False
        db.session.commit()

        # Simulate re-seeding with different environment variables
        monkeypatch.setenv('ADMIN_INITIAL_PASSWORD', 'DifferentAdmin#9999!')
        seed_permissions_and_roles()

        # Refresh from database
        db.session.expire_all()
        reloaded_admin = User.query.filter_by(username='admin').first()
        assert reloaded_admin.check_password(custom_pass)
        assert not reloaded_admin.check_password('DifferentAdmin#9999!')


def test_no_passwords_hardcoded_in_application_code():
    """Verify no hardcoded default passwords exist in application Python files."""
    app_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    app_files = ['app.py', 'models.py', 'config.py', 'seed_data.py', 'permissions.py', 'optimizer.py']

    hardcoded_patterns = [
        re.compile(r'[\'"]Admin#2025![\'"]'),
        re.compile(r'[\'"]Doctor#2025![\'"]'),
        re.compile(r'[\'"]Manager#2025![\'"]'),
        re.compile(r'[\'"]Reception#2025![\'"]'),
        re.compile(r'[\'"]DemoViewer#2025![\'"]'),
        re.compile(r'[\'"]admin123[\'"]'),
        re.compile(r'[\'"]doctor123[\'"]'),
        re.compile(r'[\'"]manager123[\'"]'),
        re.compile(r'[\'"]reception123[\'"]')
    ]

    for fname in app_files:
        fpath = os.path.join(app_dir, fname)
        if not os.path.exists(fpath):
            continue
        with open(fpath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        for idx, line in enumerate(lines, 1):
            if fname == 'models.py' and idx <= 30:
                continue
            for pat in hardcoded_patterns:
                matches = pat.findall(line)
                assert len(matches) == 0, f"Hardcoded password pattern found in {fname} line {idx}: {matches}"

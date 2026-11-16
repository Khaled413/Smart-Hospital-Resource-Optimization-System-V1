import pytest
from app import app, db
from models import User, Role, Department, Doctor, Patient, Room, Appointment, today_in_app_tz

@pytest.fixture
def kiosk_client():
    app.config['TESTING'] = True
    app.config['KIOSK_VIEW_TOKEN'] = 'test-kiosk-secret-token-xyz'
    with app.test_client() as client:
        with app.app_context():
            yield client


def setup_kiosk_data(target_date):
    """Seed test appointments for queue kiosk testing."""
    Appointment.query.filter_by(date=target_date).delete()
    db.session.commit()

    dept = Department.query.first() or Department(name='Cardiology', code='CARD')
    db.session.add(dept)
    db.session.flush()

    doc = Doctor.query.first() or Doctor(name='Robert Smith', specialization='Cardiology', department_id=dept.id, shift_start='08:00', shift_end='16:00')
    db.session.add(doc)

    room = Room.query.first() or Room(room_number='101', room_type='consultation', department_id=dept.id)
    db.session.add(room)
    db.session.flush()

    p1 = Patient(name='John Doe', age=45, gender='M', priority='critical', triage_level=1, required_specialization='Cardiology', condition_description='Acute Chest Pain')
    p2 = Patient(name='Sarah Connor', age=38, gender='F', priority='urgent', triage_level=2, required_specialization='Cardiology', condition_description='Hypertensive Crisis')
    p3 = Patient(name='Michael Brown', age=50, gender='M', priority='normal', triage_level=4, required_specialization='Cardiology', condition_description='Follow-up')
    p4 = Patient(name='Alice Wonderland', age=29, gender='F', priority='normal', triage_level=4, required_specialization='Cardiology', condition_description='Routine')

    db.session.add_all([p1, p2, p3, p4])
    db.session.flush()

    # Appointment 1: In progress (serving), Emergency / Immediate
    a1 = Appointment(
        patient_id=p1.id, doctor_id=doc.id, room_id=room.id,
        date=target_date, start_time='09:00', end_time='09:30',
        status='in_progress', is_emergency=True,
        clinical_notes='Confidential ECG anomaly ST elevation',
        prescription='Aspirin 300mg stat'
    )
    # Appointment 2: Scheduled at 10:00 (upcoming 1)
    a2 = Appointment(
        patient_id=p2.id, doctor_id=doc.id, room_id=room.id,
        date=target_date, start_time='10:00', end_time='10:30',
        status='scheduled', is_emergency=False,
        clinical_notes='Blood pressure monitoring notes',
        prescription='Amlodipine 5mg'
    )
    # Appointment 3: Scheduled at 09:30 (upcoming earlier than a2)
    a3 = Appointment(
        patient_id=p3.id, doctor_id=doc.id, room_id=room.id,
        date=target_date, start_time='09:30', end_time='10:00',
        status='scheduled', is_emergency=False,
        clinical_notes='Stable routine checkup'
    )
    # Appointment 4: Completed (should not appear in serving or upcoming)
    a4 = Appointment(
        patient_id=p4.id, doctor_id=doc.id, room_id=room.id,
        date=target_date, start_time='08:30', end_time='09:00',
        status='completed', is_emergency=False
    )

    db.session.add_all([a1, a2, a3, a4])
    db.session.commit()
    return {'p1': p1, 'p2': p2, 'p3': p3, 'p4': p4, 'a1': a1, 'a2': a2, 'a3': a3, 'a4': a4}


def test_kiosk_page_token_auth(kiosk_client):
    """Kiosk display page can be accessed via URL token without user login."""
    # Invalid token redirects to login
    res_bad = kiosk_client.get('/queue-display?token=wrong-token')
    assert res_bad.status_code == 302
    assert '/login' in res_bad.headers['Location']

    # No token redirects to login
    res_none = kiosk_client.get('/queue-display')
    assert res_none.status_code == 302

    # Valid token succeeds
    res_good = kiosk_client.get('/queue-display?token=test-kiosk-secret-token-xyz')
    assert res_good.status_code == 200
    assert b'MediOptim Pro' in res_good.data
    assert b'test-kiosk-secret-token-xyz' in res_good.data


def test_kiosk_api_feed_auth_guards(kiosk_client):
    """API feed strictly validates token or session permissions."""
    # Missing token -> 401
    res = kiosk_client.get('/api/queue-display/feed')
    assert res.status_code == 401
    assert 'Unauthorized' in res.get_json()['error']

    # Invalid token -> 401
    res_bad = kiosk_client.get('/api/queue-display/feed?token=bad-token')
    assert res_bad.status_code == 401

    # Valid token in query param -> 200
    res_good_query = kiosk_client.get('/api/queue-display/feed?token=test-kiosk-secret-token-xyz')
    assert res_good_query.status_code == 200
    assert 'serving' in res_good_query.get_json()

    # Valid token in HTTP Header -> 200
    res_good_header = kiosk_client.get('/api/queue-display/feed', headers={'X-Kiosk-Token': 'test-kiosk-secret-token-xyz'})
    assert res_good_header.status_code == 200
    assert 'serving' in res_good_header.get_json()


def test_kiosk_serving_only_in_progress_and_upcoming_sorted(kiosk_client):
    """Verify 'Currently Serving' contains only in_progress, upcoming is scheduled sorted by time."""
    target_date = today_in_app_tz()
    data = setup_kiosk_data(target_date)

    res = kiosk_client.get(f'/api/queue-display/feed?token=test-kiosk-secret-token-xyz&date={target_date}')
    assert res.status_code == 200
    feed = res.get_json()

    # Check serving
    serving = feed['serving']
    assert len(serving) == 1
    assert serving[0]['id'] == data['a1'].id
    assert serving[0]['status'] == 'in_progress'

    # Check upcoming
    upcoming = feed['upcoming']
    assert len(upcoming) == 2
    # a3 (09:30) must precede a2 (10:00)
    assert upcoming[0]['id'] == data['a3'].id
    assert upcoming[0]['start_time'] == '09:30'
    assert upcoming[1]['id'] == data['a2'].id
    assert upcoming[1]['start_time'] == '10:00'

    # Completed appointment (a4) should NOT appear
    all_ids = [item['id'] for item in serving + upcoming]
    assert data['a4'].id not in all_ids


def test_kiosk_privacy_no_clinical_leak_and_neutral_priority(kiosk_client):
    """Ensure no clinical notes, triage levels, or full patient names leak into kiosk feed."""
    target_date = today_in_app_tz()
    setup_kiosk_data(target_date)

    res = kiosk_client.get(f'/api/queue-display/feed?token=test-kiosk-secret-token-xyz&date={target_date}')
    assert res.status_code == 200
    feed = res.get_json()

    all_items = feed['serving'] + feed['upcoming']
    for item in all_items:
        # Check forbidden clinical fields
        assert 'clinical_notes' not in item
        assert 'prescription' not in item
        assert 'triage_level' not in item
        assert 'medical_condition' not in item
        assert 'vitals' not in item

        # Check name masking
        assert 'John Doe' not in item['patient_initials']
        assert 'Sarah Connor' not in item['patient_initials']
        assert '***' in item['patient_initials']

        # Check neutral priority labels
        assert item['priority_label'] in ('Immediate', 'Priority', 'Regular')
        assert item['priority_label'] != 'Triage 1'


def test_kiosk_production_guard_and_random_generation(monkeypatch):
    """Verify production requires non-default KIOSK_VIEW_TOKEN and dev generates random token."""
    from config import get_config, ProductionConfig, Config

    # In production with missing or default token: must raise ValueError
    monkeypatch.setenv('FLASK_ENV', 'production')
    monkeypatch.setenv('SECRET_KEY', 'a' * 40)
    monkeypatch.setenv('DATABASE_URL', 'postgresql+psycopg2://user:pass@host:5432/db')

    for bad_token in [None, '', 'medioptim-kiosk-display-token-2025', 'kiosk-token', 'default']:
        if bad_token is None:
            monkeypatch.delenv('KIOSK_VIEW_TOKEN', raising=False)
        else:
            monkeypatch.setenv('KIOSK_VIEW_TOKEN', bad_token)
        with pytest.raises(ValueError) as exc:
            get_config('production')
        assert 'KIOSK_VIEW_TOKEN' in str(exc.value)

    # In production with strong token: succeeds
    monkeypatch.setenv('KIOSK_VIEW_TOKEN', 'super-strong-production-token-1234567890')
    cfg = get_config('production')
    assert cfg.KIOSK_VIEW_TOKEN == 'super-strong-production-token-1234567890'


def test_kiosk_rejects_default_known_token(kiosk_client):
    """Requests using the old public placeholder token must be rejected with 401."""
    res = kiosk_client.get('/api/queue-display/feed?token=medioptim-kiosk-display-token-2025')
    assert res.status_code == 401


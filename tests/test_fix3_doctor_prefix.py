"""
test_fix3_doctor_prefix.py - Tests for Doctor Name Normalization & Duplicate 'Dr.' Prevention
"""

import pytest
import hashlib
from app import app
from models import db, Doctor, Patient, Room, Appointment, User, format_doctor_name
from optimizer import run_greedy, run_lp, run_hybrid, handle_emergency_preemption


def test_format_doctor_name_helper_variations():
    """Verify format_doctor_name handles all prefix variations and never outputs 'Dr. Dr.'."""
    # Single title
    assert format_doctor_name("Dr. Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Dr. Sarah", with_title=False) == "Sarah"

    # Bare name (no title)
    assert format_doctor_name("Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Sarah", with_title=False) == "Sarah"

    # Repeated titles (duplicate prefixes)
    assert format_doctor_name("Dr. Dr. Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Dr. Dr. Sarah", with_title=False) == "Sarah"
    assert format_doctor_name("Dr. Dr. Dr. Sarah Mitchell", with_title=True) == "Dr. Sarah Mitchell"
    assert format_doctor_name("Dr. Dr. Dr. Sarah Mitchell", with_title=False) == "Sarah Mitchell"

    # Case insensitivity & formatting quirks
    assert format_doctor_name("dr. sarah", with_title=True) == "Dr. sarah"
    assert format_doctor_name("dr. sarah", with_title=False) == "sarah"
    assert format_doctor_name("DR. Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Dr Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Dr Sarah", with_title=False) == "Sarah"
    assert format_doctor_name("Dr.Sarah", with_title=True) == "Dr. Sarah"
    assert format_doctor_name("Dr.Sarah", with_title=False) == "Sarah"

    # Names naturally beginning with Dr (like Drew, Drake) must not lose their letters
    assert format_doctor_name("Drew", with_title=True) == "Dr. Drew"
    assert format_doctor_name("Drew", with_title=False) == "Drew"
    assert format_doctor_name("Dr. Drew", with_title=True) == "Dr. Drew"
    assert format_doctor_name("Dr. Drew", with_title=False) == "Drew"
    assert format_doctor_name("Dr. Dr. Drew", with_title=True) == "Dr. Drew"

    # Empty / None / Lone Dr.
    assert format_doctor_name("", with_title=True) == ""
    assert format_doctor_name(None, with_title=True) == ""
    assert format_doctor_name("Dr.", with_title=True) == ""
    assert format_doctor_name("Dr", with_title=True) == ""


def test_doctor_model_name_validation(client):
    """Verify Doctor model validates name and strips duplicate Dr. prefixes upon assignment."""
    with app.app_context():
        # Duplicate title assignment
        doc1 = Doctor(
            name="Dr. Dr. Emily Watson",
            specialization="Neurology",
            department_id=1,
            max_patients_per_day=8
        )
        assert doc1.name == "Dr. Emily Watson"
        assert doc1.clean_name == "Emily Watson"
        assert doc1.formatted_name == "Dr. Emily Watson"
        assert "Dr. Dr." not in doc1.name

        # Bare name assignment gets normalized to Dr. <Name>
        doc2 = Doctor(
            name="Robert Hayes",
            specialization="Cardiology",
            department_id=1,
            max_patients_per_day=10
        )
        assert doc2.name == "Dr. Robert Hayes"
        assert doc2.clean_name == "Robert Hayes"

        # to_dict output
        d_dict = doc1.to_dict()
        assert d_dict['name'] == "Dr. Emily Watson"
        assert d_dict['clean_name'] == "Emily Watson"
        assert "Dr. Dr." not in d_dict['name']


def test_doctor_api_normalizes_names(client):
    """Verify POST and PUT /api/doctors endpoints sanitize doctor names."""
    # Log in as admin
    with client.session_transaction() as sess:
        sess['user_id'] = 1
        sess['username'] = 'admin'
        sess['role'] = 'admin'
        sess['is_demo'] = False
        user = db.session.get(User, 1)
        if user:
            sess['pwd_hash'] = hashlib.sha256(user.password_hash.encode('utf-8')).hexdigest()[:16]

    # 1. POST doctor with duplicate Dr. Dr.
    res_post = client.post('/api/doctors', json={
        'name': 'Dr. Dr. Christopher Columbus',
        'specialization': 'General Surgery',
        'department_id': 1,
        'max_patients_per_day': 8
    })
    assert res_post.status_code == 201
    doc_data = res_post.get_json()
    assert doc_data['name'] == "Dr. Christopher Columbus"
    assert "Dr. Dr." not in doc_data['name']
    doc_id = doc_data['id']

    # 2. PUT doctor with triple Dr.
    res_put = client.put(f'/api/doctors/{doc_id}', json={
        'name': 'Dr. Dr. Dr. Christopher C. Columbus'
    })
    assert res_put.status_code == 200
    updated_data = res_put.get_json()
    assert updated_data['name'] == "Dr. Christopher C. Columbus"
    assert "Dr. Dr." not in updated_data['name']

    # Clean up test doctor
    with app.app_context():
        d = db.session.get(Doctor, doc_id)
        if d:
            db.session.delete(d)
            db.session.commit()


def test_optimizer_logs_never_have_duplicate_dr():
    """Verify Greedy, LP, Hybrid and Emergency logs do not contain 'Dr. Dr.'."""
    with app.app_context():
        # Fetch or mock doctors with "Dr." in name
        doctors = Doctor.query.all()
        rooms = Room.query.all()
        patients = Patient.query.all()

        if doctors and rooms and patients:
            # 1. Greedy solver
            _, _, g_log = run_greedy(patients[:3], doctors, rooms, "2025-06-01")
            for line in g_log:
                assert "Dr. Dr." not in line

            # 2. LP solver
            _, _, lp_log = run_lp(patients[:3], doctors, rooms, "2025-06-01")
            for line in lp_log:
                assert "Dr. Dr." not in line

            # 3. Hybrid solver
            _, _, h_log = run_hybrid(patients[:3], doctors, rooms, "2025-06-01")
            for line in h_log:
                assert "Dr. Dr." not in line

            # 4. Emergency Preemption
            em_patient = patients[0]
            existing_appts = Appointment.query.filter_by(date="2025-06-01").all()
            em_res = handle_emergency_preemption(em_patient, existing_appts, doctors, rooms, "2025-06-01")
            for line in em_res.get('log', []):
                assert "Dr. Dr." not in line

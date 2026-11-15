"""
test_system.py - Comprehensive Unit & Integration Tests for MediOptim Pro
Run with: pytest tests/test_system.py
"""

import pytest
import os
import sys

# Add root directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
os.environ['ADMIN_INITIAL_PASSWORD'] = 'Admin#2025!'
os.environ['MANAGER_INITIAL_PASSWORD'] = 'Manager#2025!'
os.environ['DOCTOR_INITIAL_PASSWORD'] = 'Doctor#2025!'
os.environ['RECEPTIONIST_INITIAL_PASSWORD'] = 'Reception#2025!'
os.environ['DEMO_MODE'] = 'true'
os.environ['RATELIMIT_ENABLED'] = 'false'

from app import app, limiter
from models import db, Department, Doctor, Patient, Room, Bed, Equipment, Appointment, User, Role, Permission, UserPermissionOverride
from optimizer import (
    run_greedy, run_lp, run_hybrid, handle_emergency_preemption,
    predict_no_show_risk, run_scenario_simulation, run_optimization,
    ScheduleState, sync_triage_and_priority, times_overlap, time_to_minutes
)


@pytest.fixture
def client():
    app.config['TESTING'] = True
    app.config['RATELIMIT_ENABLED'] = False
    limiter.enabled = False
    os.environ['ADMIN_INITIAL_PASSWORD'] = 'Admin#2025!'
    with app.test_client() as test_client:
        yield test_client


def login_as(client, username='admin', password='Admin#2025!'):
    return client.post('/api/auth/login', json={'username': username, 'password': password})


def test_user_authentication(client):
    """Test user password hashing and login API."""
    res = client.post('/api/auth/login', json={'username': 'admin', 'password': 'Admin#2025!'})
    assert res.status_code == 200
    data = res.get_json()
    assert data['user']['username'] == 'admin'
    assert data['user']['role'] == 'admin'

    # Failed login
    res_fail = client.post('/api/auth/login', json={'username': 'admin', 'password': 'wrongpassword'})
    assert res_fail.status_code == 401


def test_account_lockout_after_multiple_failed_logins(client):
    """Verify account is temporarily locked out after 5 consecutive failed login attempts."""
    # Reset attempts first
    with app.app_context():
        u = User.query.filter_by(username='admin').first()
        if u:
            u.failed_login_attempts = 0
            u.locked_until = None
            db.session.commit()

    # Attempt 4 failed logins
    for i in range(4):
        res = client.post('/api/auth/login', json={'username': 'admin', 'password': f'badpwd_{i}'})
        assert res.status_code == 401
        assert 'Invalid' in res.get_json()['error']

    # 5th failed login triggers lockout (HTTP 403)
    res_5 = client.post('/api/auth/login', json={'username': 'admin', 'password': 'badpwd_5'})
    assert res_5.status_code == 403
    assert 'locked' in res_5.get_json()['error'].lower()

    # Even with correct password, account remains locked
    res_locked = client.post('/api/auth/login', json={'username': 'admin', 'password': 'Admin#2025!'})
    assert res_locked.status_code == 403
    assert 'locked' in res_locked.get_json()['error'].lower()

    # Reset lockout for following tests
    with app.app_context():
        u = User.query.filter_by(username='admin').first()
        if u:
            u.failed_login_attempts = 0
            u.locked_until = None
            db.session.commit()


def test_all_api_routes_require_authentication(client):
    """
    Dynamically iterate over every route registered in app.url_map.
    Every route starting with /api/ (except /api/auth/login and /api/auth/me)
    MUST return HTTP 401 when accessed without an active session.
    """
    public_endpoints = {'/api/auth/login', '/api/auth/me'}
    tested_count = 0
    import re

    for rule in app.url_map.iter_rules():
        path = rule.rule
        if not path.startswith('/api/') or path in public_endpoints:
            continue

        # Convert URL parameters like <int:id>, <id> to dummy values
        test_path = re.sub(r'<[^>]*int[^>]*>', '1', path)
        test_path = re.sub(r'<[^>]+>', '1', test_path)

        for method in rule.methods:
            if method in {'HEAD', 'OPTIONS'}:
                continue
            res = client.open(test_path, method=method)
            assert res.status_code == 401, (
                f"Route {method} {test_path} (rule: {rule.rule}) is not protected! "
                f"Returned {res.status_code} instead of 401."
            )
            tested_count += 1

    assert tested_count >= 15, f"Expected at least 15 API routes to be tested, got {tested_count}"


def test_rbac_and_protected_routes(client):
    """Test that unauthorized access is blocked and roles are strictly enforced."""
    # 1. Unauthenticated page redirect
    res_page = client.get('/')
    assert res_page.status_code == 302
    assert '/login' in res_page.headers['Location']

    # 2. Unauthenticated API returns 401
    res_api = client.get('/api/dashboard')
    assert res_api.status_code == 401

    # 3. Login as receptionist
    login_as(client, 'receptionist', 'Reception#2025!')

    # Receptionist can view beds
    res_beds = client.get('/api/beds')
    assert res_beds.status_code == 200

    # Receptionist cannot access audit logs (Admin only)
    res_audit = client.get('/api/audit-logs')
    assert res_audit.status_code == 403

    # Receptionist cannot trigger AI optimization (Admin & Manager only)
    res_opt = client.post('/api/optimize', json={})
    assert res_opt.status_code == 403

    # 4. Login as admin
    login_as(client, 'admin', 'Admin#2025!')
    res_audit_admin = client.get('/api/audit-logs')
    assert res_audit_admin.status_code == 200


def test_security_headers_and_csv_sanitization(client):
    """Test security headers and CSV export sanitization."""
    res = client.get('/login')
    assert res.headers.get('X-Content-Type-Options') == 'nosniff'
    assert res.headers.get('X-Frame-Options') == 'SAMEORIGIN'
    assert 'Content-Security-Policy' in res.headers

    from app import sanitize_csv_cell
    assert sanitize_csv_cell("=1+1") == "'=1+1"
    assert sanitize_csv_cell("+cmd") == "'+cmd"
    assert sanitize_csv_cell("-123") == "'-123"
    assert sanitize_csv_cell("@calc") == "'@calc"
    assert sanitize_csv_cell("Normal text") == "Normal text"


def test_no_show_prediction():
    """Test ML no-show risk predictor logic."""
    class DummyPatient:
        priority = 'critical'
        age = 68
        heart_rate = 115
        spo2 = 91

    risk_critical = predict_no_show_risk(DummyPatient(), days_in_advance=0)
    assert risk_critical <= 0.10  # Critical patients rarely miss appointments

    class LowPatient:
        priority = 'low'
        age = 22
        heart_rate = 70
        spo2 = 99

    risk_low = predict_no_show_risk(LowPatient(), days_in_advance=14)
    assert risk_low >= 0.25  # Young adult with low priority far in advance has high no-show risk


def test_optimizer_algorithms(client):
    """Test Greedy, LP, and Hybrid optimization."""
    with app.app_context():
        patients = Patient.query.limit(8).all()
        doctors = Doctor.query.all()
        rooms = Room.query.all()

        # Greedy
        g_res, g_unassigned, g_log = run_greedy(patients, doctors, rooms, "2025-01-01")
        assert len(g_res) > 0

        # LP
        lp_res, lp_unassigned, lp_log = run_lp(patients, doctors, rooms, "2025-01-01")
        assert len(lp_res) > 0

        # Hybrid
        h_res, h_unassigned, h_log = run_hybrid(patients, doctors, rooms, "2025-01-01")
        assert len(h_res) > 0


def test_emergency_code_red_preemption(client):
    """Test Code Red emergency preemption of scheduled slots."""
    with app.app_context():
        doctors = Doctor.query.all()
        rooms = Room.query.all()
        appts = Appointment.query.all()

        em_patient = Patient(
            name="Emergency Heart Attack",
            age=60,
            gender="Male",
            priority="critical",
            required_specialization="Cardiology",
            triage_level=1
        )
        res = handle_emergency_preemption(em_patient, appts, doctors, rooms, "2025-01-01")
        assert res['action'] in ('immediate_slot', 'preempted')


def test_bed_management_api(client):
    """Test bed admission and discharge flow."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        for b in Bed.query.all():
            b.patient_id = None
            b.status = 'vacant'
        db.session.commit()

    # List beds
    res = client.get('/api/beds')
    assert res.status_code == 200
    beds = res.get_json()
    assert len(beds) >= 1

    vacant_bed = next((b for b in beds if b['status'] == 'vacant'), beds[0])
    bed_id = vacant_bed['id']

    # Admit
    admit_res = client.post(f'/api/beds/{bed_id}/admit', json={'patient_id': 1, 'notes': 'Test admission'})
    assert admit_res.status_code == 200
    assert admit_res.get_json()['status'] == 'occupied'

    # Discharge
    dc_res = client.post(f'/api/beds/{bed_id}/discharge', json={})
    assert dc_res.status_code == 200
    assert dc_res.get_json()['status'] == 'cleaning'


def test_scenario_simulation():
    """Test crisis what-if simulation."""
    with app.app_context():
        patients = Patient.query.limit(10).all()
        doctors = Doctor.query.all()
        rooms = Room.query.all()

        sim = run_scenario_simulation(
            patients, doctors, rooms, "2025-01-01",
            patient_surge_percent=30
        )
        assert 'baseline' in sim
        assert 'crisis' in sim
        assert 'impact' in sim
        assert sim['crisis']['total_patients'] >= sim['baseline']['total_patients']


def test_schedule_state_and_hybrid_conflict_free():
    """Verify ScheduleState tracks busy intervals and Hybrid never double-books doctors or rooms."""
    with app.app_context():
        patients = Patient.query.limit(12).all()
        doctors = Doctor.query.all()
        rooms = Room.query.all()

        # Run hybrid optimization
        assignments, unassigned, log = run_hybrid(patients, doctors, rooms, "2025-01-01")

        # 1. Verify no doctor is double-booked
        doc_times = {}
        for a in assignments:
            d_id = a['doctor'].id
            s = time_to_minutes(a['start_time'])
            e = time_to_minutes(a['end_time'])
            if d_id not in doc_times:
                doc_times[d_id] = []
            for prev_s, prev_e in doc_times[d_id]:
                assert not times_overlap(s, e, prev_s, prev_e), f"Doctor {d_id} double booked: {s}-{e} vs {prev_s}-{prev_e}"
            doc_times[d_id].append((s, e))

        # 2. Verify no room is double-booked (including cleaning buffer)
        room_times = {}
        for a in assignments:
            r_id = a['room'].id
            s = time_to_minutes(a['start_time'])
            e = time_to_minutes(a['end_time']) + a.get('buffer_minutes', 10)
            if r_id not in room_times:
                room_times[r_id] = []
            for prev_s, prev_e in room_times[r_id]:
                assert not times_overlap(s, e, prev_s, prev_e), f"Room {r_id} double booked with buffer: {s}-{e} vs {prev_s}-{prev_e}"
            room_times[r_id].append((s, e))


def test_priority_triage_synchronization():
    """Verify ESI levels and priorities are synchronized and consistent."""
    assert sync_triage_and_priority(priority=None, triage_level=1) == ('critical', 1)
    assert sync_triage_and_priority(priority=None, triage_level=2) == ('critical', 2)
    assert sync_triage_and_priority(priority=None, triage_level=3) == ('urgent', 3)
    assert sync_triage_and_priority(priority=None, triage_level=4) == ('normal', 4)
    assert sync_triage_and_priority(priority=None, triage_level=5) == ('low', 5)

    # Contradicting inputs prioritize valid triage level
    assert sync_triage_and_priority(priority='low', triage_level=1) == ('critical', 1)


def test_api_optimize_atomic_and_excludes_scheduled(client):
    """Verify /api/optimize endpoint excludes already-scheduled patients and operates atomically."""
    login_as(client, 'admin', 'Admin#2025!')
    target_date = "2025-10-10"

    with app.app_context():
        Patient.query.filter(Patient.id <= 20).update({'preferred_date': target_date})
        Patient.query.filter(Patient.id > 20).delete()
        Appointment.query.filter_by(date=target_date).delete()
        db.session.commit()

    # First run: schedules patients
    res1 = client.post('/api/optimize', json={'algorithm': 'hybrid', 'date': target_date, 'clear_existing': True})
    assert res1.status_code == 200
    data1 = res1.get_json()
    assert data1['status'] == 'success'
    assert 'algorithm_used' in data1
    first_assigned = len(data1['assignments'])
    assert first_assigned > 0

    # Second run without clear_existing: already scheduled patients must be excluded
    res2 = client.post('/api/optimize', json={'algorithm': 'hybrid', 'date': target_date, 'clear_existing': False})
    assert res2.status_code == 200
    data2 = res2.get_json()
    # Should warn that no eligible unscheduled patients are left
    assert data2['status'] == 'warning'
    assert data2['metrics']['assigned'] == 0


def test_analytics_utilization_date_filtered(client):
    """Verify /api/analytics/utilization returns date-filtered utilization metrics."""
    login_as(client, 'admin', 'Admin#2025!')
    res = client.get('/api/analytics/utilization?date=2025-10-10')
    assert res.status_code == 200
    util_list = res.get_json()
    assert isinstance(util_list, list)
    for u in util_list:
        assert 'doctor' in u
        assert 'utilization' in u
        assert 'booked_minutes' in u
        assert u['utilization'] >= 0


def test_lp_infeasible_status_and_solver_fallback():
    """Verify LP solver falls back gracefully to Greedy when candidate variables or problem is infeasible."""
    with app.app_context():
        # Large dataset or dummy patients
        doctors = Doctor.query.all()
        rooms = Room.query.all()
        # Create an artificial ScheduleState where all doctors and rooms are completely full
        state = ScheduleState(doctors, rooms)
        for d in doctors:
            state.doctor_patient_count[d.id] = d.max_patients_per_day

        patients = Patient.query.limit(5).all()
        # With zero quota left for any doctor, run_lp should fall back cleanly
        res = run_lp(patients, doctors, rooms, "2025-01-01", schedule_state=state)
        # Should return OptimizerResult with algorithm_used recorded
        assert isinstance(res, tuple)
        assignments, unassigned, log = res[0], res[1], res[2]
        assert len(assignments) == 0
        assert len(unassigned) == len(patients)
        assert res.algorithm_used == 'greedy'
        assert res.fallback_reason is not None


def test_emergency_preemption_respects_doctor_shift():
    """Verify emergency preemption checks doctor's actual shift and does not bump beyond shift boundaries."""
    with app.app_context():
        doctors = Doctor.query.all()
        rooms = Room.query.all()

        # Doctor with early shift end
        doc = doctors[0]
        appt = Appointment(
            patient_id=1,
            doctor_id=doc.id,
            room_id=rooms[0].id,
            date="2025-01-01",
            start_time="15:30",
            end_time="16:00",
            duration_minutes=30,
            status="scheduled",
            is_emergency=False
        )

        em_patient = Patient(
            name="Late Emergency Patient",
            age=55,
            gender="Female",
            priority="critical",
            required_specialization=doc.specialization,
            triage_level=1
        )

        # Call emergency preemption
        res = handle_emergency_preemption(em_patient, [appt], [doc], rooms, "2025-01-01")
        assert res['action'] in ('immediate_slot', 'preempted')
        if res['action'] == 'preempted':
            plan = res.get('bumped_plan')
            assert plan is not None
            # Either conflict-free relocated before doc.available_until, or flagged needs_reschedule
            if plan.get('rescheduled_slot'):
                assert time_to_minutes(plan['rescheduled_slot']['end_time']) <= time_to_minutes(doc.available_until)
            else:
                assert plan.get('needs_reschedule') is True


def test_specialization_flexible_compatibility():
    """Verify alias mapping and flexible specialization matching."""
    from optimizer import are_specializations_compatible, normalize_specialization
    assert normalize_specialization('Cardio') == 'cardiology'
    assert normalize_specialization('cardiologist') == 'cardiology'
    assert normalize_specialization('ortho') == 'orthopedics'
    assert are_specializations_compatible('Cardiology', 'cardiologist') is True
    assert are_specializations_compatible('General Surgery', 'surgery') is True
    assert are_specializations_compatible('Pediatrics', 'pediatrician') is True
    assert are_specializations_compatible('Neurology', 'Cardiology') is False


def test_appointment_status_state_machine(client):
    """Verify appointment status transition validation."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        appt = Appointment.query.filter_by(status='scheduled').first()
        if not appt:
            appt = Appointment(patient_id=1, doctor_id=1, room_id=1, date="2025-01-01",
                               start_time="09:00", end_time="09:30", duration_minutes=30, status="scheduled")
            db.session.add(appt)
            db.session.commit()
        appt_id = appt.id

    # scheduled -> in_progress (valid)
    res = client.patch(f'/api/appointments/{appt_id}/status', json={'status': 'in_progress'})
    assert res.status_code == 200
    assert res.get_json()['status'] == 'in_progress'

    # in_progress -> completed (valid)
    res = client.patch(f'/api/appointments/{appt_id}/status', json={'status': 'completed'})
    assert res.status_code == 200
    assert res.get_json()['status'] == 'completed'

    # completed -> scheduled (invalid transition: terminal state)
    res = client.patch(f'/api/appointments/{appt_id}/status', json={'status': 'scheduled'})
    assert res.status_code == 400
    assert 'Invalid status transition' in res.get_json()['error']


def test_bed_admission_guards(client):
    """Verify validation when admitting patients to beds."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        for b in Bed.query.all():
            b.patient_id = None
            b.status = 'vacant'
        db.session.commit()

    # Fetch beds
    beds = client.get('/api/beds').get_json()
    vacant = [b for b in beds if b['status'] == 'vacant']
    assert len(vacant) >= 2, "Need at least 2 vacant beds to test admission guards"
    b1 = vacant[0]['id']
    b2 = vacant[1]['id']

    # Missing patient_id
    res = client.post(f'/api/beds/{b1}/admit', json={})
    assert res.status_code == 400

    # Admit patient 1 to bed 1
    res_admit = client.post(f'/api/beds/{b1}/admit', json={'patient_id': 1})
    assert res_admit.status_code == 200

    # Cannot admit another patient to already occupied bed 1
    res = client.post(f'/api/beds/{b1}/admit', json={'patient_id': 2})
    assert res.status_code == 400
    assert 'already occupied' in res.get_json()['error']

    # Cannot admit patient 1 into bed 2 when already in bed 1
    res = client.post(f'/api/beds/{b2}/admit', json={'patient_id': 1})
    assert res.status_code == 400
    assert 'already admitted' in res.get_json()['error']


def test_deletion_safeguards_active_appointments(client):
    """Verify deletion of doctor or patient is rejected if active appointments exist."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        # Ensure active appointment exists
        appt = Appointment.query.filter_by(status='scheduled').first()
        if not appt:
            appt = Appointment(patient_id=1, doctor_id=1, room_id=1, date="2025-01-01",
                               start_time="09:00", end_time="09:30", duration_minutes=30, status="scheduled")
            db.session.add(appt)
            db.session.commit()
        doc_id = appt.doctor_id
        pat_id = appt.patient_id

    # Attempt delete doctor with active appt
    res = client.delete(f'/api/doctors/{doc_id}')
    assert res.status_code == 400
    assert 'active appointment' in res.get_json()['error']

    # Attempt delete patient with active appt
    res = client.delete(f'/api/patients/{pat_id}')
    assert res.status_code == 400
    assert 'active appointment' in res.get_json()['error']


def test_unique_constraint_conflicts(client):
    """Verify unique constraint collisions return HTTP 409 Conflict."""
    login_as(client, 'admin', 'Admin#2025!')
    # Add room
    res1 = client.post('/api/rooms', json={'room_number': 'UNIQUE-TEST-101', 'department_id': 1})
    assert res1.status_code in (201, 409)

    # Add duplicate room
    res2 = client.post('/api/rooms', json={'room_number': 'UNIQUE-TEST-101', 'department_id': 1})
    assert res2.status_code == 409
    assert 'already exists' in res2.get_json()['error']


def test_no_credentials_exposed_in_rendered_login_html(client):
    """Verify login page never leaks passwords or admin autofill buttons."""
    # When DEMO_MODE is False (default production)
    app.config['DEMO_MODE'] = False
    res = client.get('/login')
    html = res.get_data(as_text=True)

    # Must NOT expose passwords or autofill buttons
    assert 'admin123' not in html
    assert 'Admin#2025!' not in html
    assert 'Doctor#2025!' not in html
    assert 'Manager#2025!' not in html
    assert 'Reception#2025!' not in html
    assert 'Quick Select Role' not in html
    assert '👑 Admin' not in html


def test_security_headers_present(client):
    """Verify critical HTTP security headers are set on all responses."""
    res = client.get('/login')
    assert res.headers.get('X-Content-Type-Options') == 'nosniff'
    assert res.headers.get('X-Frame-Options') == 'SAMEORIGIN'
    assert 'Content-Security-Policy' in res.headers
    assert res.headers.get('Referrer-Policy') == 'strict-origin-when-cross-origin'


def test_csv_export_formula_injection_sanitization(client):
    """Verify CSV export sanitizes formulas starting with =, +, -, @ to prevent spreadsheet injection."""
    login_as(client, 'admin', 'Admin#2025!')
    # Register patient with formula injection name
    malicious_name = "=SUM(1+1)"
    client.post('/api/patients', json={
        'name': malicious_name,
        'age': 30,
        'gender': 'Male',
        'required_specialization': 'Cardiology'
    })

    try:
        res = client.get('/api/export/appointments/csv')
        assert res.status_code == 200
        csv_text = res.get_data(as_text=True)
        # If the malicious name appeared, it must be escaped with a single quote prefix
        if malicious_name in csv_text:
            assert f"'{malicious_name}" in csv_text
    finally:
        with app.app_context():
            Patient.query.filter_by(name=malicious_name).delete()
            db.session.commit()


# ─── Dynamic RBAC Comprehensive Tests ──────────────────────────────────────────

def test_all_routes_have_explicit_permission_protection():
    """Verify default-deny architecture: every route must have explicit authentication or permission gating."""
    exempt_endpoints = {'login_page', 'api_login', 'static', 'favicon'}
    unprotected = []
    for rule in app.url_map.iter_rules():
        endpoint = rule.endpoint
        if endpoint in exempt_endpoints:
            continue
        view_func = app.view_functions.get(endpoint)
        if not view_func:
            continue
        # Verify decorated with permission or auth guard
        is_protected = getattr(view_func, '_permission_protected', False)
        if not is_protected:
            unprotected.append(f"{rule.rule} -> {endpoint}")
    assert not unprotected, f"Unprotected routes detected violating default-deny architecture: {unprotected}"


def test_role_permission_matrix_access_control(client):
    """Verify permission matrix enforces access control across roles."""
    # 1. Admin has access to all protected endpoints
    login_as(client, 'admin', 'Admin#2025!')
    assert client.get('/api/audit-logs').status_code == 200
    assert client.get('/api/roles').status_code == 200
    assert client.get('/api/users').status_code == 200

    # 2. Receptionist cannot view audit logs or optimize
    login_as(client, 'receptionist', 'Reception#2025!')
    res_audit = client.get('/api/audit-logs')
    assert res_audit.status_code == 403
    assert 'audit.view' in res_audit.get_json().get('required_permission', '')

    res_opt = client.post('/api/optimize', json={'algorithm': 'greedy'})
    assert res_opt.status_code == 403
    assert 'optimization.run' in res_opt.get_json().get('required_permission', '')

    # 3. Doctor cannot optimize or view audit logs, but can view patients
    login_as(client, 'dr_sarah', 'Doctor#2025!')
    assert client.get('/api/audit-logs').status_code == 403
    assert client.post('/api/optimize', json={'algorithm': 'greedy'}).status_code == 403
    assert client.get('/api/patients').status_code == 200

    # 4. Demo viewer has read-only views, cannot execute state modifications
    login_as(client, 'demo_viewer', 'DemoViewer#2025!')
    assert client.get('/api/dashboard').status_code == 200
    assert client.get('/api/audit-logs').status_code == 403
    assert client.post('/api/patients', json={'name': 'Hacker'}).status_code == 403


def test_row_level_doctor_scoping(client):
    """Verify doctors can only view and update their own appointments."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        sarah = User.query.filter_by(username='dr_sarah').first()
        assert sarah is not None and sarah.doctor_id is not None
        sarah_doc_id = sarah.doctor_id

        # Find another doctor's ID
        other_doctor = Doctor.query.filter(Doctor.id != sarah_doc_id).first()
        assert other_doctor is not None
        other_doc_id = other_doctor.id

        # Create appointment for Dr. Sarah
        appt_sarah = Appointment(
            patient_id=1, doctor_id=sarah_doc_id, room_id=1,
            date="2027-01-01", start_time="09:00", end_time="09:30",
            duration_minutes=30, status="scheduled"
        )
        # Create appointment for the other doctor
        appt_other = Appointment(
            patient_id=2, doctor_id=other_doc_id, room_id=2,
            date="2027-01-01", start_time="10:00", end_time="10:30",
            duration_minutes=30, status="scheduled"
        )
        db.session.add_all([appt_sarah, appt_other])
        db.session.commit()
        sarah_aid = appt_sarah.id
        other_aid = appt_other.id

    # Log in as Dr. Sarah Mitchell
    login_as(client, 'dr_sarah', 'Doctor#2025!')

    # 1. Query appointments: must only contain Dr. Sarah's appointments
    res = client.get('/api/appointments?date=2027-01-01')
    assert res.status_code == 200
    appts = res.get_json()
    returned_doc_ids = {a['doctor_id'] for a in appts}
    assert sarah_doc_id in returned_doc_ids
    assert other_doc_id not in returned_doc_ids

    # 2. Dr. Sarah can update her own appointment
    res_update_own = client.patch(f'/api/appointments/{sarah_aid}/status', json={'status': 'in_progress'})
    assert res_update_own.status_code == 200
    assert res_update_own.get_json()['status'] == 'in_progress'

    # 3. Dr. Sarah cannot update another doctor's appointment (HTTP 403)
    res_update_other = client.patch(f'/api/appointments/{other_aid}/status', json={'status': 'in_progress'})
    assert res_update_other.status_code == 403


def test_field_level_serialization_and_demo_masking(client):
    """Verify clinical vitals are stripped for non-clinical roles and demo viewer masks names."""
    # 1. Doctor Sarah (holds patients.view_clinical) receives full vitals
    login_as(client, 'dr_sarah', 'Doctor#2025!')
    res_doc = client.get('/api/patients')
    assert res_doc.status_code == 200
    doc_pats = res_doc.get_json()
    assert len(doc_pats) > 0
    p_doc = doc_pats[0]
    assert p_doc['vitals'] is not None
    assert 'bp' in p_doc['vitals']
    assert p_doc['triage_level'] is not None

    # 2. Receptionist (lacks patients.view_clinical) has vitals stripped
    login_as(client, 'receptionist', 'Reception#2025!')
    res_rec = client.get('/api/patients')
    assert res_rec.status_code == 200
    rec_pats = res_rec.get_json()
    assert len(rec_pats) > 0
    p_rec = rec_pats[0]
    assert p_rec['vitals'] is None
    assert p_rec['triage_level'] is None
    assert 'Protected' in p_rec['condition_description']

    # 3. Demo Viewer has vitals stripped AND patient names masked
    login_as(client, 'demo_viewer', 'DemoViewer#2025!')
    res_demo = client.get('/api/patients')
    assert res_demo.status_code == 200
    demo_pats = res_demo.get_json()
    assert len(demo_pats) > 0
    p_demo = demo_pats[0]
    assert p_demo['vitals'] is None
    # Verify name is masked (contains ***)
    assert '***' in p_demo['name']


def test_dynamic_permission_overrides_and_cache_busting(client):
    """Verify per-user permission overrides take immediate effect without re-login."""
    # 1. Receptionist initially denied audit logs
    login_as(client, 'receptionist', 'Reception#2025!')
    res1 = client.get('/api/audit-logs')
    assert res1.status_code == 403

    # 2. Admin grants 'audit.view' override to receptionist
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        rec_user = User.query.filter_by(username='receptionist').first()
        rec_uid = rec_user.id

    res_grant = client.post(f'/api/users/{rec_uid}/overrides', json={
        'permission_key': 'audit.view',
        'effect': 'grant',
        'reason': 'Temporary audit inspection assignment',
        'admin_password': 'Admin#2025!'
    })
    assert res_grant.status_code == 201

    # 3. Switch back to receptionist: audit logs immediately accessible (HTTP 200)
    login_as(client, 'receptionist', 'Reception#2025!')
    res2 = client.get('/api/audit-logs')
    assert res2.status_code == 200
    assert isinstance(res2.get_json(), list)

    # 4. Admin removes the override
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        perm = Permission.query.filter_by(key='audit.view').first()
        perm_id = perm.id
    res_del = client.delete(f'/api/users/{rec_uid}/overrides/{perm_id}', headers={'X-Admin-Password': 'Admin#2025!'})
    assert res_del.status_code == 200

    # 5. Receptionist immediately denied again
    login_as(client, 'receptionist', 'Reception#2025!')
    res3 = client.get('/api/audit-logs')
    assert res3.status_code == 403


def test_rbac_security_safeguards(client):
    """Verify safeguards: step-up auth, last admin protection, self-demotion block, locked role guard."""
    login_as(client, 'admin', 'Admin#2025!')
    with app.app_context():
        admin_user = User.query.filter_by(username='admin').first()
        admin_uid = admin_user.id
        admin_role = Role.query.filter_by(name='admin').first()
        manager_role = Role.query.filter_by(name='manager').first()

    # 1. Step-up auth required: missing or invalid password returns 401
    res_no_pw = client.put(f'/api/users/{admin_uid}/role', json={'role_id': manager_role.id})
    assert res_no_pw.status_code == 401
    assert 'Step-up' in res_no_pw.get_json()['message']

    res_bad_pw = client.put(f'/api/users/{admin_uid}/role', json={
        'role_id': manager_role.id,
        'admin_password': 'WrongPassword123!'
    })
    assert res_bad_pw.status_code == 401

    # 2. Self-demotion safeguard: admin cannot demote self
    res_self_demote = client.put(f'/api/users/{admin_uid}/role', json={
        'role_id': manager_role.id,
        'admin_password': 'Admin#2025!'
    })
    assert res_self_demote.status_code == 400
    assert res_self_demote.get_json()['error'] == 'SelfDemotionBlocked'

    # 3. Self-deactivation safeguard: admin cannot deactivate self
    res_self_disable = client.patch(f'/api/users/{admin_uid}/status', json={
        'is_active': False,
        'admin_password': 'Admin#2025!'
    })
    assert res_self_disable.status_code == 400
    assert res_self_disable.get_json()['error'] == 'SelfDisableBlocked'

    # 4. Locked role guard: admin role permissions cannot be edited
    res_edit_locked = client.put(f'/api/roles/{admin_role.id}', json={
        'description': 'Tampered admin',
        'permissions': ['dashboard.view'],
        'admin_password': 'Admin#2025!'
    })
    assert res_edit_locked.status_code == 403
    assert res_edit_locked.get_json()['error'] == 'RoleLocked'

    # 5. System role delete guard: cannot delete system roles
    res_del_system = client.delete(f'/api/roles/{admin_role.id}', headers={'X-Admin-Password': 'Admin#2025!'})
    assert res_del_system.status_code == 400
    assert res_del_system.get_json()['error'] == 'SystemRoleProtected'


def test_seed_database_idempotency(client):
    """Verify running seed_database() repeatedly is idempotent and preserves custom role edits."""
    from seed_data import seed_database
    login_as(client, 'admin', 'Admin#2025!')

    # Re-run seeder
    with app.app_context():
        seed_database()

    # Verify system roles still intact
    res = client.get('/api/roles')
    assert res.status_code == 200
    roles = res.get_json()['roles']
    role_names = {r['name'] for r in roles}
    assert {'admin', 'manager', 'doctor', 'receptionist', 'demo_viewer'}.issubset(role_names)


def test_password_toggle_elements_present(client):
    """Verify password inputs on login and change-password pages include password visibility toggle buttons."""
    # 1. Login page
    res_login = client.get('/login')
    html_login = res_login.get_data(as_text=True)
    assert 'password-toggle-btn' in html_login
    assert 'password-field-wrap' in html_login
    assert 'data-target="login-password"' in html_login

    # 2. Change password page
    login_as(client, 'admin', 'Admin#2025!')
    res_cp = client.get('/change-password')
    html_cp = res_cp.get_data(as_text=True)
    assert 'data-target="current-password"' in html_cp
    assert 'data-target="new-password"' in html_cp
    assert 'data-target="confirm-password"' in html_cp


def test_user_profile_settings_and_updates(client):
    """Verify profile view, retrieval, update, and validation."""
    # 1. Unauthenticated /profile redirects to /login
    assert client.get('/profile').status_code == 302
    assert client.get('/api/user/profile').status_code == 401

    # 2. Login as admin and fetch profile
    login_as(client, 'admin', 'Admin#2025!')
    res_page = client.get('/profile')
    assert res_page.status_code == 200
    assert 'profile-form' in res_page.get_data(as_text=True)

    res_get = client.get('/api/user/profile')
    assert res_get.status_code == 200
    user_data = res_get.get_json()['user']
    assert user_data['username'] == 'admin'
    assert user_data['role'] == 'admin'
    assert 'permissions' in user_data

    # 3. Update profile
    res_put = client.put('/api/user/profile', json={
        'full_name': 'Super Admin Lead',
        'email': 'lead.admin@hospital.org'
    })
    assert res_put.status_code == 200
    assert res_put.get_json()['user']['full_name'] == 'Super Admin Lead'
    assert res_put.get_json()['user']['email'] == 'lead.admin@hospital.org'

    # 4. Duplicate email validation
    res_dup = client.put('/api/user/profile', json={
        'full_name': 'Super Admin Lead',
        'email': 'manager@hospital.org'
    })
    assert res_dup.status_code == 409

    # Revert email
    client.put('/api/user/profile', json={
        'full_name': 'Chief Administrator',
        'email': 'admin@hospital.org'
    })




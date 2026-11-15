"""
test_system.py - Comprehensive Unit & Integration Tests for MediOptim Pro
Run with: pytest tests/test_system.py
"""

import pytest
import os
import sys

# Add root directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app, limiter
from models import db, Department, Doctor, Patient, Room, Bed, Equipment, Appointment, User
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

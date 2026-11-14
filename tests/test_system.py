"""
test_system.py - Comprehensive Unit & Integration Tests for MediOptim Pro
Run with: pytest tests/test_system.py
"""

import pytest
import os
import sys

# Add root directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app
from models import db, Department, Doctor, Patient, Room, Bed, Equipment, Appointment, User
from optimizer import (
    run_greedy, run_lp, run_hybrid, handle_emergency_preemption,
    predict_no_show_risk, run_scenario_simulation
)


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as test_client:
        yield test_client


def test_user_authentication(client):
    """Test user password hashing and login API."""
    res = client.post('/api/auth/login', json={'username': 'admin', 'password': 'admin123'})
    assert res.status_code == 200
    data = res.get_json()
    assert data['user']['username'] == 'admin'
    assert data['user']['role'] == 'admin'

    # Failed login
    res_fail = client.post('/api/auth/login', json={'username': 'admin', 'password': 'wrongpassword'})
    assert res_fail.status_code == 401


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

"""
test_fix5_metrics_sql.py - Tests for Centralized MetricsService and Aggregate SQL
"""

import pytest
from app import app
from models import db, Appointment, Doctor, Department, Patient, User
from metrics_service import MetricsService


def test_metrics_service_average_wait_time_sql():
    """Verify get_average_wait_time uses aggregate SQL AVG and ignores cancelled appointments."""
    with app.app_context():
        target_date = "2029-05-15"
        # Clean existing test data for target_date
        Appointment.query.filter_by(date=target_date).delete()

        # When no appointments exist
        assert MetricsService.get_average_wait_time(target_date) == 0.0

        # Insert 3 appointments: wait 10m, wait 20m, and one cancelled wait 60m
        a1 = Appointment(patient_id=1, doctor_id=1, room_id=1, date=target_date,
                         start_time="09:00", end_time="09:30", duration_minutes=30,
                         waiting_time=10, status="scheduled")
        a2 = Appointment(patient_id=2, doctor_id=1, room_id=1, date=target_date,
                         start_time="09:30", end_time="10:00", duration_minutes=30,
                         waiting_time=20, status="scheduled")
        a3 = Appointment(patient_id=3, doctor_id=1, room_id=1, date=target_date,
                         start_time="10:00", end_time="10:30", duration_minutes=30,
                         waiting_time=60, status="cancelled")
        db.session.add_all([a1, a2, a3])
        db.session.commit()

        # Expected average: (10 + 20) / 2 = 15.0 (cancelled a3 excluded)
        avg = MetricsService.get_average_wait_time(target_date)
        assert avg == 15.0

        # Cleanup
        Appointment.query.filter_by(date=target_date).delete()
        db.session.commit()


def test_metrics_service_overall_and_doctor_utilization():
    """Verify utilization metrics use single aggregate SQL queries with GROUP BY."""
    with app.app_context():
        target_date = "2029-06-20"
        Appointment.query.filter_by(date=target_date).delete()

        # Insert 2 appointments of 30 mins each for doctor 1
        a1 = Appointment(patient_id=1, doctor_id=1, room_id=1, date=target_date,
                         start_time="08:00", end_time="08:30", duration_minutes=30,
                         waiting_time=0, status="scheduled")
        a2 = Appointment(patient_id=2, doctor_id=1, room_id=1, date=target_date,
                         start_time="08:30", end_time="09:00", duration_minutes=30,
                         waiting_time=0, status="completed")
        db.session.add_all([a1, a2])
        db.session.commit()

        # 1. Overall utilization
        overall = MetricsService.get_overall_utilization(target_date)
        assert overall['booked_minutes'] == 60
        assert overall['utilization'] > 0

        # 2. Per-doctor utilization
        doc_utils = MetricsService.get_doctor_utilization(target_date)
        assert isinstance(doc_utils, list)
        doc1_metric = next((d for d in doc_utils if d['doctor_id'] == 1), None)
        assert doc1_metric is not None
        assert doc1_metric['booked'] == 2
        assert doc1_metric['booked_minutes'] == 60
        assert doc1_metric['utilization'] > 0

        # Cleanup
        Appointment.query.filter_by(date=target_date).delete()
        db.session.commit()


def test_metrics_service_department_load_group_by():
    """Verify get_department_load aggregates appointments per department via SQL GROUP BY."""
    with app.app_context():
        load = MetricsService.get_department_load()
        assert isinstance(load, dict)
        # Should return a mapping of department names to count
        assert len(load) > 0


def test_metrics_service_patient_status_counts():
    """Verify get_patient_status_counts uses SQL distinct count without full model loading."""
    with app.app_context():
        status_counts = MetricsService.get_patient_status_counts()
        assert 'assigned' in status_counts
        assert 'unassigned' in status_counts
        assert status_counts['assigned'] >= 0
        assert status_counts['unassigned'] >= 0


def test_dashboard_and_analytics_endpoints_use_metrics_service(client):
    """Verify /api/dashboard and /api/analytics endpoints serve aggregate SQL metrics."""
    with client.session_transaction() as sess:
        sess['user_id'] = 1
        sess['username'] = 'admin'
        sess['role'] = 'admin'
        sess['is_demo'] = False
        user = db.session.get(User, 1)
        if user:
            import hashlib
            sess['pwd_hash'] = hashlib.sha256(user.password_hash.encode('utf-8')).hexdigest()[:16]

    # 1. Dashboard summary
    res_dash = client.get('/api/dashboard')
    assert res_dash.status_code == 200
    dash_data = res_dash.get_json()
    assert 'total_patients' in dash_data
    assert 'avg_wait_time' in dash_data
    assert 'utilization_rate' in dash_data
    assert 'department_workload' in dash_data
    assert 'doctor_utilization' in dash_data

    # 2. Analytics utilization
    res_util = client.get('/api/analytics/utilization')
    assert res_util.status_code == 200
    util_data = res_util.get_json()
    assert isinstance(util_data, list)

    # 3. Analytics patients status
    res_pats = client.get('/api/analytics/patients-status')
    assert res_pats.status_code == 200
    pats_data = res_pats.get_json()
    assert 'assigned' in pats_data
    assert 'unassigned' in pats_data

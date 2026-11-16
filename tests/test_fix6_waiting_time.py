"""
test_fix6_waiting_time.py - Tests for Waiting Time Definition and Crisis Simulator Alignment
"""

import pytest
from datetime import datetime
from app import app
from models import db, Doctor, Patient, Room, Appointment
from optimizer import calculate_waiting_time, time_to_minutes, run_scenario_simulation
from metrics_service import MetricsService


class DummyDoctor:
    def __init__(self, start="08:00", until="17:00"):
        self.available_from = start
        self.available_until = until


class DummyPatient:
    def __init__(self, registered_at=None, arrival_time=None):
        self.registered_at = registered_at
        self.arrival_time = arrival_time


def test_waiting_time_when_arrival_known_before_shift():
    """When arrival is before doctor shift start, wait is measured from shift start."""
    doc = DummyDoctor(start="08:00")  # 480 mins
    target_date = "2025-10-10"

    # Patient registered at 07:15 (435 mins)
    pat = DummyPatient(registered_at=f"{target_date}T07:15:00")
    slot_start = time_to_minutes("08:30")  # 510 mins

    # Wait = slot_start - max(arrival, shift_start) = 510 - max(435, 480) = 510 - 480 = 30 mins
    wait = calculate_waiting_time(pat, doc, slot_start, target_date)
    assert wait == 30


def test_waiting_time_when_arrival_known_after_shift_start():
    """When arrival is after shift start, wait is measured from patient arrival."""
    doc = DummyDoctor(start="08:00")  # 480 mins
    target_date = "2025-10-10"

    # Patient registered at 09:15 (555 mins)
    pat = DummyPatient(registered_at=f"{target_date}T09:15:00")
    slot_start = time_to_minutes("09:45")  # 585 mins

    # Wait = slot_start - max(arrival, shift_start) = 585 - max(555, 480) = 585 - 555 = 30 mins
    wait = calculate_waiting_time(pat, doc, slot_start, target_date)
    assert wait == 30


def test_waiting_time_when_arrival_unknown_never_measures_from_midnight():
    """When arrival is unknown, wait is measured from shift start, NEVER from midnight (00:00)."""
    doc = DummyDoctor(start="08:00")  # 480 mins
    target_date = "2025-10-10"

    # Unknown arrival (no registered_at, or registered on previous day)
    pat = DummyPatient(registered_at=None)
    slot_start = time_to_minutes("09:00")  # 540 mins

    # Wait = slot_start - shift_start = 540 - 480 = 60 mins (NOT 540 - 0 = 540 mins!)
    wait = calculate_waiting_time(pat, doc, slot_start, target_date)
    assert wait == 60
    assert wait < 120, f"Wait time {wait} indicates baseline was measured from midnight instead of shift start!"


def test_waiting_time_never_negative():
    """When slot is at or before shift start/arrival, waiting time is 0."""
    doc = DummyDoctor(start="08:00")  # 480 mins
    target_date = "2025-10-10"
    pat = DummyPatient(registered_at=None)

    slot_start = time_to_minutes("08:00")
    wait = calculate_waiting_time(pat, doc, slot_start, target_date)
    assert wait == 0


def test_simulator_wait_time_uses_consistent_definition():
    """Verify crisis scenario simulator baseline and crisis average wait times are realistic."""
    with app.app_context():
        patients = Patient.query.all()
        doctors = Doctor.query.all()
        rooms = Room.query.all()

        if patients and doctors and rooms:
            sim_res = run_scenario_simulation(
                patients, doctors, rooms, "2025-10-10",
                absent_doctor_ids=[doctors[0].id] if len(doctors) > 1 else [],
                patient_surge_percent=20
            )

            b_wait = sim_res['baseline']['avg_wait_time']
            c_wait = sim_res['crisis']['avg_wait_time']

            # Realistic hospital average wait times are typically between 0 and 180 minutes, never 500+ mins
            assert 0 <= b_wait < 180, f"Baseline average wait time {b_wait} is unrealistic (likely measured from midnight)"
            assert 0 <= c_wait < 240, f"Crisis average wait time {c_wait} is unrealistic"
            assert 'wait_time_delta' in sim_res['impact']


def test_metrics_service_wait_time_by_priority_aggregate_sql():
    """Verify MetricsService.get_wait_time_by_priority returns dictionary for all priorities."""
    with app.app_context():
        by_prio = MetricsService.get_wait_time_by_priority()
        assert set(by_prio.keys()) == {'critical', 'urgent', 'normal', 'low'}
        for prio, val in by_prio.items():
            assert isinstance(val, (int, float))
            assert val >= 0.0

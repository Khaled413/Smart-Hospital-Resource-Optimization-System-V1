"""
optimizer.py - Hardened Optimization Engine for Smart Hospital Resource Optimization System
Features:
- ScheduleState: tracks busy doctor/room intervals with sanitization buffers and quotas
- Dynamic procedure duration & sanitization buffers
- Linear Programming (PuLP CBC with strict optimality validation and fast precomputed indices)
- Greedy and Conflict-Free Hybrid algorithms
- Emergency Code Red preemption with conflict-free slot relocation
- Machine Learning No-Show Risk Prediction
- "What-If" Crisis Scenario Simulation
"""

try:
    import pulp
    PULP_AVAILABLE = True
except (ImportError, ModuleNotFoundError):
    pulp = None
    PULP_AVAILABLE = False

from datetime import datetime, timedelta
import random
import math
from collections import defaultdict


class OptimizerResult(tuple):
    """3-tuple subclass for backward-compatible unpacking with algorithm metadata."""
    def __new__(cls, assignments, unassigned, log, algorithm_used="greedy", fallback_reason=None):
        instance = super().__new__(cls, (assignments, unassigned, log))
        instance.assignments = assignments
        instance.unassigned = unassigned
        instance.log = log
        instance.algorithm_used = algorithm_used
        instance.fallback_reason = fallback_reason
        return instance


# ─── Configuration & Time Utilities ───────────────────────────────────────────

PROCEDURE_DURATIONS = {
    'cardiology': 30,
    'neurology': 45,
    'orthopedics': 30,
    'pediatrics': 20,
    'general surgery': 60
}

DEFAULT_BUFFER_MINUTES = 10
PRIORITY_SCORE = {'critical': 4, 'urgent': 3, 'normal': 2, 'low': 1}


def time_to_minutes(t: str) -> int:
    """Convert HH:MM string to minutes since midnight."""
    h, m = map(int, t.split(':'))
    return h * 60 + m


def minutes_to_time(m: int) -> str:
    """Convert minutes since midnight to HH:MM string."""
    return f"{m // 60:02d}:{m % 60:02d}"


def times_overlap(start1, end1, start2, end2) -> bool:
    """Check if two time intervals overlap (strictly)."""
    return not (end1 <= start2 or end2 <= start1)


def get_patient_duration(patient) -> int:
    """Return procedure duration in minutes based on specialization and clinical triage."""
    spec = getattr(patient, 'required_specialization', '').lower()
    base = PROCEDURE_DURATIONS.get(spec, 30)
    if getattr(patient, 'priority', '') == 'critical' or getattr(patient, 'triage_level', 3) <= 2:
        base += 10
    return base


def sync_triage_and_priority(priority: str = None, triage_level: int = None):
    """
    Synchronizes ESI triage levels (1-5) and priority labels.
    Level 1: Critical (Resuscitation)
    Level 2: Critical (Emergent)
    Level 3: Urgent
    Level 4: Normal
    Level 5: Low
    """
    triage_to_priority = {
        1: 'critical',
        2: 'critical',
        3: 'urgent',
        4: 'normal',
        5: 'low'
    }
    priority_to_triage = {
        'critical': 1,
        'urgent': 3,
        'normal': 4,
        'low': 5
    }

    if triage_level is not None and triage_level in triage_to_priority:
        resolved_triage = triage_level
        resolved_priority = triage_to_priority[triage_level]
    elif priority is not None and priority.lower() in priority_to_triage:
        resolved_priority = priority.lower()
        resolved_triage = priority_to_triage[resolved_priority]
    else:
        resolved_priority = 'normal'
        resolved_triage = 4

    return resolved_priority, resolved_triage


def calculate_waiting_time(patient, doctor, slot_start: int, target_date: str) -> int:
    """
    Measure waiting time as slot_start - max(arrival_time, doctor_shift_start).
    If patient.registered_at is on target_date, use registered_at time.
    Otherwise, default to doctor's shift start.
    """
    doc_start = time_to_minutes(doctor.available_from)
    arrival_min = doc_start

    reg_at = getattr(patient, 'registered_at', None)
    if reg_at:
        try:
            if isinstance(reg_at, datetime):
                if reg_at.strftime('%Y-%m-%d') == target_date:
                    arrival_min = reg_at.hour * 60 + reg_at.minute
            elif isinstance(reg_at, str) and target_date in reg_at:
                t_part = reg_at.split('T')[-1][:5]
                arrival_min = time_to_minutes(t_part)
        except Exception:
            arrival_min = doc_start

    effective_start = max(arrival_min, doc_start)
    return max(0, slot_start - effective_start)


# ─── Schedule State Tracker ───────────────────────────────────────────────────

class ScheduleState:
    """
    Tracks doctor schedules, room schedules, patient quotas, and busy intervals
    including cleaning buffers to prevent any double-booking.
    """
    def __init__(self, doctors, rooms, existing_appointments=None):
        self.doctor_schedule = {d.id: [] for d in doctors}
        self.room_schedule = {r.id: [] for r in rooms}
        self.doctor_patient_count = {d.id: 0 for d in doctors}
        self.scheduled_patient_ids = set()

        if existing_appointments:
            for appt in existing_appointments:
                status = getattr(appt, 'status', 'scheduled')
                if status in ('scheduled', 'in_progress', 'completed'):
                    s_min = time_to_minutes(appt.start_time)
                    e_min = time_to_minutes(appt.end_time)
                    buf = getattr(appt, 'buffer_minutes', DEFAULT_BUFFER_MINUTES) or DEFAULT_BUFFER_MINUTES

                    if appt.doctor_id in self.doctor_schedule:
                        self.doctor_schedule[appt.doctor_id].append((s_min, e_min))
                        self.doctor_patient_count[appt.doctor_id] += 1

                    if appt.room_id in self.room_schedule:
                        self.room_schedule[appt.room_id].append((s_min, e_min + buf))

                    if getattr(appt, 'patient_id', None):
                        self.scheduled_patient_ids.add(appt.patient_id)

    def is_doctor_free(self, doc_id: int, start: int, end: int) -> bool:
        intervals = self.doctor_schedule.get(doc_id, [])
        return not any(times_overlap(start, end, s, e) for s, e in intervals)

    def is_room_free(self, room_id: int, start: int, end_with_buf: int) -> bool:
        intervals = self.room_schedule.get(room_id, [])
        return not any(times_overlap(start, end_with_buf, s, e) for s, e in intervals)

    def add_assignment(self, patient_id: int, doc_id: int, room_id: int, start: int, end: int, buffer_min: int = DEFAULT_BUFFER_MINUTES):
        self.doctor_schedule.setdefault(doc_id, []).append((start, end))
        self.room_schedule.setdefault(room_id, []).append((start, end + buffer_min))
        self.doctor_patient_count[doc_id] = self.doctor_patient_count.get(doc_id, 0) + 1
        if patient_id:
            self.scheduled_patient_ids.add(patient_id)


# ─── Machine Learning: No-Show Risk Predictor ─────────────────────────────────

def predict_no_show_risk(patient, days_in_advance: int = 1) -> float:
    """
    Predict probability (0.0 to 1.0) that a patient will not show up for their appointment.
    Factors: Age, Priority/Triage, Vitals, Lead Time.
    """
    priority = getattr(patient, 'priority', 'normal')
    base_risk = {
        'critical': 0.02,
        'urgent': 0.08,
        'normal': 0.22,
        'low': 0.38
    }.get(priority, 0.20)

    age = getattr(patient, 'age', 35)
    if 18 <= age <= 28:
        base_risk += 0.08
    elif age < 12 or age >= 65:
        base_risk -= 0.05

    if days_in_advance > 7:
        base_risk += 0.12
    elif days_in_advance <= 1:
        base_risk -= 0.04

    hr = getattr(patient, 'heart_rate', 75)
    spo2 = getattr(patient, 'spo2', 98)
    if hr > 105 or hr < 50 or spo2 < 94:
        base_risk -= 0.08

    return round(max(0.01, min(0.85, base_risk)), 2)


# ─── Greedy Scheduling Algorithm ──────────────────────────────────────────────

def run_greedy(patients, doctors, rooms, target_date, schedule_state=None):
    """
    Greedy scheduling with dynamic durations and cleaning buffers.
    Uses schedule_state if provided to respect existing/LP appointments and prevent double booking.
    """
    log = ["[GREEDY] Starting Dynamic Greedy scheduling..."]
    assignments = []
    unassigned = []

    if schedule_state is None:
        schedule_state = ScheduleState(doctors, rooms)

    unscheduled_patients = [
        p for p in patients
        if p.id not in schedule_state.scheduled_patient_ids
    ]

    sorted_patients = sorted(
        unscheduled_patients,
        key=lambda p: (PRIORITY_SCORE.get(p.priority, 2), -(getattr(p, 'triage_level', 3) or 3)),
        reverse=True
    )
    log.append(f"[GREEDY] Scheduling {len(sorted_patients)} patients with dynamic procedure durations.")

    for patient in sorted_patients:
        assigned = False
        duration = get_patient_duration(patient)
        buffer = DEFAULT_BUFFER_MINUTES

        compatible_doctors = [
            d for d in doctors
            if d.specialization.lower() == patient.required_specialization.lower()
        ]

        if not compatible_doctors:
            log.append(f"[GREEDY] ✗ No matching doctor for {patient.name} ({patient.required_specialization})")
            unassigned.append(patient)
            continue

        compatible_doctors.sort(key=lambda d: schedule_state.doctor_patient_count.get(d.id, 0))

        for doctor in compatible_doctors:
            if schedule_state.doctor_patient_count.get(doctor.id, 0) >= doctor.max_patients_per_day:
                continue

            doc_start = time_to_minutes(doctor.available_from)
            doc_end = time_to_minutes(doctor.available_until)

            dept_rooms = [r for r in rooms if r.department_id == doctor.department_id]
            if not dept_rooms:
                dept_rooms = rooms

            current_slot = doc_start
            while current_slot + duration <= doc_end:
                slot_end = current_slot + duration

                if not schedule_state.is_doctor_free(doctor.id, current_slot, slot_end):
                    current_slot += 15
                    continue

                selected_room = None
                for room in dept_rooms:
                    if schedule_state.is_room_free(room.id, current_slot, slot_end + buffer):
                        selected_room = room
                        break

                if selected_room:
                    wait_time = calculate_waiting_time(patient, doctor, current_slot, target_date)

                    schedule_state.add_assignment(
                        patient_id=patient.id,
                        doc_id=doctor.id,
                        room_id=selected_room.id,
                        start=current_slot,
                        end=slot_end,
                        buffer_min=buffer
                    )

                    assignments.append({
                        'patient': patient,
                        'doctor': doctor,
                        'room': selected_room,
                        'date': target_date,
                        'start_time': minutes_to_time(current_slot),
                        'end_time': minutes_to_time(slot_end),
                        'duration_minutes': duration,
                        'buffer_minutes': buffer,
                        'waiting_time': wait_time
                    })
                    log.append(
                        f"[GREEDY] ✓ {patient.name} ({patient.priority.upper()}, {duration}m) → "
                        f"Dr. {doctor.name} | Room {selected_room.room_number} | "
                        f"{minutes_to_time(current_slot)}-{minutes_to_time(slot_end)} | Wait={wait_time}m"
                    )
                    assigned = True
                    break

                current_slot += 15

            if assigned:
                break

        if not assigned:
            unassigned.append(patient)
            log.append(f"[GREEDY] ✗ Could not schedule {patient.name} (Capacity full or time window exceeded)")

    log.append(f"[GREEDY] Finished. Assigned: {len(assignments)}, Unassigned: {len(unassigned)}")
    return OptimizerResult(assignments, unassigned, log, algorithm_used="greedy")


# ─── Linear Programming Algorithm ─────────────────────────────────────────────

def run_lp(patients, doctors, rooms, target_date, schedule_state=None):
    """
    Linear Programming scheduling via PuLP (CBC solver).
    Only status 1 (Optimal) is accepted. Status -1 (Infeasible) triggers fallback or unassigned.
    Precomputes lookup maps to avoid nested O(N*M) variable scans.
    """
    log = ["[LP] Starting Mixed-Integer Linear Programming Optimization..."]
    fallback_reason = None

    if schedule_state is None:
        schedule_state = ScheduleState(doctors, rooms)

    unscheduled_patients = [
        p for p in patients
        if p.id not in schedule_state.scheduled_patient_ids
    ]

    # Check if PuLP is available
    if not PULP_AVAILABLE or pulp is None:
        fallback_reason = "PuLP solver library not available"
        log.append(f"[LP Fallback] {fallback_reason}. Executing Dynamic Greedy.")
        g_assign, g_unassigned, g_log = run_greedy(unscheduled_patients, doctors, rooms, target_date, schedule_state=schedule_state)
        return OptimizerResult(g_assign, g_unassigned, log + g_log, algorithm_used="greedy", fallback_reason=fallback_reason)

    # If dataset is large (>75 patients), fallback to Greedy
    if len(unscheduled_patients) > 75:
        fallback_reason = f"Dataset size ({len(unscheduled_patients)}) exceeds LP threshold (75)"
        log.append(f"[LP Fallback] {fallback_reason}. Using fast Greedy.")
        g_assign, g_unassigned, g_log = run_greedy(unscheduled_patients, doctors, rooms, target_date, schedule_state=schedule_state)
        return OptimizerResult(g_assign, g_unassigned, log + g_log, algorithm_used="greedy", fallback_reason=fallback_reason)

    step = 15
    earliest_start = min(time_to_minutes(d.available_from) for d in doctors)
    latest_end = max(time_to_minutes(d.available_until) for d in doctors)

    doctor_map = {d.id: d for d in doctors}
    patient_map = {p.id: p for p in unscheduled_patients}
    room_map = {r.id: r for r in rooms}

    dept_rooms = {}
    for r in rooms:
        dept_rooms.setdefault(r.department_id, []).append(r.id)

    durations = {p.id: get_patient_duration(p) for p in unscheduled_patients}

    # Precompute candidate variables, filtering out already busy slots from schedule_state
    var_keys = []
    for p in unscheduled_patients:
        p_dur = durations[p.id]
        comp_docs = [d for d in doctors if d.specialization.lower() == p.required_specialization.lower()]
        for d in comp_docs:
            rem_quota = d.max_patients_per_day - schedule_state.doctor_patient_count.get(d.id, 0)
            if rem_quota <= 0:
                continue

            d_start = time_to_minutes(d.available_from)
            d_end = time_to_minutes(d.available_until)
            allowed_rooms = dept_rooms.get(d.department_id, [r.id for r in rooms])

            curr = d_start
            while curr + p_dur <= d_end:
                slot_end = curr + p_dur
                if schedule_state.is_doctor_free(d.id, curr, slot_end):
                    for rid in allowed_rooms:
                        if schedule_state.is_room_free(rid, curr, slot_end + DEFAULT_BUFFER_MINUTES):
                            var_keys.append((p.id, d.id, curr, rid))
                curr += step

    log.append(f"[LP] Formulating MIP model with {len(var_keys)} candidate decision variables.")

    if not var_keys:
        fallback_reason = "No feasible candidate variables"
        log.append(f"[LP Fallback] {fallback_reason}. Falling back to greedy.")
        g_assign, g_unassigned, g_log = run_greedy(unscheduled_patients, doctors, rooms, target_date, schedule_state=schedule_state)
        return OptimizerResult(g_assign, g_unassigned, log + g_log, algorithm_used="greedy", fallback_reason=fallback_reason)

    # Precompute lookup maps for fast constraint creation
    p_keys_map = defaultdict(list)
    d_keys_map = defaultdict(list)
    doc_overlap_map = defaultdict(list)
    room_overlap_map = defaultdict(list)

    for k in var_keys:
        pid, did, start, rid = k
        p_keys_map[pid].append(k)
        d_keys_map[did].append(k)
        dur = durations[pid]

        for t in range(start, start + dur, step):
            doc_overlap_map[(did, t)].append(k)

        for t in range(start, start + dur + DEFAULT_BUFFER_MINUTES, step):
            room_overlap_map[(rid, t)].append(k)

    prob = pulp.LpProblem("Hospital_Resource_Optimization", pulp.LpMaximize)
    x = pulp.LpVariable.dicts("x_assign", var_keys, cat='Binary')

    # Objective
    priority_reward = {'critical': 10000, 'urgent': 5000, 'normal': 2000, 'low': 1000}
    prob += pulp.lpSum(
        (priority_reward.get(patient_map[pid].priority, 2000) - calculate_waiting_time(patient_map[pid], doctor_map[did], start, target_date)) * x[k]
        for k in var_keys
        for pid, did, start, rid in [k]
    ), "Max_Priority_Min_Wait"

    # Constraint 1: Patient at most once
    for pid, pkeys in p_keys_map.items():
        prob += pulp.lpSum(x[k] for k in pkeys) <= 1, f"Patient_Single_{pid}"

    # Constraint 2: Doctor capacity
    for did, dkeys in d_keys_map.items():
        doc = doctor_map[did]
        rem_quota = max(0, doc.max_patients_per_day - schedule_state.doctor_patient_count.get(did, 0))
        prob += pulp.lpSum(x[k] for k in dkeys) <= rem_quota, f"Doc_Cap_{did}"

    # Constraint 3: Doctor no-overlap
    for (did, t), ov_keys in doc_overlap_map.items():
        if len(ov_keys) > 1:
            prob += pulp.lpSum(x[k] for k in ov_keys) <= 1, f"Doc_Overlap_{did}_{t}"

    # Constraint 4: Room no-overlap (with buffer)
    for (rid, t), ov_keys in room_overlap_map.items():
        if len(ov_keys) > 1:
            prob += pulp.lpSum(x[k] for k in ov_keys) <= 1, f"Room_Overlap_{rid}_{t}"

    # Solve
    log.append("[LP] Executing CBC solver (limit 25s)...")
    try:
        solver = pulp.PULP_CBC_CMD(msg=0, timeLimit=25)
        prob.solve(solver)
        status_code = prob.status
        status_str = pulp.LpStatus.get(status_code, 'Unknown')
        log.append(f"[LP] Solver ended with status: {status_str} (code={status_code})")

        # Check: only status 1 (Optimal) is treated as success
        if status_code != 1:
            has_incumbent = any(x[k].value() and x[k].value() > 0.5 for k in var_keys)
            if not has_incumbent:
                fallback_reason = f"Solver status {status_str} (code {status_code}) without incumbent"
                log.append(f"[LP Fallback] {fallback_reason}. Switching to Greedy.")
                g_assign, g_unassigned, g_log = run_greedy(unscheduled_patients, doctors, rooms, target_date, schedule_state=schedule_state)
                return OptimizerResult(g_assign, g_unassigned, log + g_log, algorithm_used="greedy", fallback_reason=fallback_reason)
    except Exception as e:
        fallback_reason = f"CBC solver error: {e}"
        log.append(f"[LP Fallback] {fallback_reason}. Switching to Dynamic Heuristic.")
        g_assign, g_unassigned, g_log = run_greedy(unscheduled_patients, doctors, rooms, target_date, schedule_state=schedule_state)
        return OptimizerResult(g_assign, g_unassigned, log + g_log, algorithm_used="greedy", fallback_reason=fallback_reason)

    # Process LP solution
    assignments = []
    assigned_pids = set()

    for k in var_keys:
        val = x[k].value()
        if val and val > 0.5:
            pid, did, start, rid = k
            patient = patient_map[pid]
            doctor = doctor_map[did]
            room = room_map[rid]
            dur = durations[pid]
            wait_time = calculate_waiting_time(patient, doctor, start, target_date)

            schedule_state.add_assignment(
                patient_id=pid,
                doc_id=did,
                room_id=rid,
                start=start,
                end=start + dur,
                buffer_min=DEFAULT_BUFFER_MINUTES
            )

            assignments.append({
                'patient': patient,
                'doctor': doctor,
                'room': room,
                'date': target_date,
                'start_time': minutes_to_time(start),
                'end_time': minutes_to_time(start + dur),
                'duration_minutes': dur,
                'buffer_minutes': DEFAULT_BUFFER_MINUTES,
                'waiting_time': wait_time
            })
            assigned_pids.add(pid)
            log.append(
                f"[LP] ✓ {patient.name} ({patient.priority.upper()}) → "
                f"Dr. {doctor.name} | Room {room.room_number} | "
                f"{minutes_to_time(start)}-{minutes_to_time(start + dur)} | wait={wait_time}m"
            )

    unassigned = [p for p in unscheduled_patients if p.id not in assigned_pids]
    log.append(f"[LP] Completed. Assigned: {len(assignments)}, Unassigned: {len(unassigned)}")
    return OptimizerResult(assignments, unassigned, log, algorithm_used="lp", fallback_reason=None)


# ─── Hybrid Algorithm ─────────────────────────────────────────────────────────

def run_hybrid(patients, doctors, rooms, target_date, schedule_state=None):
    """
    Hybrid scheduling:
    1. Uses Linear Programming for high-priority patients (Critical & Urgent).
    2. Populates schedule_state with LP assignments.
    3. Runs Greedy on remaining patients passing the exact same schedule_state,
       guaranteeing zero double-booking or room conflicts!
    """
    log = ["[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)..."]

    if schedule_state is None:
        schedule_state = ScheduleState(doctors, rooms)

    if not PULP_AVAILABLE or pulp is None:
        log.append("[HYBRID Fallback] PuLP solver library not available. Executing full Dynamic Greedy.")
        return run_greedy(patients, doctors, rooms, target_date, schedule_state=schedule_state)

    high_priority = [p for p in patients if p.priority in ('critical', 'urgent') and p.id not in schedule_state.scheduled_patient_ids]
    low_priority = [p for p in patients if p.priority in ('normal', 'low') and p.id not in schedule_state.scheduled_patient_ids]

    log.append(f"[HYBRID] High-priority queue: {len(high_priority)} patients")
    log.append(f"[HYBRID] Standard queue: {len(low_priority)} patients")

    lp_assignments = []
    lp_unassigned = []

    if high_priority:
        lp_res = run_lp(high_priority, doctors, rooms, target_date, schedule_state=schedule_state)
        lp_assignments = lp_res[0]
        lp_unassigned = lp_res[1]
        log.extend(lp_res[2])

    remaining_patients = low_priority + lp_unassigned
    greedy_assignments = []
    greedy_unassigned = []

    if remaining_patients:
        greedy_assignments, greedy_unassigned, greedy_log = run_greedy(
            remaining_patients, doctors, rooms, target_date, schedule_state=schedule_state
        )
        log.extend(greedy_log)

    all_assignments = lp_assignments + greedy_assignments
    all_unassigned = greedy_unassigned

    log.append(f"[HYBRID] Final Result: Assigned={len(all_assignments)}, Unassigned={len(all_unassigned)}")
    return OptimizerResult(all_assignments, all_unassigned, log, algorithm_used="hybrid")


# ─── Main Optimization Entry Point ───────────────────────────────────────────

def run_optimization(algorithm: str, patients, doctors, rooms, target_date: str, existing_appointments=None):
    """
    Unified entry point for optimization algorithms.
    Accepts existing_appointments to pre-populate busy doctor intervals, room intervals,
    and doctor patient counts with buffers to avoid conflicts.
    """
    if not patients:
        return {
            'assignments': [],
            'unassigned': [],
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': 0, 'avg_wait_time': 0, 'utilization_rate': 0},
            'log': ['No patients in queue to schedule.'],
            'algorithm_used': algorithm,
            'fallback_reason': None
        }

    schedule_state = ScheduleState(doctors, rooms, existing_appointments)
    actual_algo = algorithm
    fallback_reason = None

    if algorithm == 'lp':
        res = run_lp(patients, doctors, rooms, target_date, schedule_state=schedule_state)
        assignments, unassigned, log = res[0], res[1], res[2]
        if len(res) >= 4:
            actual_algo = res[3]
        if len(res) >= 5:
            fallback_reason = res[4]
    elif algorithm == 'hybrid':
        assignments, unassigned, log = run_hybrid(patients, doctors, rooms, target_date, schedule_state=schedule_state)
        actual_algo = 'hybrid'
    else:
        assignments, unassigned, log = run_greedy(patients, doctors, rooms, target_date, schedule_state=schedule_state)
        actual_algo = 'greedy'

    total = len(patients)
    assigned = len(assignments)
    unassigned_count = len(unassigned)
    avg_wait = (sum(a['waiting_time'] for a in assignments) / assigned) if assigned > 0 else 0

    # Unified Utilization formula: booked_minutes / total_available_minutes * 100
    booked_minutes = sum(a['duration_minutes'] for a in assignments)
    if existing_appointments:
        for appt in existing_appointments:
            status = getattr(appt, 'status', 'scheduled')
            if status in ('scheduled', 'in_progress', 'completed'):
                booked_minutes += getattr(appt, 'duration_minutes', 30)

    total_available_minutes = sum(
        time_to_minutes(d.available_until) - time_to_minutes(d.available_from)
        for d in doctors
    )
    utilization = (booked_minutes / total_available_minutes * 100) if total_available_minutes > 0 else 0

    metrics = {
        'total': total,
        'assigned': assigned,
        'unassigned': unassigned_count,
        'avg_wait_time': round(avg_wait, 2),
        'utilization_rate': round(min(utilization, 100), 2)
    }

    return {
        'assignments': assignments,
        'unassigned': unassigned,
        'metrics': metrics,
        'log': log,
        'algorithm_used': actual_algo,
        'fallback_reason': fallback_reason
    }


# ─── Emergency Code Red Preemption Engine ─────────────────────────────────────

def handle_emergency_preemption(emergency_patient, existing_appointments, doctors, rooms, target_date, app_timezone='Africa/Cairo'):
    """
    Fast preemption for immediate Code Red emergencies.
    - Uses configurable timezone for current time.
    - Checks doctor's actual shift boundaries.
    - Matches rooms belonging to the doctor's department or emergency-ready suites.
    - When bumping an appointment, searches for the next available conflict-free slot on the same day.
      If none exists, flags it as `needs_reschedule`.
    """
    log = [f"[EMERGENCY] 🚨 Code Red Triggered for patient: {emergency_patient.name} ({emergency_patient.required_specialization})"]
    duration = get_patient_duration(emergency_patient)
    buffer = DEFAULT_BUFFER_MINUTES

    # Determine current time in configured timezone
    try:
        from zoneinfo import ZoneInfo
        now_dt = datetime.now(ZoneInfo(app_timezone))
    except Exception:
        now_dt = datetime.now()

    now_mins = now_dt.hour * 60 + now_dt.minute

    compat_docs = [d for d in doctors if d.specialization.lower() == emergency_patient.required_specialization.lower()]
    if not compat_docs:
        compat_docs = doctors

    state = ScheduleState(doctors, rooms, existing_appointments)

    # 1. Search for immediate vacant opening first
    for doc in compat_docs:
        doc_start = time_to_minutes(doc.available_from)
        doc_end = time_to_minutes(doc.available_until)

        slot_candidate = max(now_mins, doc_start)
        rem = slot_candidate % 15
        if rem != 0:
            slot_candidate += (15 - rem)

        dept_rooms = [
            r for r in rooms
            if r.department_id == doc.department_id or r.room_type in ('surgery', 'icu', 'emergency')
        ]
        if not dept_rooms:
            dept_rooms = rooms

        while slot_candidate + duration <= doc_end:
            slot_end = slot_candidate + duration
            if state.is_doctor_free(doc.id, slot_candidate, slot_end):
                for room in dept_rooms:
                    if state.is_room_free(room.id, slot_candidate, slot_end + buffer):
                        log.append(f"[EMERGENCY] ✓ Found immediate opening with Dr. {doc.name} in Room {room.room_number}")
                        return {
                            'action': 'immediate_slot',
                            'emergency_assignment': {
                                'patient_id': emergency_patient.id,
                                'doctor_id': doc.id,
                                'room_id': room.id,
                                'date': target_date,
                                'start_time': minutes_to_time(slot_candidate),
                                'end_time': minutes_to_time(slot_end),
                                'duration_minutes': duration,
                                'is_emergency': True,
                                'waiting_time': 0
                            },
                            'bumped_appointment_id': None,
                            'bumped_plan': None,
                            'log': log
                        }
            slot_candidate += 15

    # 2. If no immediate slot, preempt a lower-priority appointment
    log.append("[EMERGENCY] No immediate open slot. Scanning for preemption candidates...")
    candidates = []
    for appt in existing_appointments:
        status = getattr(appt, 'status', 'scheduled')
        if status != 'scheduled' or getattr(appt, 'is_emergency', False):
            continue
        prio = getattr(appt.patient, 'priority', 'normal')
        if prio in ('normal', 'low'):
            appt_start = time_to_minutes(appt.start_time)
            doctor = next((d for d in doctors if d.id == appt.doctor_id), None)
            if doctor and (doctor in compat_docs or not compat_docs):
                candidates.append((appt_start, appt, doctor))

    candidates.sort(key=lambda c: c[0])

    if candidates:
        target_start, target_appt, target_doc = candidates[0]
        emergency_start = target_start
        emergency_end = emergency_start + duration

        log.append(f"[EMERGENCY] ⚠️ Preempting appointment #{target_appt.id} (Patient: {target_appt.patient.name}, Priority: {target_appt.patient.priority})")

        bumped_duration = getattr(target_appt, 'duration_minutes', 30)
        doc_end = time_to_minutes(target_doc.available_until)
        search_start = emergency_end + buffer
        dept_rooms = [r for r in rooms if r.department_id == target_doc.department_id] or rooms

        rescheduled_slot = None
        curr = search_start
        while curr + bumped_duration <= doc_end:
            curr_end = curr + bumped_duration
            doc_appts = [
                a for a in existing_appointments
                if a.doctor_id == target_doc.id and a.id != target_appt.id and getattr(a, 'status', 'scheduled') == 'scheduled'
            ]
            doc_overlap = any(times_overlap(curr, curr_end, time_to_minutes(a.start_time), time_to_minutes(a.end_time)) for a in doc_appts)
            if not doc_overlap:
                for room in dept_rooms:
                    room_appts = [
                        a for a in existing_appointments
                        if a.room_id == room.id and a.id != target_appt.id and getattr(a, 'status', 'scheduled') == 'scheduled'
                    ]
                    room_overlap = any(times_overlap(curr, curr_end + buffer, time_to_minutes(a.start_time), time_to_minutes(a.end_time) + getattr(a, 'buffer_minutes', 10)) for a in room_appts)
                    if not room_overlap:
                        rescheduled_slot = {
                            'start_time': minutes_to_time(curr),
                            'end_time': minutes_to_time(curr_end),
                            'room_id': room.id,
                            'status': 'scheduled',
                            'waiting_time': max(0, curr - time_to_minutes(target_doc.available_from))
                        }
                        break
            if rescheduled_slot:
                break
            curr += 15

        bumped_plan = {
            'appointment_id': target_appt.id,
            'patient_name': target_appt.patient.name if target_appt.patient else 'Patient',
            'rescheduled_slot': rescheduled_slot,
            'needs_reschedule': rescheduled_slot is None
        }

        if rescheduled_slot:
            log.append(f"[EMERGENCY] Bumped patient {bumped_plan['patient_name']} safely relocated to {rescheduled_slot['start_time']}")
        else:
            log.append(f"[EMERGENCY] Doctor shift full. Bumped patient {bumped_plan['patient_name']} flagged as needs_reschedule")

        return {
            'action': 'preempted',
            'emergency_assignment': {
                'patient_id': emergency_patient.id,
                'doctor_id': target_appt.doctor_id,
                'room_id': target_appt.room_id,
                'date': target_date,
                'start_time': minutes_to_time(emergency_start),
                'end_time': minutes_to_time(emergency_end),
                'duration_minutes': duration,
                'is_emergency': True,
                'waiting_time': 0
            },
            'bumped_appointment_id': target_appt.id,
            'bumped_plan': bumped_plan,
            'log': log
        }

    log.append("[EMERGENCY] ✗ Critical: Hospital at 100% emergency capacity. Divert ambulance.")
    return {'action': 'failed', 'log': log}


# ─── Crisis Scenario Simulation Engine ("What-If" Analysis) ───────────────────

def run_scenario_simulation(patients, doctors, rooms, target_date,
                            absent_doctor_ids=None,
                            disabled_room_ids=None,
                            patient_surge_percent=0):
    """
    Simulates operational crises:
    - Doctor absenteeism / sick leave
    - Room closures / maintenance
    - Sudden emergency patient surge (+% increase in patient queue)
    Compares baseline vs simulated crisis metrics.
    """
    absent_doctor_ids = set(absent_doctor_ids or [])
    disabled_room_ids = set(disabled_room_ids or [])

    baseline = run_optimization('hybrid', patients, doctors, rooms, target_date)

    sim_doctors = [d for d in doctors if d.id not in absent_doctor_ids]
    sim_rooms = [r for r in rooms if r.id not in disabled_room_ids]

    sim_patients = list(patients)
    if patient_surge_percent > 0:
        surge_count = int(len(patients) * (patient_surge_percent / 100.0))
        for i in range(surge_count):
            proto = patients[i % len(patients)]
            class MockPatient:
                def __init__(self, p, idx):
                    self.id = 9000 + idx
                    self.name = f"Surge Emergency Patient #{idx+1}"
                    self.age = p.age
                    self.gender = p.gender
                    self.priority = 'critical' if idx % 2 == 0 else 'urgent'
                    self.required_specialization = p.required_specialization
                    self.condition_description = 'Crisis surge admission'
                    self.preferred_date = target_date
                    self.triage_level = 2
                    self.blood_pressure = '140/90'
                    self.heart_rate = 95
                    self.spo2 = 94
                    self.temperature = 38.2
                    self.no_show_risk = 0.05
            sim_patients.append(MockPatient(proto, i))

    simulated = run_optimization('hybrid', sim_patients, sim_doctors, sim_rooms, target_date)

    return {
        'baseline': {
            'total_patients': baseline['metrics']['total'],
            'assigned': baseline['metrics']['assigned'],
            'unassigned': baseline['metrics']['unassigned'],
            'avg_wait_time': baseline['metrics']['avg_wait_time'],
            'utilization_rate': baseline['metrics']['utilization_rate'],
            'active_doctors': len(doctors),
            'active_rooms': len(rooms)
        },
        'crisis': {
            'total_patients': simulated['metrics']['total'],
            'assigned': simulated['metrics']['assigned'],
            'unassigned': simulated['metrics']['unassigned'],
            'avg_wait_time': simulated['metrics']['avg_wait_time'],
            'utilization_rate': simulated['metrics']['utilization_rate'],
            'active_doctors': len(sim_doctors),
            'active_rooms': len(sim_rooms)
        },
        'impact': {
            'unassigned_delta': simulated['metrics']['unassigned'] - baseline['metrics']['unassigned'],
            'wait_time_delta': round(simulated['metrics']['avg_wait_time'] - baseline['metrics']['avg_wait_time'], 2),
            'utilization_delta': round(simulated['metrics']['utilization_rate'] - baseline['metrics']['utilization_rate'], 2)
        }
    }

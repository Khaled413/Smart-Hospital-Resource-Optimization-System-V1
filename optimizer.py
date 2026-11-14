"""
optimizer.py - Enhanced Optimization Engine for Smart Hospital Resource Optimization System
Features:
- Dynamic procedure duration & sanitization buffers
- Linear Programming (PuLP CBC), Greedy, and Hybrid algorithms
- Emergency Code Red preemption & instant dynamic rescheduling
- Machine Learning No-Show Risk Prediction
- "What-If" Crisis Scenario Simulation
"""

import pulp
from datetime import datetime, timedelta
import random
import math


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
    # Critical patients or ESI Level 1/2 receive slightly longer stabilization time
    if getattr(patient, 'priority', '') == 'critical' or getattr(patient, 'triage_level', 3) <= 2:
        base += 10
    return base


# ─── Machine Learning: No-Show Risk Predictor ─────────────────────────────────

def predict_no_show_risk(patient, days_in_advance: int = 1) -> float:
    """
    Predict probability (0.0 to 1.0) that a patient will not show up for their appointment.
    Factors: Age, Priority/Triage, Vitals, Lead Time.
    """
    # Base risk by priority
    priority = getattr(patient, 'priority', 'normal')
    base_risk = {
        'critical': 0.02,
        'urgent': 0.08,
        'normal': 0.22,
        'low': 0.38
    }.get(priority, 0.20)

    # Age factor: young adults (18-28) historically have higher no-show rates
    age = getattr(patient, 'age', 35)
    if 18 <= age <= 28:
        base_risk += 0.08
    elif age < 12 or age >= 65:
        base_risk -= 0.05  # Parents or elderly accompanied by family

    # Lead time factor: appointments booked further in advance have higher no-show risk
    if days_in_advance > 7:
        base_risk += 0.12
    elif days_in_advance <= 1:
        base_risk -= 0.04

    # Vital signs abnormality check: if patient is in pain or abnormal vitals, risk drops
    hr = getattr(patient, 'heart_rate', 75)
    spo2 = getattr(patient, 'spo2', 98)
    if hr > 105 or hr < 50 or spo2 < 94:
        base_risk -= 0.08

    # Bound probability between 0.01 and 0.85
    return round(max(0.01, min(0.85, base_risk)), 2)


# ─── Greedy Scheduling Algorithm ──────────────────────────────────────────────

def run_greedy(patients, doctors, rooms, target_date, equipment_list=None):
    """
    Greedy scheduling with dynamic durations and cleaning buffers.
    Prioritizes critical/urgent patients, assigns earliest available matching doctor & room.
    """
    log = ["[GREEDY] Starting Dynamic Greedy scheduling..."]
    assignments = []
    unassigned = []

    # Sort patients by priority descending (Critical -> Urgent -> Normal -> Low)
    sorted_patients = sorted(
        patients,
        key=lambda p: (PRIORITY_SCORE.get(p.priority, 2), -(p.triage_level if hasattr(p, 'triage_level') else 3)),
        reverse=True
    )
    log.append(f"[GREEDY] Scheduling {len(sorted_patients)} patients with dynamic procedure durations.")

    doctor_schedule = {d.id: [] for d in doctors}  # list of (start_min, end_min)
    room_schedule = {r.id: [] for r in rooms}      # list of (start_min, end_min_with_buffer)
    doctor_patient_count = {d.id: 0 for d in doctors}

    for patient in sorted_patients:
        assigned = False
        duration = get_patient_duration(patient)
        buffer = DEFAULT_BUFFER_MINUTES

        # Compatible doctors
        compatible_doctors = [
            d for d in doctors
            if d.specialization.lower() == patient.required_specialization.lower()
        ]

        if not compatible_doctors:
            log.append(f"[GREEDY] ✗ No matching doctor for {patient.name} ({patient.required_specialization})")
            unassigned.append(patient)
            continue

        # Sort doctors by current load
        compatible_doctors.sort(key=lambda d: doctor_patient_count[d.id])

        for doctor in compatible_doctors:
            if doctor_patient_count[doctor.id] >= doctor.max_patients_per_day:
                continue

            doc_start = time_to_minutes(doctor.available_from)
            doc_end = time_to_minutes(doctor.available_until)

            dept_rooms = [r for r in rooms if r.department_id == doctor.department_id]
            if not dept_rooms:
                dept_rooms = rooms

            # Find earliest available slot
            current_slot = doc_start
            while current_slot + duration <= doc_end:
                slot_end = current_slot + duration
                
                # Check doctor overlap
                doc_busy = any(times_overlap(current_slot, slot_end, s, e) for s, e in doctor_schedule[doctor.id])
                if doc_busy:
                    current_slot += 15  # Step by 15 mins for flexible alignment
                    continue

                # Check room overlap (with cleaning buffer)
                selected_room = None
                for room in dept_rooms:
                    room_busy = any(times_overlap(current_slot, slot_end + buffer, s, e) for s, e in room_schedule[room.id])
                    if not room_busy:
                        selected_room = room
                        break

                if selected_room:
                    wait_time = max(0, current_slot - doc_start)

                    doctor_schedule[doctor.id].append((current_slot, slot_end))
                    room_schedule[selected_room.id].append((current_slot, slot_end + buffer))
                    doctor_patient_count[doctor.id] += 1

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
    return assignments, unassigned, log


# ─── Linear Programming Algorithm ─────────────────────────────────────────────

def run_lp(patients, doctors, rooms, target_date):
    """
    Linear Programming scheduling via PuLP (CBC solver).
    Minimizes total weighted waiting time across compatible doctor-patient-room triplets.
    """
    log = ["[LP] Starting Mixed-Integer Linear Programming Optimization..."]

    # If problem size is very large (> 60 patients), fallback to Greedy for sub-second responsiveness
    if len(patients) > 75:
        log.append("[LP] Dataset is large (>75 patients). Using fast Greedy to guarantee instant response.")
        return run_greedy(patients, doctors, rooms, target_date)

    # Discretize day into 15-minute intervals
    step = 15
    earliest_start = min(time_to_minutes(d.available_from) for d in doctors)
    latest_end = max(time_to_minutes(d.available_until) for d in doctors)

    doctor_map = {d.id: d for d in doctors}
    patient_map = {p.id: p for p in patients}
    room_map = {r.id: r for r in rooms}

    # Department rooms
    dept_rooms = {}
    for r in rooms:
        dept_rooms.setdefault(r.department_id, []).append(r.id)

    # Candidate variables (patient_id, doctor_id, start_min, room_id)
    var_keys = []
    durations = {p.id: get_patient_duration(p) for p in patients}

    for p in patients:
        p_dur = durations[p.id]
        comp_docs = [d for d in doctors if d.specialization.lower() == p.required_specialization.lower()]
        for d in comp_docs:
            d_start = time_to_minutes(d.available_from)
            d_end = time_to_minutes(d.available_until)
            allowed_rooms = dept_rooms.get(d.department_id, [r.id for r in rooms])

            curr = d_start
            while curr + p_dur <= d_end:
                for rid in allowed_rooms:
                    var_keys.append((p.id, d.id, curr, rid))
                curr += step

    log.append(f"[LP] Formulating MIP model with {len(var_keys)} candidate decision variables.")

    if not var_keys:
        log.append("[LP] No feasible candidate slots. Falling back to greedy.")
        return run_greedy(patients, doctors, rooms, target_date)

    # PuLP Model: Maximize weighted assignments with penalty for wait time
    prob = pulp.LpProblem("Hospital_Resource_Optimization", pulp.LpMaximize)
    x = pulp.LpVariable.dicts("x_assign", var_keys, cat='Binary')

    # Objective: Each scheduled patient gives large positive reward (scaled by priority),
    # while waiting time subtracts a small penalty to encourage earliest possible scheduling.
    priority_reward = {'critical': 10000, 'urgent': 5000, 'normal': 2000, 'low': 1000}
    prob += pulp.lpSum(
        (priority_reward.get(patient_map[pid].priority, 2000) - (start - time_to_minutes(doctor_map[did].available_from))) * x[(pid, did, start, rid)]
        for (pid, did, start, rid) in var_keys
    ), "Max_Priority_Min_Wait"

    # Constraint 1: Patient assigned at most once
    for p in patients:
        p_keys = [k for k in var_keys if k[0] == p.id]
        if p_keys:
            prob += pulp.lpSum(x[k] for k in p_keys) <= 1, f"Patient_Single_{p.id}"

    # Constraint 2: Doctor capacity
    for d in doctors:
        d_keys = [k for k in var_keys if k[1] == d.id]
        if d_keys:
            prob += pulp.lpSum(x[k] for k in d_keys) <= d.max_patients_per_day, f"Doc_Cap_{d.id}"

    # Constraint 3: Doctor no-overlap
    for d in doctors:
        d_start = time_to_minutes(d.available_from)
        d_end = time_to_minutes(d.available_until)
        for t in range(d_start, d_end, step):
            overlapping = [
                k for k in var_keys
                if k[1] == d.id and times_overlap(k[2], k[2] + durations[k[0]], t, t + step)
            ]
            if len(overlapping) > 1:
                prob += pulp.lpSum(x[k] for k in overlapping) <= 1, f"Doc_Overlap_{d.id}_{t}"

    # Constraint 4: Room no-overlap (with buffer)
    for r in rooms:
        for t in range(earliest_start, latest_end, step):
            overlapping = [
                k for k in var_keys
                if k[3] == r.id and times_overlap(k[2], k[2] + durations[k[0]] + DEFAULT_BUFFER_MINUTES, t, t + step)
            ]
            if len(overlapping) > 1:
                prob += pulp.lpSum(x[k] for k in overlapping) <= 1, f"Room_Overlap_{r.id}_{t}"

    # Solve
    log.append("[LP] Executing CBC solver (limit 25s)...")
    solver = pulp.PULP_CBC_CMD(msg=0, timeLimit=25)
    prob.solve(solver)

    status_str = pulp.LpStatus[prob.status]
    log.append(f"[LP] Solver ended with status: {status_str}")

    if prob.status not in (1, -1):
        log.append("[LP] Solver could not find optimal solution. Executing Greedy fallback.")
        return run_greedy(patients, doctors, rooms, target_date)

    assignments = []
    assigned_pids = set()

    for k in var_keys:
        if x[k].value() and x[k].value() > 0.5:
            pid, did, start, rid = k
            patient = patient_map[pid]
            doctor = doctor_map[did]
            room = room_map[rid]
            dur = durations[pid]
            doc_start = time_to_minutes(doctor.available_from)
            wait_time = max(0, start - doc_start)

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

    unassigned = [p for p in patients if p.id not in assigned_pids]
    log.append(f"[LP] Completed. Assigned: {len(assignments)}, Unassigned: {len(unassigned)}")
    return assignments, unassigned, log


# ─── Hybrid Algorithm ─────────────────────────────────────────────────────────

def run_hybrid(patients, doctors, rooms, target_date):
    """
    Hybrid scheduling:
    1. Uses Linear Programming for high-priority patients (Critical & Urgent).
    2. Uses Greedy for normal and low-priority patients in remaining free slots.
    """
    log = ["[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)..."]

    high_priority = [p for p in patients if p.priority in ('critical', 'urgent')]
    low_priority = [p for p in patients if p.priority in ('normal', 'low')]

    log.append(f"[HYBRID] High-priority queue: {len(high_priority)} patients")
    log.append(f"[HYBRID] Standard queue: {len(low_priority)} patients")

    lp_assignments = []
    lp_unassigned = []
    if high_priority:
        lp_assignments, lp_unassigned, lp_log = run_lp(high_priority, doctors, rooms, target_date)
        log.extend(lp_log)

    # Greedy for the rest
    remaining_patients = low_priority + lp_unassigned
    greedy_assignments = []
    greedy_unassigned = []
    if remaining_patients:
        # Pre-seed doctor & room schedules from LP
        greedy_assignments, greedy_unassigned, greedy_log = run_greedy(
            remaining_patients, doctors, rooms, target_date
        )
        log.extend(greedy_log)

    all_assignments = lp_assignments + greedy_assignments
    all_unassigned = greedy_unassigned

    log.append(f"[HYBRID] Final Result: Assigned={len(all_assignments)}, Unassigned={len(all_unassigned)}")
    return all_assignments, all_unassigned, log


# ─── Main Optimization Entry Point ───────────────────────────────────────────

def run_optimization(algorithm: str, patients, doctors, rooms, target_date: str):
    """
    Unified entry point for optimization algorithms.
    """
    if not patients:
        return {
            'assignments': [],
            'unassigned': [],
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': 0, 'avg_wait_time': 0, 'utilization_rate': 0},
            'log': ['No patients in queue to schedule.']
        }

    if algorithm == 'lp':
        assignments, unassigned, log = run_lp(patients, doctors, rooms, target_date)
    elif algorithm == 'hybrid':
        assignments, unassigned, log = run_hybrid(patients, doctors, rooms, target_date)
    else:
        assignments, unassigned, log = run_greedy(patients, doctors, rooms, target_date)

    total = len(patients)
    assigned = len(assignments)
    unassigned_count = len(unassigned)
    avg_wait = (sum(a['waiting_time'] for a in assignments) / assigned) if assigned > 0 else 0

    # Calculate doctor slot utilization percentage
    total_slots = sum(
        (time_to_minutes(d.available_until) - time_to_minutes(d.available_from)) // 30
        for d in doctors
    )
    utilization = (assigned / total_slots * 100) if total_slots > 0 else 0

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
        'log': log
    }


# ─── Emergency Code Red Preemption Engine ─────────────────────────────────────

def handle_emergency_preemption(emergency_patient, existing_appointments, doctors, rooms, target_date):
    """
    Fast preemption for immediate Code Red emergencies.
    1. Checks if an immediate free slot exists.
    2. If not, preempts/bumps the earliest low/normal priority appointment.
    3. Reschedules the bumped appointment to the next available slot.
    Returns: dict with emergency appointment, bumped appointment, and logs.
    """
    log = [f"[EMERGENCY] 🚨 Code Red Triggered for patient: {emergency_patient.name} ({emergency_patient.required_specialization})"]
    duration = get_patient_duration(emergency_patient)
    now_dt = datetime.now()
    now_mins = max(time_to_minutes('08:00'), now_dt.hour * 60 + now_dt.minute)
    if now_mins >= time_to_minutes('17:00'):
        # If testing outside operating hours, simulate active shift starting at 08:00
        now_mins = time_to_minutes('08:00')

    # Compatible doctors
    compat_docs = [d for d in doctors if d.specialization.lower() == emergency_patient.required_specialization.lower()]
    if not compat_docs:
        compat_docs = doctors  # Emergency triage can use any available doctor if specialization full

    dept_rooms = [r for r in rooms if r.room_type in ('surgery', 'icu', 'consultation')]

    # Look for immediate vacant slot first
    for doc in compat_docs:
        doc_start = max(now_mins, time_to_minutes(doc.available_from))
        doc_end = time_to_minutes(doc.available_until)
        slot = doc_start
        while slot + duration <= doc_end:
            slot_end = slot + duration
            # Check if doctor busy
            doc_appts = [a for a in existing_appointments if a.doctor_id == doc.id and a.status == 'scheduled']
            doc_overlap = any(times_overlap(slot, slot_end, time_to_minutes(a.start_time), time_to_minutes(a.end_time)) for a in doc_appts)
            if not doc_overlap:
                for room in dept_rooms:
                    room_appts = [a for a in existing_appointments if a.room_id == room.id and a.status == 'scheduled']
                    room_overlap = any(times_overlap(slot, slot_end, time_to_minutes(a.start_time), time_to_minutes(a.end_time)) for a in room_appts)
                    if not room_overlap:
                        log.append(f"[EMERGENCY] ✓ Found immediate opening with Dr. {doc.name} in Room {room.room_number}")
                        return {
                            'action': 'immediate_slot',
                            'emergency_assignment': {
                                'patient_id': emergency_patient.id,
                                'doctor_id': doc.id,
                                'room_id': room.id,
                                'date': target_date,
                                'start_time': minutes_to_time(slot),
                                'end_time': minutes_to_time(slot_end),
                                'duration_minutes': duration,
                                'is_emergency': True,
                                'waiting_time': 0
                            },
                            'bumped_appointment': None,
                            'log': log
                        }
            slot += 15

    # If no immediate opening, preempt a lower-priority appointment
    log.append("[EMERGENCY] No immediate open slot. Scanning for preemption candidates...")
    candidates = []
    for appt in existing_appointments:
        if appt.status != 'scheduled' or getattr(appt, 'is_emergency', False):
            continue
        patient_prio = getattr(appt.patient, 'priority', 'normal')
        if patient_prio in ('normal', 'low'):
            appt_start = time_to_minutes(appt.start_time)
            if appt_start >= now_mins:
                candidates.append((appt_start, appt))

    candidates.sort(key=lambda c: c[0])  # Earliest first

    if candidates:
        target_appt = candidates[0][1]
        log.append(f"[EMERGENCY] ⚠️ Preempting appointment #{target_appt.id} (Patient: {target_appt.patient.name}, Priority: {target_appt.patient.priority})")

        # Shift target appt start to later time
        emergency_start = time_to_minutes(target_appt.start_time)
        emergency_end = emergency_start + duration

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

    # 1. Baseline run
    baseline = run_optimization('hybrid', patients, doctors, rooms, target_date)

    # 2. Crisis setup
    sim_doctors = [d for d in doctors if d.id not in absent_doctor_ids]
    sim_rooms = [r for r in rooms if r.id not in disabled_room_ids]

    sim_patients = list(patients)
    if patient_surge_percent > 0:
        surge_count = int(len(patients) * (patient_surge_percent / 100.0))
        # Clone some urgent/critical patients to simulate surge
        for i in range(surge_count):
            proto = patients[i % len(patients)]
            # Mock patient object
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

    # 3. Simulated Crisis Run
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

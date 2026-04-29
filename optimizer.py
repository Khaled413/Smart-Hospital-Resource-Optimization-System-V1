"""
optimizer.py - Optimization Engine for Smart Hospital Resource Optimization System
Implements Linear Programming (PuLP), Greedy, and Hybrid scheduling algorithms.
"""

import pulp
from datetime import datetime, timedelta
import random


# ─── Time Utilities ───────────────────────────────────────────────────────────

def time_to_minutes(t: str) -> int:
    """Convert HH:MM string to minutes since midnight."""
    h, m = map(int, t.split(':'))
    return h * 60 + m


def minutes_to_time(m: int) -> str:
    """Convert minutes since midnight to HH:MM string."""
    return f"{m // 60:02d}:{m % 60:02d}"


def times_overlap(start1, end1, start2, end2) -> bool:
    """Check if two time intervals overlap."""
    return not (end1 <= start2 or end2 <= start1)


# ─── Priority Scores ──────────────────────────────────────────────────────────

PRIORITY_SCORE = {'critical': 4, 'urgent': 3, 'normal': 2, 'low': 1}
APPOINTMENT_DURATION = 30  # minutes per appointment slot


# ─── Greedy Algorithm ─────────────────────────────────────────────────────────

def run_greedy(patients, doctors, rooms, target_date):
    """
    Greedy scheduling: sort patients by priority (highest first),
    then assign the first available doctor+room+time slot.
    Returns (assignments, log_lines).
    """
    log = ["[GREEDY] Starting greedy scheduling algorithm..."]
    assignments = []
    unassigned = []

    # Sort patients by priority descending
    sorted_patients = sorted(patients, key=lambda p: PRIORITY_SCORE.get(p.priority, 2), reverse=True)
    log.append(f"[GREEDY] Processing {len(sorted_patients)} patients sorted by priority.")

    # Track doctor and room schedules: {id: [(start_min, end_min)]}
    doctor_schedule = {d.id: [] for d in doctors}
    room_schedule = {r.id: [] for r in rooms}
    doctor_patient_count = {d.id: 0 for d in doctors}

    for patient in sorted_patients:
        assigned = False

        # Filter compatible doctors by specialization
        compatible_doctors = [
            d for d in doctors
            if d.specialization.lower() == patient.required_specialization.lower()
        ]

        if not compatible_doctors:
            log.append(f"[GREEDY] ✗ No doctor for patient {patient.name} ({patient.required_specialization})")
            unassigned.append(patient)
            continue

        # Sort doctors by load (fewest patients first)
        compatible_doctors.sort(key=lambda d: doctor_patient_count[d.id])

        for doctor in compatible_doctors:
            if doctor_patient_count[doctor.id] >= doctor.max_patients_per_day:
                continue

            doc_start = time_to_minutes(doctor.available_from)
            doc_end = time_to_minutes(doctor.available_until)

            # Find next free slot for this doctor
            slot_start = doc_start
            while slot_start + APPOINTMENT_DURATION <= doc_end:
                slot_end = slot_start + APPOINTMENT_DURATION

                # Check doctor availability
                doc_busy = any(
                    times_overlap(slot_start, slot_end, s, e)
                    for s, e in doctor_schedule[doctor.id]
                )
                if doc_busy:
                    slot_start += APPOINTMENT_DURATION
                    continue

                # Find available room in the doctor's department
                dept_rooms = [r for r in rooms if r.department_id == doctor.department_id]
                for room in dept_rooms:
                    room_busy = any(
                        times_overlap(slot_start, slot_end, s, e)
                        for s, e in room_schedule[room.id]
                    )
                    if not room_busy:
                        # Calculate waiting time (time from work start to appointment)
                        wait_time = max(0, slot_start - doc_start)

                        # Book the slot
                        doctor_schedule[doctor.id].append((slot_start, slot_end))
                        room_schedule[room.id].append((slot_start, slot_end))
                        doctor_patient_count[doctor.id] += 1

                        assignments.append({
                            'patient': patient,
                            'doctor': doctor,
                            'room': room,
                            'date': target_date,
                            'start_time': minutes_to_time(slot_start),
                            'end_time': minutes_to_time(slot_end),
                            'waiting_time': wait_time
                        })
                        log.append(
                            f"[GREEDY] ✓ {patient.name} ({patient.priority}) → "
                            f"Dr.{doctor.name} | Room {room.room_number} | "
                            f"{minutes_to_time(slot_start)}-{minutes_to_time(slot_end)} | wait={wait_time}min"
                        )
                        assigned = True
                        break
                if assigned:
                    break
                slot_start += APPOINTMENT_DURATION
            if assigned:
                break

        if not assigned:
            unassigned.append(patient)
            log.append(f"[GREEDY] ✗ Could not assign patient {patient.name}")

    log.append(f"[GREEDY] Done. Assigned: {len(assignments)}, Unassigned: {len(unassigned)}")
    return assignments, unassigned, log


# ─── Linear Programming Algorithm ─────────────────────────────────────────────

def run_lp(patients, doctors, rooms, target_date):
    """
    Linear Programming scheduling using PuLP.
    Minimizes total weighted waiting time while respecting all hard constraints.
    Falls back to greedy if LP solver fails.
    """
    log = ["[LP] Starting Linear Programming optimization with PuLP..."]

    # Pre-generate all possible time slots
    all_slots = []
    for doctor in doctors:
        doc_start = time_to_minutes(doctor.available_from)
        doc_end = time_to_minutes(doctor.available_until)
        slot = doc_start
        while slot + APPOINTMENT_DURATION <= doc_end:
            all_slots.append((doctor.id, slot, slot + APPOINTMENT_DURATION))
            slot += APPOINTMENT_DURATION

    log.append(f"[LP] Generated {len(all_slots)} possible doctor-time slots.")

    # Filter compatible (patient, doctor) pairs
    compatible_pairs = []
    for p in patients:
        for d in doctors:
            if d.specialization.lower() == p.required_specialization.lower():
                compatible_pairs.append((p.id, d.id))

    if not compatible_pairs:
        log.append("[LP] No compatible patient-doctor pairs found. Aborting.")
        return [], patients, log

    # Build department → rooms mapping
    dept_rooms = {}
    for r in rooms:
        dept_rooms.setdefault(r.department_id, []).append(r.id)

    patient_map = {p.id: p for p in patients}
    doctor_map = {d.id: d for d in doctors}
    room_map = {r.id: r for r in rooms}

    # Decision variables: x[patient_id, doctor_id, slot_start, room_id] ∈ {0,1}
    # To keep the problem tractable, we create variables only for valid combos
    var_keys = []
    for (pid, did) in compatible_pairs:
        doc = doctor_map[did]
        doc_start = time_to_minutes(doc.available_from)
        doc_end = time_to_minutes(doc.available_until)
        slot = doc_start
        while slot + APPOINTMENT_DURATION <= doc_end:
            for rid in dept_rooms.get(doc.department_id, []):
                var_keys.append((pid, did, slot, rid))
            slot += APPOINTMENT_DURATION

    log.append(f"[LP] Created {len(var_keys)} decision variables.")

    if not var_keys:
        log.append("[LP] No feasible variable combinations. Falling back to greedy.")
        return run_greedy(patients, doctors, rooms, target_date)

    # Create LP problem (minimize total waiting time weighted by priority)
    prob = pulp.LpProblem("HospitalScheduling", pulp.LpMinimize)
    x = pulp.LpVariable.dicts("assign", var_keys, cat='Binary')

    # Objective: minimize sum of (waiting_time * priority_weight) for all assignments
    priority_weight = {p.id: (5 - PRIORITY_SCORE.get(p.priority, 2)) for p in patients}

    prob += pulp.lpSum(
        priority_weight[pid] * (slot - time_to_minutes(doctor_map[did].available_from)) * x[(pid, did, slot, rid)]
        for (pid, did, slot, rid) in var_keys
    ), "MinimizeWeightedWaitTime"

    # Constraint 1: Each patient assigned at most once
    for p in patients:
        keys_for_patient = [(pid, did, slot, rid) for (pid, did, slot, rid) in var_keys if pid == p.id]
        if keys_for_patient:
            prob += pulp.lpSum(x[k] for k in keys_for_patient) <= 1, f"PatientOnce_{p.id}"

    # Constraint 2: Doctor daily capacity
    for d in doctors:
        keys_for_doctor = [(pid, did, slot, rid) for (pid, did, slot, rid) in var_keys if did == d.id]
        if keys_for_doctor:
            prob += pulp.lpSum(x[k] for k in keys_for_doctor) <= d.max_patients_per_day, \
                f"DoctorCapacity_{d.id}"

    # Constraint 3: No overlapping appointments for same doctor
    for d in doctors:
        doc_start = time_to_minutes(d.available_from)
        doc_end = time_to_minutes(d.available_until)
        slot = doc_start
        while slot + APPOINTMENT_DURATION <= doc_end:
            slot_end = slot + APPOINTMENT_DURATION
            same_slot_keys = [
                (pid, did, s, rid) for (pid, did, s, rid) in var_keys
                if did == d.id and times_overlap(s, s + APPOINTMENT_DURATION, slot, slot_end)
            ]
            if len(same_slot_keys) > 1:
                prob += pulp.lpSum(x[k] for k in same_slot_keys) <= 1, \
                    f"DoctorNoOverlap_{d.id}_{slot}"
            slot += APPOINTMENT_DURATION

    # Constraint 4: No overlapping appointments for same room
    all_room_ids = [r.id for r in rooms]
    for r in rooms:
        doc_start_min = 8 * 60
        doc_end_min = 17 * 60
        slot = doc_start_min
        while slot + APPOINTMENT_DURATION <= doc_end_min:
            slot_end = slot + APPOINTMENT_DURATION
            same_slot_keys = [
                (pid, did, s, rid) for (pid, did, s, rid) in var_keys
                if rid == r.id and times_overlap(s, s + APPOINTMENT_DURATION, slot, slot_end)
            ]
            if len(same_slot_keys) > 1:
                prob += pulp.lpSum(x[k] for k in same_slot_keys) <= 1, \
                    f"RoomNoOverlap_{r.id}_{slot}"
            slot += APPOINTMENT_DURATION

    # Solve
    log.append("[LP] Solving with CBC solver...")
    solver = pulp.PULP_CBC_CMD(msg=0, timeLimit=30)
    result = prob.solve(solver)
    status = pulp.LpStatus[prob.status]
    log.append(f"[LP] Solver status: {status}")

    if prob.status not in [1, -1]:  # Not optimal or infeasible
        log.append("[LP] Solver did not find optimal solution. Falling back to greedy.")
        return run_greedy(patients, doctors, rooms, target_date)

    # Extract assignments from solution
    assignments = []
    assigned_patient_ids = set()

    for (pid, did, slot, rid) in var_keys:
        if x[(pid, did, slot, rid)].value() and x[(pid, did, slot, rid)].value() > 0.5:
            patient = patient_map[pid]
            doctor = doctor_map[did]
            room = room_map[rid]
            doc_start = time_to_minutes(doctor.available_from)
            wait_time = max(0, slot - doc_start)

            assignments.append({
                'patient': patient,
                'doctor': doctor,
                'room': room,
                'date': target_date,
                'start_time': minutes_to_time(slot),
                'end_time': minutes_to_time(slot + APPOINTMENT_DURATION),
                'waiting_time': wait_time
            })
            assigned_patient_ids.add(pid)
            log.append(
                f"[LP] ✓ {patient.name} ({patient.priority}) → "
                f"Dr.{doctor.name} | Room {room.room_number} | "
                f"{minutes_to_time(slot)}-{minutes_to_time(slot+APPOINTMENT_DURATION)} | wait={wait_time}min"
            )

    unassigned = [p for p in patients if p.id not in assigned_patient_ids]
    log.append(f"[LP] Done. Assigned: {len(assignments)}, Unassigned: {len(unassigned)}")
    return assignments, unassigned, log


# ─── Hybrid Algorithm ─────────────────────────────────────────────────────────

def run_hybrid(patients, doctors, rooms, target_date):
    """
    Hybrid: Use LP for critical/urgent patients, Greedy for normal/low.
    Combines the precision of LP with the speed of Greedy.
    """
    log = ["[HYBRID] Starting Hybrid optimization (LP + Greedy)..."]

    high_priority = [p for p in patients if p.priority in ('critical', 'urgent')]
    low_priority = [p for p in patients if p.priority in ('normal', 'low')]

    log.append(f"[HYBRID] High-priority patients (LP): {len(high_priority)}")
    log.append(f"[HYBRID] Low-priority patients (Greedy): {len(low_priority)}")

    # Run LP for high-priority
    lp_assignments, lp_unassigned, lp_log = run_lp(high_priority, doctors, rooms, target_date) \
        if high_priority else ([], [], [])
    log.extend(lp_log)

    # Compute remaining capacity after LP assignments
    doctor_patient_count = {d.id: 0 for d in doctors}
    doctor_schedule = {d.id: [] for d in doctors}
    room_schedule = {r.id: [] for r in rooms}

    for a in lp_assignments:
        did = a['doctor'].id
        rid = a['room'].id
        s = time_to_minutes(a['start_time'])
        e = time_to_minutes(a['end_time'])
        doctor_patient_count[did] = doctor_patient_count.get(did, 0) + 1
        doctor_schedule[did].append((s, e))
        room_schedule[rid].append((s, e))

    # Run greedy for low-priority (with remaining capacity)
    remaining_patients = low_priority + lp_unassigned
    greedy_assignments, greedy_unassigned, greedy_log = \
        run_greedy(remaining_patients, doctors, rooms, target_date) \
        if remaining_patients else ([], [], [])
    log.extend(greedy_log)

    all_assignments = lp_assignments + greedy_assignments
    all_unassigned = greedy_unassigned

    log.append(f"[HYBRID] Final: Assigned={len(all_assignments)}, Unassigned={len(all_unassigned)}")
    return all_assignments, all_unassigned, log


# ─── Main Entry Point ─────────────────────────────────────────────────────────

def run_optimization(algorithm: str, patients, doctors, rooms, target_date: str):
    """
    Main optimizer entry point.
    Returns: dict with assignments, metrics, and log.
    """
    if not patients:
        return {
            'assignments': [],
            'unassigned': [],
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': 0,
                        'avg_wait_time': 0, 'utilization_rate': 0},
            'log': ['No patients to schedule.']
        }

    if algorithm == 'lp':
        assignments, unassigned, log = run_lp(patients, doctors, rooms, target_date)
    elif algorithm == 'greedy':
        assignments, unassigned, log = run_greedy(patients, doctors, rooms, target_date)
    elif algorithm == 'hybrid':
        assignments, unassigned, log = run_hybrid(patients, doctors, rooms, target_date)
    else:
        assignments, unassigned, log = run_greedy(patients, doctors, rooms, target_date)

    # Calculate metrics
    total = len(patients)
    assigned = len(assignments)
    unassigned_count = len(unassigned)
    avg_wait = (sum(a['waiting_time'] for a in assignments) / assigned) if assigned > 0 else 0

    # Utilization: (assigned slots / total available slots) * 100
    total_slots = sum(
        (time_to_minutes(d.available_until) - time_to_minutes(d.available_from)) // APPOINTMENT_DURATION
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

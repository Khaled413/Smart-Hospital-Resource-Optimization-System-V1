"""
app.py - Enterprise Application for Smart Hospital Resource Optimization System
Includes Authentication, RBAC, Bed Management, Equipment Tracking, Emergency Code Red Preemption,
Crisis Simulation, Export, and Optimization Services.
"""

from flask import Flask, jsonify, request, render_template, session, redirect, url_for, Response
from datetime import datetime, date
import csv
import io
import os
from functools import wraps

from config import config_by_name
from models import (
    db, Department, Doctor, Patient, Room, Bed, Equipment,
    Appointment, OptimizationRun, User, AuditLog
)
from optimizer import (
    run_optimization, handle_emergency_preemption,
    run_scenario_simulation, predict_no_show_risk,
    time_to_minutes, minutes_to_time
)
from seed_data import seed_database

# ─── App Factory / Configuration ──────────────────────────────────────────────

app = Flask(__name__)
env_name = os.environ.get('FLASK_ENV', 'dev')
app.config.from_object(config_by_name.get(env_name, config_by_name['dev']))

# Ensure instance folder exists
os.makedirs(os.path.join(app.root_path, 'instance'), exist_ok=True)

db.init_app(app)

with app.app_context():
    db.create_all()
    seed_database()


# ─── Auth & Security Helpers ──────────────────────────────────────────────────

def safe_int(val, default=0):
    try:
        return int(val)
    except (ValueError, TypeError):
        return default

def safe_float(val, default=0.0):
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def get_current_user():
    user_id = session.get('user_id')
    if user_id:
        return User.query.get(user_id)
    return None


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            if request.path.startswith('/api/'):
                return jsonify({'error': 'Authentication required. Please sign in.'}), 401
            return redirect(url_for('login_page'))
        return f(*args, **kwargs)
    return decorated_function


def role_required(allowed_roles):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user_role = session.get('role', 'receptionist')
            if user_role not in allowed_roles:
                return jsonify({'error': f'Access denied. Required roles: {", ".join(allowed_roles)}'}), 403
            return f(*args, **kwargs)
        return decorated_function
    return decorator


def log_audit(action, resource_type, resource_id=None, details=''):
    try:
        user_name = session.get('username', 'system')
        user_id = session.get('user_id')
        log = AuditLog(
            user_id=user_id,
            user_name=user_name,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=details
        )
        db.session.add(log)
        db.session.commit()
    except Exception as e:
        print(f"[AUDIT] Failed to log action: {e}")


# ─── Frontend Template Routes ─────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/login')
def login_page():
    return render_template('login.html')

@app.route('/patients')
def patients_page():
    return render_template('patients.html')

@app.route('/doctors')
def doctors_page():
    return render_template('doctors.html')

@app.route('/rooms')
def rooms_page():
    return render_template('rooms.html')

@app.route('/departments')
def departments_page():
    return render_template('departments.html')

@app.route('/appointments')
def appointments_page():
    return render_template('appointments.html')

@app.route('/optimize')
def optimize_page():
    return render_template('optimize.html')

@app.route('/analytics')
def analytics_page():
    return render_template('analytics.html')

@app.route('/history')
def history_page():
    return render_template('history.html')

@app.route('/beds')
def beds_page():
    return render_template('beds.html')

@app.route('/equipment')
def equipment_page():
    return render_template('equipment.html')

@app.route('/simulator')
def simulator_page():
    return render_template('simulator.html')

@app.route('/queue-display')
def queue_display_page():
    return render_template('queue_display.html')


# ─── API: Authentication ──────────────────────────────────────────────────────

@app.route('/api/auth/login', methods=['POST'])
def api_login():
    data = request.get_json() or {}
    username = data.get('username', '').strip()
    password = data.get('password', '')

    user = User.query.filter((User.username == username) | (User.email == username)).first()
    if not user or not user.check_password(password):
        return jsonify({'error': 'Invalid username or password'}), 401

    session['user_id'] = user.id
    session['username'] = user.username
    session['role'] = user.role
    session['full_name'] = user.full_name or user.username

    log_audit('LOGIN', 'user', user.id, f"User {user.username} logged in successfully")
    return jsonify({'message': 'Logged in successfully', 'user': user.to_dict()})


@app.route('/api/auth/logout', methods=['POST'])
def api_logout():
    username = session.get('username')
    user_id = session.get('user_id')
    if user_id:
        log_audit('LOGOUT', 'user', user_id, f"User {username} logged out")
    session.clear()
    return jsonify({'message': 'Logged out successfully'})


@app.route('/api/auth/me', methods=['GET'])
def api_me():
    user = get_current_user()
    if user:
        return jsonify({'authenticated': True, 'user': user.to_dict()})
    return jsonify({'authenticated': False, 'user': None})


# ─── API: Dashboard ───────────────────────────────────────────────────────────

@app.route('/api/dashboard')
def api_dashboard():
    today = date.today().isoformat()
    total_patients = Patient.query.count()
    total_doctors = Doctor.query.count()
    total_rooms = Room.query.count()
    total_depts = Department.query.count()
    total_beds = Bed.query.count()
    occupied_beds = Bed.query.filter_by(status='occupied').count()
    total_equipment = Equipment.query.count()
    avail_equipment = Equipment.query.filter_by(status='available').count()

    appointments_today = Appointment.query.filter_by(date=today).count()
    emergencies_today = Appointment.query.filter_by(date=today, is_emergency=True).count()

    appts = Appointment.query.all()
    avg_wait = (sum(a.waiting_time for a in appts) / len(appts)) if appts else 0

    doctors = Doctor.query.all()
    total_slots = sum(
        (time_to_minutes(d.available_until) - time_to_minutes(d.available_from)) // 30
        for d in doctors
    )
    scheduled_today = Appointment.query.filter_by(date=today, status='scheduled').count()
    utilization = round((scheduled_today / total_slots * 100), 1) if total_slots > 0 else 0

    priority_dist = {}
    for p in Patient.query.all():
        priority_dist[p.priority] = priority_dist.get(p.priority, 0) + 1

    dept_workload = {}
    for d in Department.query.all():
        doc_ids = [doc.id for doc in Doctor.query.filter_by(department_id=d.id).all()]
        count = Appointment.query.filter(Appointment.doctor_id.in_(doc_ids)).count() if doc_ids else 0
        dept_workload[d.name] = count

    doctor_util = []
    for doc in doctors:
        booked = Appointment.query.filter_by(doctor_id=doc.id, date=today).count()
        util_pct = round((booked / doc.max_patients_per_day) * 100, 1) if doc.max_patients_per_day else 0
        doctor_util.append({'name': doc.name, 'utilization': util_pct, 'booked': booked, 'spec': doc.specialization})

    return jsonify({
        'total_patients': total_patients,
        'total_doctors': total_doctors,
        'total_rooms': total_rooms,
        'total_departments': total_depts,
        'total_beds': total_beds,
        'occupied_beds': occupied_beds,
        'bed_occupancy_rate': round((occupied_beds / total_beds * 100), 1) if total_beds > 0 else 0,
        'total_equipment': total_equipment,
        'available_equipment': avail_equipment,
        'appointments_today': appointments_today,
        'emergencies_today': emergencies_today,
        'avg_wait_time': round(avg_wait, 1),
        'utilization_rate': utilization,
        'priority_distribution': priority_dist,
        'department_workload': dept_workload,
        'doctor_utilization': doctor_util
    })


# ─── API: Patients ────────────────────────────────────────────────────────────

@app.route('/api/patients', methods=['GET'])
def api_patients():
    search = request.args.get('search', '').strip().lower()
    priority = request.args.get('priority', '')
    query = Patient.query
    if search:
        query = query.filter(Patient.name.ilike(f'%{search}%'))
    if priority:
        query = query.filter_by(priority=priority)
    return jsonify([p.to_dict() for p in query.order_by(Patient.registered_at.desc()).all()])


@app.route('/api/patients', methods=['POST'])
def api_add_patient():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Patient name is required'}), 400

    patient = Patient(
        name=data.get('name'),
        age=safe_int(data.get('age'), 0),
        gender=data.get('gender', 'Unknown'),
        priority=data.get('priority', 'normal'),
        required_specialization=data.get('required_specialization', ''),
        condition_description=data.get('condition_description', ''),
        preferred_date=data.get('preferred_date', ''),
        triage_level=safe_int(data.get('triage_level'), 3),
        blood_pressure=data.get('blood_pressure', '120/80'),
        heart_rate=safe_int(data.get('heart_rate'), 75),
        spo2=safe_int(data.get('spo2'), 98),
        temperature=safe_float(data.get('temperature'), 37.0),
        registered_at=datetime.utcnow()
    )
    patient.no_show_risk = predict_no_show_risk(patient)
    db.session.add(patient)
    db.session.commit()

    log_audit('CREATE', 'patient', patient.id, f"Registered patient {patient.name} ({patient.priority})")
    return jsonify(patient.to_dict()), 201


@app.route('/api/patients/<int:pid>', methods=['PUT'])
def api_update_patient(pid):
    patient = Patient.query.get_or_404(pid)
    data = request.get_json() or {}
    for field in ['name', 'age', 'gender', 'priority', 'required_specialization',
                  'condition_description', 'preferred_date', 'triage_level',
                  'blood_pressure', 'heart_rate', 'spo2', 'temperature']:
        if field in data:
            setattr(patient, field, data[field])

    # Recalculate ML no-show risk
    patient.no_show_risk = predict_no_show_risk(patient)
    db.session.commit()
    log_audit('UPDATE', 'patient', patient.id, f"Updated patient {patient.name}")
    return jsonify(patient.to_dict())


@app.route('/api/patients/<int:pid>', methods=['DELETE'])
def api_delete_patient(pid):
    patient = Patient.query.get_or_404(pid)
    name = patient.name
    Appointment.query.filter_by(patient_id=pid).delete()
    # Unlink any bed
    bed = Bed.query.filter_by(patient_id=pid).first()
    if bed:
        bed.patient_id = None
        bed.status = 'cleaning'
    db.session.delete(patient)
    db.session.commit()
    log_audit('DELETE', 'patient', pid, f"Deleted patient {name}")
    return jsonify({'message': f'Patient {name} deleted successfully'})


# ─── API: Doctors ─────────────────────────────────────────────────────────────

@app.route('/api/doctors', methods=['GET'])
def api_doctors():
    doctors = Doctor.query.all()
    return jsonify([d.to_dict() for d in doctors])


@app.route('/api/doctors', methods=['POST'])
def api_add_doctor():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Doctor name is required'}), 400
    doctor = Doctor(
        name=data.get('name'),
        specialization=data.get('specialization', ''),
        department_id=int(data.get('department_id', 1)),
        max_patients_per_day=int(data.get('max_patients_per_day', 10)),
        available_from=data.get('available_from', '08:00'),
        available_until=data.get('available_until', '17:00')
    )
    db.session.add(doctor)
    db.session.commit()
    log_audit('CREATE', 'doctor', doctor.id, f"Added doctor {doctor.name} ({doctor.specialization})")
    return jsonify(doctor.to_dict()), 201


@app.route('/api/doctors/<int:did>', methods=['PUT'])
def api_update_doctor(did):
    doctor = Doctor.query.get_or_404(did)
    data = request.get_json() or {}
    for field in ['name', 'specialization', 'department_id', 'max_patients_per_day',
                  'available_from', 'available_until']:
        if field in data:
            setattr(doctor, field, data[field])
    db.session.commit()
    log_audit('UPDATE', 'doctor', doctor.id, f"Updated doctor {doctor.name}")
    return jsonify(doctor.to_dict())


@app.route('/api/doctors/<int:did>', methods=['DELETE'])
def api_delete_doctor(did):
    doctor = Doctor.query.get_or_404(did)
    name = doctor.name
    Appointment.query.filter_by(doctor_id=did).delete()
    db.session.delete(doctor)
    db.session.commit()
    log_audit('DELETE', 'doctor', did, f"Deleted doctor {name}")
    return jsonify({'message': f'Doctor {name} deleted successfully'})


# ─── API: Rooms ───────────────────────────────────────────────────────────────

@app.route('/api/rooms', methods=['GET'])
def api_rooms():
    rooms = Room.query.all()
    return jsonify([r.to_dict() for r in rooms])


@app.route('/api/rooms', methods=['POST'])
def api_add_room():
    data = request.get_json() or {}
    if not data.get('room_number'):
        return jsonify({'error': 'Room number is required'}), 400
    room = Room(
        room_number=data.get('room_number'),
        department_id=int(data.get('department_id', 1)),
        room_type=data.get('room_type', 'consultation'),
        capacity=int(data.get('capacity', 1)),
        status=data.get('status', 'available')
    )
    db.session.add(room)
    db.session.commit()
    log_audit('CREATE', 'room', room.id, f"Added room {room.room_number}")
    return jsonify(room.to_dict()), 201


@app.route('/api/rooms/<int:rid>', methods=['PUT'])
def api_update_room(rid):
    room = Room.query.get_or_404(rid)
    data = request.get_json() or {}
    for field in ['room_number', 'department_id', 'room_type', 'capacity', 'status']:
        if field in data:
            setattr(room, field, data[field])
    db.session.commit()
    log_audit('UPDATE', 'room', room.id, f"Updated room {room.room_number}")
    return jsonify(room.to_dict())


@app.route('/api/rooms/<int:rid>', methods=['DELETE'])
def api_delete_room(rid):
    room = Room.query.get_or_404(rid)
    number = room.room_number
    Appointment.query.filter_by(room_id=rid).delete()
    Bed.query.filter_by(room_id=rid).delete()
    db.session.delete(room)
    db.session.commit()
    log_audit('DELETE', 'room', rid, f"Deleted room {number}")
    return jsonify({'message': f'Room {number} deleted successfully'})


# ─── API: Departments ─────────────────────────────────────────────────────────

@app.route('/api/departments', methods=['GET'])
def api_departments():
    depts = Department.query.all()
    return jsonify([d.to_dict() for d in depts])


@app.route('/api/departments', methods=['POST'])
def api_add_department():
    data = request.get_json() or {}
    dept = Department(
        name=data.get('name'),
        capacity=int(data.get('capacity', 50)),
        description=data.get('description', '')
    )
    db.session.add(dept)
    db.session.commit()
    log_audit('CREATE', 'department', dept.id, f"Added department {dept.name}")
    return jsonify(dept.to_dict()), 201


# ─── API: Inpatient Beds ──────────────────────────────────────────────────────

@app.route('/api/beds', methods=['GET'])
def api_beds():
    beds = Bed.query.all()
    return jsonify([b.to_dict() for b in beds])


@app.route('/api/beds', methods=['POST'])
def api_add_bed():
    data = request.get_json() or {}
    if not data.get('bed_number'):
        return jsonify({'error': 'Bed number is required'}), 400
    bed = Bed(
        bed_number=data.get('bed_number'),
        room_id=int(data.get('room_id', 1)),
        department_id=int(data.get('department_id', 1)),
        status=data.get('status', 'vacant'),
        notes=data.get('notes', '')
    )
    db.session.add(bed)
    db.session.commit()
    log_audit('CREATE', 'bed', bed.id, f"Added bed {bed.bed_number}")
    return jsonify(bed.to_dict()), 201


@app.route('/api/beds/<int:bid>/status', methods=['PATCH'])
def api_update_bed_status(bid):
    bed = Bed.query.get_or_404(bid)
    data = request.get_json() or {}
    new_status = data.get('status')
    if new_status not in ('vacant', 'occupied', 'cleaning', 'reserved'):
        return jsonify({'error': 'Invalid bed status'}), 400
    bed.status = new_status
    if new_status == 'vacant':
        bed.patient_id = None
        bed.admission_date = ''
        bed.expected_discharge = ''
    db.session.commit()
    log_audit('UPDATE', 'bed', bed.id, f"Changed bed {bed.bed_number} status to {new_status}")
    return jsonify(bed.to_dict())


@app.route('/api/beds/<int:bid>/admit', methods=['POST'])
def api_admit_patient_to_bed(bid):
    bed = Bed.query.get_or_404(bid)
    data = request.get_json() or {}
    patient_id = data.get('patient_id')
    patient = Patient.query.get_or_404(patient_id)

    bed.patient_id = patient.id
    bed.status = 'occupied'
    bed.admission_date = data.get('admission_date', date.today().isoformat())
    bed.expected_discharge = data.get('expected_discharge', '')
    bed.notes = data.get('notes', '')
    db.session.commit()

    log_audit('ADMIT', 'bed', bed.id, f"Admitted {patient.name} to bed {bed.bed_number}")
    return jsonify(bed.to_dict())


@app.route('/api/beds/<int:bid>/discharge', methods=['POST'])
def api_discharge_patient_from_bed(bid):
    bed = Bed.query.get_or_404(bid)
    patient_name = bed.patient.name if bed.patient else 'Patient'
    bed.patient_id = None
    bed.status = 'cleaning'  # Moves to cleaning first before vacant
    db.session.commit()

    log_audit('DISCHARGE', 'bed', bed.id, f"Discharged {patient_name} from bed {bed.bed_number} (marked for cleaning)")
    return jsonify(bed.to_dict())


# ─── API: Medical Equipment ───────────────────────────────────────────────────

@app.route('/api/equipment', methods=['GET'])
def api_equipment():
    equip = Equipment.query.all()
    return jsonify([e.to_dict() for e in equip])


@app.route('/api/equipment', methods=['POST'])
def api_add_equipment():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Equipment name is required'}), 400
    eq = Equipment(
        name=data.get('name'),
        equipment_type=data.get('equipment_type', 'ecg'),
        department_id=int(data.get('department_id', 1)),
        room_id=int(data['room_id']) if data.get('room_id') else None,
        status=data.get('status', 'available'),
        notes=data.get('notes', '')
    )
    db.session.add(eq)
    db.session.commit()
    log_audit('CREATE', 'equipment', eq.id, f"Added equipment {eq.name}")
    return jsonify(eq.to_dict()), 201


@app.route('/api/equipment/<int:eid>/status', methods=['PATCH'])
def api_update_equipment_status(eid):
    eq = Equipment.query.get_or_404(eid)
    data = request.get_json() or {}
    new_status = data.get('status')
    if new_status not in ('available', 'in_use', 'maintenance'):
        return jsonify({'error': 'Invalid status'}), 400
    eq.status = new_status
    db.session.commit()
    log_audit('UPDATE', 'equipment', eq.id, f"Set {eq.name} status to {new_status}")
    return jsonify(eq.to_dict())


# ─── API: Appointments ────────────────────────────────────────────────────────

@app.route('/api/appointments', methods=['GET'])
def api_appointments():
    status = request.args.get('status', '')
    date_filter = request.args.get('date', '')
    appts = Appointment.query
    if status:
        appts = appts.filter_by(status=status)
    if date_filter:
        appts = appts.filter_by(date=date_filter)
    return jsonify([a.to_dict() for a in appts.order_by(Appointment.date, Appointment.start_time).all()])


@app.route('/api/appointments/<int:aid>/status', methods=['PATCH'])
def api_update_appointment_status(aid):
    appt = Appointment.query.get_or_404(aid)
    data = request.get_json() or {}
    new_status = data.get('status')
    if new_status not in ('scheduled', 'in_progress', 'completed', 'cancelled', 'no_show'):
        return jsonify({'error': 'Invalid appointment status'}), 400
    appt.status = new_status
    if data.get('clinical_notes'):
        appt.clinical_notes = data['clinical_notes']
    if data.get('prescription'):
        appt.prescription = data['prescription']
    db.session.commit()
    log_audit('UPDATE', 'appointment', appt.id, f"Appointment #{appt.id} set to {new_status}")
    return jsonify(appt.to_dict())


# ─── API: Emergency Code Red Walk-In ──────────────────────────────────────────

@app.route('/api/emergency/walkin', methods=['POST'])
def api_emergency_walkin():
    data = request.get_json() or {}
    name = data.get('name', 'Anonymous Emergency Walk-In')
    spec = data.get('required_specialization', 'Cardiology')
    age = safe_int(data.get('age'), 40)
    gender = data.get('gender', 'Unknown')
    condition = data.get('condition_description', 'Acute Code Red Walk-in')
    today_iso = date.today().isoformat()

    # 1. Register emergency patient immediately
    patient = Patient(
        name=name,
        age=age,
        gender=gender,
        priority='critical',
        required_specialization=spec,
        condition_description=condition,
        preferred_date=today_iso,
        triage_level=1,
        blood_pressure=data.get('blood_pressure', '150/95'),
        heart_rate=safe_int(data.get('heart_rate'), 110),
        spo2=safe_int(data.get('spo2'), 92),
        temperature=safe_float(data.get('temperature'), 37.5),
        no_show_risk=0.01,
        registered_at=datetime.utcnow()
    )
    db.session.add(patient)
    db.session.flush()

    # 2. Get doctors and rooms
    doctors = Doctor.query.all()
    rooms = Room.query.all()
    existing_appts = Appointment.query.filter_by(date=today_iso).all()

    # 3. Run Emergency Preemption Engine
    res = handle_emergency_preemption(patient, existing_appts, doctors, rooms, today_iso)

    if res['action'] == 'failed':
        db.session.commit()
        return jsonify({
            'status': 'critical_warning',
            'message': 'No free doctors or preemptable slots available. Hospital is at full capacity!',
            'patient': patient.to_dict(),
            'log': res['log']
        }), 409

    assign = res['emergency_assignment']
    emergency_appt = Appointment(
        patient_id=assign['patient_id'],
        doctor_id=assign['doctor_id'],
        room_id=assign['room_id'],
        date=assign['date'],
        start_time=assign['start_time'],
        end_time=assign['end_time'],
        duration_minutes=assign['duration_minutes'],
        buffer_minutes=10,
        waiting_time=0,
        status='scheduled',
        is_emergency=True,
        notes=f"EMERGENCY CODE RED: {condition}"
    )
    db.session.add(emergency_appt)

    bumped_msg = None
    if res['action'] == 'preempted':
        bumped_id = res['bumped_appointment_id']
        bumped_appt = Appointment.query.get(bumped_id)
        if bumped_appt:
            # Shift bumped appointment later
            new_start_min = time_to_minutes(assign['end_time']) + 10
            new_end_min = new_start_min + bumped_appt.duration_minutes
            bumped_appt.start_time = minutes_to_time(new_start_min)
            bumped_appt.end_time = minutes_to_time(new_end_min)
            bumped_appt.waiting_time += assign['duration_minutes'] + 10
            bumped_appt.notes = f"Rescheduled due to Emergency Code Red insertion #{emergency_appt.id}"
            bumped_msg = f"Patient {bumped_appt.patient.name}'s appointment bumped to {bumped_appt.start_time}"

    db.session.commit()
    log_audit('EMERGENCY', 'appointment', emergency_appt.id, f"Code Red admitted for {patient.name}")

    return jsonify({
        'status': 'success',
        'action': res['action'],
        'emergency_appointment': emergency_appt.to_dict(),
        'bumped_notice': bumped_msg,
        'log': res['log']
    }), 201


# ─── API: Optimization ────────────────────────────────────────────────────────

@app.route('/api/optimize', methods=['POST'])
def api_optimize():
    data = request.get_json() or {}
    algorithm = data.get('algorithm', 'hybrid')
    target_date = data.get('date', date.today().isoformat())
    clear_existing = data.get('clear_existing', False)

    patients = Patient.query.all()
    doctors = Doctor.query.all()
    rooms = Room.query.all()

    patients_to_schedule = [
        p for p in patients
        if not p.preferred_date or p.preferred_date == target_date
    ]

    if not patients_to_schedule:
        return jsonify({
            'status': 'warning',
            'message': f'No patients with preferred date {target_date}. Using all available patients.',
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': len(patients)}
        })

    if clear_existing:
        Appointment.query.filter_by(date=target_date, is_emergency=False).delete()
        db.session.commit()

    result = run_optimization(algorithm, patients_to_schedule, doctors, rooms, target_date)

    run = OptimizationRun(
        algorithm=algorithm,
        run_date=target_date,
        total_patients=result['metrics']['total'],
        assigned_patients=result['metrics']['assigned'],
        unassigned_patients=result['metrics']['unassigned'],
        avg_wait_time=result['metrics']['avg_wait_time'],
        utilization_rate=result['metrics']['utilization_rate'],
        status='success' if result['metrics']['assigned'] > 0 else 'partial',
        solver_log='\n'.join(result['log'])
    )
    db.session.add(run)
    db.session.flush()

    for a in result['assignments']:
        appt = Appointment(
            patient_id=a['patient'].id,
            doctor_id=a['doctor'].id,
            room_id=a['room'].id,
            date=a['date'],
            start_time=a['start_time'],
            end_time=a['end_time'],
            duration_minutes=a.get('duration_minutes', 30),
            buffer_minutes=a.get('buffer_minutes', 10),
            waiting_time=a['waiting_time'],
            status='scheduled',
            optimization_run_id=run.id
        )
        db.session.add(appt)

    db.session.commit()
    log_audit('OPTIMIZE', 'optimization_run', run.id, f"Executed {algorithm} optimization ({run.assigned_patients}/{run.total_patients} assigned)")

    assignments_out = [
        {
            'patient_name': a['patient'].name,
            'patient_priority': a['patient'].priority,
            'doctor_name': a['doctor'].name,
            'room_number': a['room'].room_number,
            'date': a['date'],
            'start_time': a['start_time'],
            'end_time': a['end_time'],
            'duration_minutes': a.get('duration_minutes', 30),
            'waiting_time': a['waiting_time']
        }
        for a in result['assignments']
    ]

    unassigned_out = [
        {'id': p.id, 'name': p.name, 'priority': p.priority,
         'specialization': p.required_specialization}
        for p in result['unassigned']
    ]

    return jsonify({
        'status': 'success',
        'run_id': run.id,
        'algorithm': algorithm,
        'metrics': result['metrics'],
        'assignments': assignments_out,
        'unassigned': unassigned_out,
        'log': result['log']
    })


# ─── API: Crisis Scenario Simulation ("What-If" Analysis) ─────────────────────

@app.route('/api/simulation/run', methods=['POST'])
def api_run_simulation():
    data = request.get_json() or {}
    target_date = data.get('date', date.today().isoformat())
    absent_doctor_ids = data.get('absent_doctor_ids', [])
    disabled_room_ids = data.get('disabled_room_ids', [])
    patient_surge_percent = int(data.get('patient_surge_percent', 0))

    patients = Patient.query.all()
    doctors = Doctor.query.all()
    rooms = Room.query.all()

    res = run_scenario_simulation(
        patients, doctors, rooms, target_date,
        absent_doctor_ids=absent_doctor_ids,
        disabled_room_ids=disabled_room_ids,
        patient_surge_percent=patient_surge_percent
    )

    log_audit('SIMULATE', 'simulation', None, f"Crisis simulation run (surge={patient_surge_percent}%, absent_docs={len(absent_doctor_ids)})")
    return jsonify(res)


# ─── API: Analytics ───────────────────────────────────────────────────────────

@app.route('/api/analytics/wait-time')
def api_analytics_wait_time():
    result = {}
    for priority in ['critical', 'urgent', 'normal', 'low']:
        appts = db.session.query(Appointment).join(Patient).filter(Patient.priority == priority).all()
        if appts:
            avg = sum(a.waiting_time for a in appts) / len(appts)
            result[priority] = round(avg, 1)
        else:
            result[priority] = 0
    return jsonify(result)


@app.route('/api/analytics/utilization')
def api_analytics_utilization():
    doctors = Doctor.query.all()
    util_data = []
    for doc in doctors:
        total_slots = (time_to_minutes(doc.available_until) - time_to_minutes(doc.available_from)) // 30
        booked = Appointment.query.filter_by(doctor_id=doc.id).count()
        util_pct = round((booked / total_slots * 100), 1) if total_slots > 0 else 0
        util_data.append({
            'doctor': doc.name,
            'specialization': doc.specialization,
            'booked': booked,
            'total_slots': total_slots,
            'utilization': min(util_pct, 100)
        })
    return jsonify(util_data)


@app.route('/api/analytics/patients-status')
def api_analytics_patients_status():
    all_patients = Patient.query.all()
    assigned_ids = {a.patient_id for a in Appointment.query.filter_by(status='scheduled').all()}
    assigned = len([p for p in all_patients if p.id in assigned_ids])
    unassigned = len(all_patients) - assigned
    return jsonify({'assigned': assigned, 'unassigned': unassigned})


@app.route('/api/optimization-runs')
def api_optimization_runs():
    runs = OptimizationRun.query.order_by(OptimizationRun.created_at.desc()).all()
    return jsonify([r.to_dict() for r in runs])


@app.route('/api/audit-logs')
def api_audit_logs():
    logs = AuditLog.query.order_by(AuditLog.created_at.desc()).limit(100).all()
    return jsonify([l.to_dict() for l in logs])


# ─── API: Export to CSV ───────────────────────────────────────────────────────

@app.route('/api/export/appointments/csv')
def export_appointments_csv():
    target_date = request.args.get('date', date.today().isoformat())
    appts = Appointment.query.filter_by(date=target_date).order_by(Appointment.start_time).all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        'ID', 'Date', 'Start Time', 'End Time', 'Duration (min)',
        'Patient Name', 'Priority', 'Triage Level', 'Doctor Name',
        'Specialization', 'Room Number', 'Emergency', 'Status', 'Wait (min)'
    ])

    for a in appts:
        writer.writerow([
            a.id, a.date, a.start_time, a.end_time, a.duration_minutes,
            a.patient.name if a.patient else '',
            a.patient.priority if a.patient else '',
            a.patient.triage_level if a.patient else 3,
            a.doctor.name if a.doctor else '',
            a.doctor.specialization if a.doctor else '',
            a.room.room_number if a.room else '',
            'YES' if a.is_emergency else 'NO',
            a.status, a.waiting_time
        ])

    output.seek(0)
    return Response(
        output.getvalue(),
        mimetype='text/csv',
        headers={"Content-disposition": f"attachment; filename=appointments_{target_date}.csv"}
    )


# ─── Main Execution ───────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("=" * 65)
    print("  Smart Hospital Resource Optimization System (Enterprise Pro)")
    print("  Running at: http://127.0.0.1:5000")
    print("  Default Admin Login: admin / admin123")
    print("=" * 65)
    app.run(debug=True, port=5000)

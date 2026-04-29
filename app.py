"""
app.py - Main Flask Application for Smart Hospital Resource Optimization System
Entry point: python app.py
"""

from flask import Flask, jsonify, request, render_template, abort
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime, date
import os

from models import db, Department, Doctor, Patient, Room, Appointment, OptimizationRun
from optimizer import run_optimization
from seed_data import seed_database

# ─── App Configuration ────────────────────────────────────────────────────────

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///hospital.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SECRET_KEY'] = 'hospital-optimizer-secret-2024'

db.init_app(app)

# ─── Database Setup ───────────────────────────────────────────────────────────

with app.app_context():
    db.create_all()
    seed_database()

# ─── Frontend Routes ──────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')

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

# ─── API: Dashboard ───────────────────────────────────────────────────────────

@app.route('/api/dashboard')
def api_dashboard():
    today = date.today().isoformat()
    total_patients = Patient.query.count()
    total_doctors = Doctor.query.count()
    total_rooms = Room.query.count()
    total_depts = Department.query.count()
    appointments_today = Appointment.query.filter_by(date=today).count()

    # Average waiting time from all appointments
    appts = Appointment.query.all()
    avg_wait = (sum(a.waiting_time for a in appts) / len(appts)) if appts else 0

    # Utilization: scheduled / total possible slots today
    doctors = Doctor.query.all()
    from optimizer import time_to_minutes, APPOINTMENT_DURATION
    total_slots = sum(
        (time_to_minutes(d.available_until) - time_to_minutes(d.available_from)) // APPOINTMENT_DURATION
        for d in doctors
    )
    scheduled_today = Appointment.query.filter_by(date=today, status='scheduled').count()
    utilization = round((scheduled_today / total_slots * 100), 1) if total_slots > 0 else 0

    # Priority distribution
    priority_dist = {}
    for p in Patient.query.all():
        priority_dist[p.priority] = priority_dist.get(p.priority, 0) + 1

    # Department workload (appointments per dept)
    dept_workload = {}
    for d in Department.query.all():
        doc_ids = [doc.id for doc in Doctor.query.filter_by(department_id=d.id).all()]
        count = Appointment.query.filter(Appointment.doctor_id.in_(doc_ids)).count() if doc_ids else 0
        dept_workload[d.name] = count

    # Doctor utilization
    doctor_util = []
    for doc in doctors:
        booked = Appointment.query.filter_by(doctor_id=doc.id, date=today).count()
        util_pct = round((booked / doc.max_patients_per_day) * 100, 1) if doc.max_patients_per_day else 0
        doctor_util.append({'name': doc.name, 'utilization': util_pct, 'booked': booked})

    return jsonify({
        'total_patients': total_patients,
        'total_doctors': total_doctors,
        'total_rooms': total_rooms,
        'total_departments': total_depts,
        'appointments_today': appointments_today,
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
    patients = Patient.query
    if search:
        patients = patients.filter(Patient.name.ilike(f'%{search}%'))
    if priority:
        patients = patients.filter_by(priority=priority)
    return jsonify([p.to_dict() for p in patients.order_by(Patient.registered_at.desc()).all()])

@app.route('/api/patients', methods=['POST'])
def api_add_patient():
    data = request.get_json()
    if not data or not data.get('name'):
        return jsonify({'error': 'Patient name is required'}), 400
    patient = Patient(
        name=data.get('name'),
        age=int(data.get('age', 0)),
        gender=data.get('gender', 'Unknown'),
        priority=data.get('priority', 'normal'),
        required_specialization=data.get('required_specialization', ''),
        condition_description=data.get('condition_description', ''),
        preferred_date=data.get('preferred_date', ''),
        registered_at=datetime.utcnow()
    )
    db.session.add(patient)
    db.session.commit()
    return jsonify(patient.to_dict()), 201

@app.route('/api/patients/<int:pid>', methods=['PUT'])
def api_update_patient(pid):
    patient = Patient.query.get_or_404(pid)
    data = request.get_json()
    for field in ['name', 'age', 'gender', 'priority', 'required_specialization',
                  'condition_description', 'preferred_date']:
        if field in data:
            setattr(patient, field, data[field])
    db.session.commit()
    return jsonify(patient.to_dict())

@app.route('/api/patients/<int:pid>', methods=['DELETE'])
def api_delete_patient(pid):
    patient = Patient.query.get_or_404(pid)
    # Delete related appointments first
    Appointment.query.filter_by(patient_id=pid).delete()
    db.session.delete(patient)
    db.session.commit()
    return jsonify({'message': 'Patient deleted successfully'})

# ─── API: Doctors ─────────────────────────────────────────────────────────────

@app.route('/api/doctors', methods=['GET'])
def api_doctors():
    doctors = Doctor.query.all()
    return jsonify([d.to_dict() for d in doctors])

@app.route('/api/doctors', methods=['POST'])
def api_add_doctor():
    data = request.get_json()
    if not data or not data.get('name'):
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
    return jsonify(doctor.to_dict()), 201

@app.route('/api/doctors/<int:did>', methods=['PUT'])
def api_update_doctor(did):
    doctor = Doctor.query.get_or_404(did)
    data = request.get_json()
    for field in ['name', 'specialization', 'department_id', 'max_patients_per_day',
                  'available_from', 'available_until']:
        if field in data:
            setattr(doctor, field, data[field])
    db.session.commit()
    return jsonify(doctor.to_dict())

@app.route('/api/doctors/<int:did>', methods=['DELETE'])
def api_delete_doctor(did):
    doctor = Doctor.query.get_or_404(did)
    Appointment.query.filter_by(doctor_id=did).delete()
    db.session.delete(doctor)
    db.session.commit()
    return jsonify({'message': 'Doctor deleted successfully'})

# ─── API: Rooms ───────────────────────────────────────────────────────────────

@app.route('/api/rooms', methods=['GET'])
def api_rooms():
    rooms = Room.query.all()
    return jsonify([r.to_dict() for r in rooms])

@app.route('/api/rooms', methods=['POST'])
def api_add_room():
    data = request.get_json()
    if not data or not data.get('room_number'):
        return jsonify({'error': 'Room number is required'}), 400
    room = Room(
        room_number=data.get('room_number'),
        department_id=int(data.get('department_id', 1)),
        room_type=data.get('room_type', 'consultation'),
        capacity=int(data.get('capacity', 1))
    )
    db.session.add(room)
    db.session.commit()
    return jsonify(room.to_dict()), 201

@app.route('/api/rooms/<int:rid>', methods=['PUT'])
def api_update_room(rid):
    room = Room.query.get_or_404(rid)
    data = request.get_json()
    for field in ['room_number', 'department_id', 'room_type', 'capacity']:
        if field in data:
            setattr(room, field, data[field])
    db.session.commit()
    return jsonify(room.to_dict())

@app.route('/api/rooms/<int:rid>', methods=['DELETE'])
def api_delete_room(rid):
    room = Room.query.get_or_404(rid)
    Appointment.query.filter_by(room_id=rid).delete()
    db.session.delete(room)
    db.session.commit()
    return jsonify({'message': 'Room deleted successfully'})

# ─── API: Departments ─────────────────────────────────────────────────────────

@app.route('/api/departments', methods=['GET'])
def api_departments():
    depts = Department.query.all()
    return jsonify([d.to_dict() for d in depts])

@app.route('/api/departments', methods=['POST'])
def api_add_department():
    data = request.get_json()
    dept = Department(
        name=data.get('name'),
        capacity=int(data.get('capacity', 50)),
        description=data.get('description', '')
    )
    db.session.add(dept)
    db.session.commit()
    return jsonify(dept.to_dict()), 201

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
    data = request.get_json()
    new_status = data.get('status')
    if new_status not in ('scheduled', 'completed', 'cancelled'):
        return jsonify({'error': 'Invalid status'}), 400
    appt.status = new_status
    db.session.commit()
    return jsonify(appt.to_dict())

# ─── API: Optimization ────────────────────────────────────────────────────────

@app.route('/api/optimize', methods=['POST'])
def api_optimize():
    data = request.get_json()
    algorithm = data.get('algorithm', 'greedy')
    target_date = data.get('date', date.today().isoformat())
    clear_existing = data.get('clear_existing', False)

    # Load resources
    patients = Patient.query.all()
    doctors = Doctor.query.all()
    rooms = Room.query.all()

    # Filter to patients with preferred_date matching OR no preferred date
    patients_to_schedule = [
        p for p in patients
        if not p.preferred_date or p.preferred_date == target_date
    ]

    if not patients_to_schedule:
        return jsonify({
            'status': 'warning',
            'message': f'No patients with preferred date {target_date}. Using all patients.',
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': len(patients)}
        })

    # Clear existing appointments for target date if requested
    if clear_existing:
        Appointment.query.filter_by(date=target_date).delete()
        db.session.commit()

    # Run optimization
    result = run_optimization(algorithm, patients_to_schedule, doctors, rooms, target_date)

    # Save optimization run record
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

    # Save appointments to DB
    for a in result['assignments']:
        appt = Appointment(
            patient_id=a['patient'].id,
            doctor_id=a['doctor'].id,
            room_id=a['room'].id,
            date=a['date'],
            start_time=a['start_time'],
            end_time=a['end_time'],
            waiting_time=a['waiting_time'],
            status='scheduled',
            optimization_run_id=run.id
        )
        db.session.add(appt)

    db.session.commit()

    # Build response
    assignments_out = [
        {
            'patient_name': a['patient'].name,
            'patient_priority': a['patient'].priority,
            'doctor_name': a['doctor'].name,
            'room_number': a['room'].room_number,
            'date': a['date'],
            'start_time': a['start_time'],
            'end_time': a['end_time'],
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

# ─── API: Analytics ───────────────────────────────────────────────────────────

@app.route('/api/analytics/wait-time')
def api_analytics_wait_time():
    """Average wait time grouped by patient priority."""
    from sqlalchemy import func
    result = {}
    for priority in ['critical', 'urgent', 'normal', 'low']:
        appts = db.session.query(Appointment).join(Patient).filter(
            Patient.priority == priority
        ).all()
        if appts:
            avg = sum(a.waiting_time for a in appts) / len(appts)
            result[priority] = round(avg, 1)
        else:
            result[priority] = 0
    return jsonify(result)

@app.route('/api/analytics/utilization')
def api_analytics_utilization():
    """Doctor utilization percentages."""
    from optimizer import time_to_minutes, APPOINTMENT_DURATION
    doctors = Doctor.query.all()
    util_data = []
    for doc in doctors:
        total_slots = (
            time_to_minutes(doc.available_until) - time_to_minutes(doc.available_from)
        ) // APPOINTMENT_DURATION
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
    """Count of assigned vs unassigned patients."""
    all_patients = Patient.query.all()
    assigned_ids = {a.patient_id for a in Appointment.query.filter_by(status='scheduled').all()}
    assigned = len([p for p in all_patients if p.id in assigned_ids])
    unassigned = len(all_patients) - assigned
    return jsonify({'assigned': assigned, 'unassigned': unassigned})

@app.route('/api/optimization-runs')
def api_optimization_runs():
    runs = OptimizationRun.query.order_by(OptimizationRun.created_at.desc()).all()
    return jsonify([r.to_dict() for r in runs])

# ─── Main ─────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("=" * 60)
    print("  Smart Hospital Resource Optimization System")
    print("  Running at: http://127.0.0.1:5000")
    print("=" * 60)
    app.run(debug=True, port=5000)

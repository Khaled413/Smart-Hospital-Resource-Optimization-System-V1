"""
app.py - Enterprise Application for Smart Hospital Resource Optimization System
Includes Authentication, RBAC, Bed Management, Equipment Tracking, Emergency Code Red Preemption,
Crisis Simulation, Export, and Optimization Services.
"""

from flask import Flask, jsonify, request, render_template, session, redirect, url_for, Response, send_from_directory
from datetime import datetime, date, timedelta
import csv
import io
import os
import secrets
from functools import wraps

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from sqlalchemy.orm import joinedload
from sqlalchemy.exc import IntegrityError

from config import get_config, config_by_name
from models import (
    db, Department, Doctor, Patient, Room, Bed, Equipment,
    Appointment, OptimizationRun, User, AuditLog
)
from optimizer import (
    run_optimization, handle_emergency_preemption,
    run_scenario_simulation, predict_no_show_risk,
    sync_triage_and_priority,
    time_to_minutes, minutes_to_time
)
from seed_data import seed_database

# ─── App Factory / Configuration ──────────────────────────────────────────────

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, 'templates'),
    static_folder=os.path.join(BASE_DIR, 'static'),
    static_url_path='/static'
)
env_name = os.environ.get('FLASK_ENV', 'dev')
app.config.from_object(get_config(env_name))

# ─── Rate Limiter ─────────────────────────────────────────────────────────────

limiter = Limiter(
    key_func=get_remote_address,
    app=app,
    default_limits=[],
    storage_uri="memory://"
)
if app.config.get('TESTING') or app.config.get('RATELIMIT_ENABLED') is False:
    limiter.enabled = False

@app.errorhandler(429)
def ratelimit_handler(e):
    if request.path.startswith('/api/'):
        return jsonify({'error': 'Too many requests. Please wait a moment and try again.'}), 429
    return render_template('login.html', error='Too many requests. Please wait a moment and try again.'), 429

# Handle Vercel / Serverless database persistence & pre-seeding
IS_VERCEL = bool(os.environ.get('VERCEL') or os.environ.get('AWS_LAMBDA_FUNCTION_NAME'))

if IS_VERCEL:
    import tempfile
    import shutil
    tmp_db = os.path.join(tempfile.gettempdir(), 'hospital.db')
    repo_db = os.path.join(app.root_path, 'instance', 'hospital.db')
    if os.path.exists(repo_db) and not os.path.exists(tmp_db):
        try:
            shutil.copy2(repo_db, tmp_db)
        except Exception:
            pass
else:
    try:
        os.makedirs(os.path.join(app.root_path, 'instance'), exist_ok=True)
    except Exception:
        pass

db.init_app(app)

with app.app_context():
    try:
        # Lightweight schema migration for SQLite columns
        try:
            with db.engine.connect() as conn:
                res = conn.execute(db.text("PRAGMA table_info(users)")).fetchall()
                cols = [r[1] for r in res]
                if cols:
                    if 'role_id' not in cols:
                        conn.execute(db.text("ALTER TABLE users ADD COLUMN role_id INTEGER REFERENCES roles(id)"))
                    if 'permissions_version' not in cols:
                        conn.execute(db.text("ALTER TABLE users ADD COLUMN permissions_version INTEGER DEFAULT 1"))
                    conn.commit()
        except Exception:
            pass
        db.create_all()
        seed_database()
    except Exception as e:
        print(f"Database initialization note: {e}")


@app.route('/favicon.ico')
def favicon():
    return send_from_directory(os.path.join(app.root_path, 'static', 'img'), 'logo.png', mimetype='image/png')


# ─── CSRF Protection & Security Headers ──────────────────────────────────────

def get_or_create_csrf_token():
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(32)
    return session['csrf_token']

@app.context_processor
def inject_csrf_token():
    return dict(csrf_token=get_or_create_csrf_token)

@app.before_request
def verify_csrf():
    if request.method in ('POST', 'PUT', 'PATCH', 'DELETE'):
        # Exempt routes
        if request.path in ('/api/auth/login', '/login'):
            return None
        # Allow testing bypass if test header not provided
        if app.config.get('TESTING') and not request.headers.get('X-CSRF-Token'):
            return None

        expected_token = session.get('csrf_token')
        received_token = request.headers.get('X-CSRF-Token')
        if not received_token and request.form:
            received_token = request.form.get('csrf_token')
        if not received_token and request.is_json:
            try:
                body = request.get_json(silent=True) or {}
                received_token = body.get('csrf_token')
            except Exception:
                pass

        if not expected_token or not received_token or not secrets.compare_digest(str(expected_token), str(received_token)):
            return jsonify({'error': 'CSRF token missing or invalid. Please refresh the page.'}), 403

@app.after_request
def add_security_headers(response):
    token = session.get('csrf_token')
    if token:
        response.set_cookie(
            'csrf_token',
            token,
            samesite='Lax',
            secure=app.config.get('SESSION_COOKIE_SECURE', False),
            httponly=False
        )
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com data:; "
        "img-src 'self' data: https:; "
        "connect-src 'self';"
    )
    return response


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

from zoneinfo import ZoneInfo


def get_current_datetime():
    """Return timezone-aware current datetime based on APP_TIMEZONE."""
    tz_str = app.config.get('APP_TIMEZONE', 'Africa/Cairo') if app else 'Africa/Cairo'
    try:
        return datetime.now(ZoneInfo(tz_str))
    except Exception:
        return datetime.now()


def get_current_date():
    """Return current date string YYYY-MM-DD in configured timezone."""
    return get_current_datetime().strftime('%Y-%m-%d')


def get_current_user():
    user_id = session.get('user_id')
    if user_id:
        return db.session.get(User, user_id)
    return None


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session or not get_current_user():
            if request.path.startswith('/api/'):
                return jsonify({'error': 'Authentication required. Please sign in.'}), 401
            next_url = request.full_path if request.query_string else request.path
            return redirect(url_for('login_page', next=next_url))
        return f(*args, **kwargs)
    return decorated_function


def role_required(allowed_roles):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if 'user_id' not in session or not get_current_user():
                return jsonify({'error': 'Authentication required. Please sign in.'}), 401
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
@login_required
def index():
    return render_template('index.html')

@app.route('/login')
def login_page():
    if 'user_id' in session and get_current_user():
        return redirect(url_for('index'))
    return render_template('login.html')

@app.route('/patients')
@login_required
def patients_page():
    return render_template('patients.html')

@app.route('/doctors')
@login_required
def doctors_page():
    return render_template('doctors.html')

@app.route('/rooms')
@login_required
def rooms_page():
    return render_template('rooms.html')

@app.route('/departments')
@login_required
def departments_page():
    return render_template('departments.html')

@app.route('/appointments')
@login_required
def appointments_page():
    return render_template('appointments.html')

@app.route('/optimize')
@login_required
def optimize_page():
    return render_template('optimize.html')

@app.route('/analytics')
@login_required
def analytics_page():
    return render_template('analytics.html')

@app.route('/history')
@login_required
def history_page():
    return render_template('history.html')

@app.route('/beds')
@login_required
def beds_page():
    return render_template('beds.html')

@app.route('/equipment')
@login_required
def equipment_page():
    return render_template('equipment.html')

@app.route('/simulator')
@login_required
def simulator_page():
    return render_template('simulator.html')

@app.route('/queue-display')
@login_required
def queue_display_page():
    return render_template('queue_display.html')

@app.route('/change-password')
@login_required
def change_password_page():
    return render_template('change_password.html')


# ─── API: Authentication ──────────────────────────────────────────────────────

def login_limit_key():
    data = request.get_json(silent=True) or {}
    u = str(data.get('username', '')).strip().lower()
    ip = get_remote_address()
    return f"{ip}:{u}"


@app.route('/api/auth/login', methods=['POST'])
@limiter.limit("5 per minute", key_func=login_limit_key)
def api_login():
    data = request.get_json() or {}
    username = data.get('username', '').strip()
    password = data.get('password', '')

    user = User.query.filter((User.username == username) | (User.email == username)).first()
    if user:
        # Check if account is temporarily locked
        if user.locked_until and user.locked_until > datetime.utcnow():
            mins_left = max(1, int((user.locked_until - datetime.utcnow()).total_seconds() / 60))
            return jsonify({
                'error': f'Account is temporarily locked due to multiple failed login attempts. Try again in {mins_left} minute(s).'
            }), 403

        if not getattr(user, 'is_active', True):
            return jsonify({'error': 'Account has been disabled. Contact system administrator.'}), 403

        if not user.check_password(password):
            user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
            if user.failed_login_attempts >= 5:
                user.locked_until = datetime.utcnow() + timedelta(minutes=15)
                db.session.commit()
                log_audit('LOCKOUT', 'user', user.id, f"User {user.username} locked out after 5 consecutive failed login attempts")
                return jsonify({
                    'error': 'Account has been temporarily locked for 15 minutes due to 5 consecutive failed login attempts.'
                }), 403
            db.session.commit()
            log_audit('LOGIN_FAILED', 'user', user.id, f"Failed login attempt ({user.failed_login_attempts}/5) for {user.username}")
            return jsonify({'error': 'Invalid username or password'}), 401

        # Successful login: reset failed attempts
        user.failed_login_attempts = 0
        user.locked_until = None
        db.session.commit()
    else:
        log_audit('LOGIN_FAILED', 'user', None, f"Failed login attempt for non-existent user: {username}")
        return jsonify({'error': 'Invalid username or password'}), 401

    session['user_id'] = user.id
    session['username'] = user.username
    session['role'] = user.role
    session['full_name'] = user.full_name or user.username

    log_audit('LOGIN', 'user', user.id, f"User {user.username} logged in successfully")
    return jsonify({'message': 'Logged in successfully', 'user': user.to_dict()})


@app.route('/api/auth/logout', methods=['POST'])
@login_required
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


@app.route('/api/auth/change-password', methods=['POST'])
@login_required
def api_change_password():
    user = get_current_user()
    if not user:
        return jsonify({'error': 'Authentication required'}), 401

    data = request.get_json() or {}
    old_password = data.get('current_password') or data.get('old_password', '')
    new_password = data.get('new_password', '')

    if not old_password or not new_password:
        return jsonify({'error': 'Both current_password and new_password are required'}), 400

    if not user.check_password(old_password):
        return jsonify({'error': 'Current password is incorrect'}), 400

    if len(new_password) < 8:
        return jsonify({'error': 'New password must be at least 8 characters long'}), 400

    user.set_password(new_password)
    user.must_change_password = False
    db.session.commit()

    log_audit('PASSWORD_CHANGE', 'user', user.id, f"User {user.username} updated password")
    return jsonify({
        'message': 'Password updated successfully',
        'must_change_password': False
    })


# ─── API: Dashboard ───────────────────────────────────────────────────────────

@app.route('/api/dashboard')
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_dashboard():
    today = get_current_date()
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

    today_appts = Appointment.query.filter_by(date=today).all()
    avg_wait = (sum(a.waiting_time for a in today_appts) / len(today_appts)) if today_appts else 0

    doctors = Doctor.query.all()
    total_avail_minutes = sum(
        (time_to_minutes(d.available_until) - time_to_minutes(d.available_from))
        for d in doctors
    )
    scheduled_today_appts = Appointment.query.filter_by(date=today, status='scheduled').all()
    booked_today_minutes = sum(a.duration_minutes for a in scheduled_today_appts)
    utilization = round((booked_today_minutes / total_avail_minutes * 100), 1) if total_avail_minutes > 0 else 0

    priority_dist = dict(
        db.session.query(Patient.priority, db.func.count(Patient.id))
        .group_by(Patient.priority).all()
    )

    dept_counts = (
        db.session.query(Department.name, db.func.count(Appointment.id))
        .join(Doctor, Doctor.department_id == Department.id)
        .join(Appointment, Appointment.doctor_id == Doctor.id)
        .group_by(Department.name).all()
    )
    dept_workload = {name: count for name, count in dept_counts}

    doc_today_counts = dict(
        db.session.query(Appointment.doctor_id, db.func.count(Appointment.id))
        .filter(Appointment.date == today)
        .group_by(Appointment.doctor_id).all()
    )
    doctor_util = []
    for doc in doctors:
        booked = doc_today_counts.get(doc.id, 0)
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
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_patients():
    search = request.args.get('search', '').strip().lower()
    priority = request.args.get('priority', '')
    query = Patient.query.options(joinedload(Patient.appointments))
    if search:
        query = query.filter(Patient.name.ilike(f'%{search}%'))
    if priority:
        query = query.filter_by(priority=priority)
    return jsonify([p.to_dict() for p in query.order_by(Patient.registered_at.desc()).all()])


@app.route('/api/patients', methods=['POST'])
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_add_patient():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Patient name is required'}), 400

    priority, triage_level = sync_triage_and_priority(
        data.get('priority'), safe_int(data.get('triage_level'), None)
    )

    patient = Patient(
        name=data.get('name'),
        age=safe_int(data.get('age'), 0),
        gender=data.get('gender', 'Unknown'),
        priority=priority,
        required_specialization=data.get('required_specialization', ''),
        condition_description=data.get('condition_description', ''),
        preferred_date=data.get('preferred_date', ''),
        triage_level=triage_level,
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
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_update_patient(pid):
    patient = db.get_or_404(Patient, pid)
    data = request.get_json() or {}
    for field in ['name', 'age', 'gender', 'required_specialization',
                  'condition_description', 'preferred_date',
                  'blood_pressure', 'heart_rate', 'spo2', 'temperature']:
        if field in data:
            setattr(patient, field, data[field])

    if 'priority' in data or 'triage_level' in data:
        prio, triage = sync_triage_and_priority(
            data.get('priority', patient.priority),
            safe_int(data.get('triage_level'), patient.triage_level)
        )
        patient.priority = prio
        patient.triage_level = triage

    # Recalculate ML no-show risk
    patient.no_show_risk = predict_no_show_risk(patient)
    db.session.commit()
    log_audit('UPDATE', 'patient', patient.id, f"Updated patient {patient.name}")
    return jsonify(patient.to_dict())


@app.route('/api/patients/<int:pid>', methods=['DELETE'])
@login_required
@role_required(['admin'])
def api_delete_patient(pid):
    patient = db.get_or_404(Patient, pid)
    active_count = Appointment.query.filter(
        Appointment.patient_id == pid,
        Appointment.status.in_(['scheduled', 'in_progress'])
    ).count()
    if active_count > 0:
        return jsonify({
            'error': f"Cannot delete patient '{patient.name}' who has {active_count} active appointment(s). Please cancel or complete them first."
        }), 400

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
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_doctors():
    today_iso = get_current_date()
    appt_counts = dict(
        db.session.query(Appointment.doctor_id, db.func.count(Appointment.id))
        .filter(Appointment.date == today_iso, Appointment.status != 'cancelled')
        .group_by(Appointment.doctor_id).all()
    )
    doctors = Doctor.query.options(joinedload(Doctor.dept)).all()
    return jsonify([d.to_dict(appointments_today=appt_counts.get(d.id, 0)) for d in doctors])


@app.route('/api/doctors', methods=['POST'])
@login_required
@role_required(['admin'])
def api_add_doctor():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Doctor name is required'}), 400
    doctor = Doctor(
        name=data.get('name'),
        specialization=data.get('specialization', ''),
        department_id=safe_int(data.get('department_id'), 1),
        max_patients_per_day=safe_int(data.get('max_patients_per_day'), 10),
        available_from=data.get('available_from', '08:00'),
        available_until=data.get('available_until', '17:00')
    )
    db.session.add(doctor)
    db.session.commit()
    log_audit('CREATE', 'doctor', doctor.id, f"Added doctor {doctor.name} ({doctor.specialization})")
    return jsonify(doctor.to_dict()), 201


@app.route('/api/doctors/<int:did>', methods=['PUT'])
@login_required
@role_required(['admin'])
def api_update_doctor(did):
    doctor = db.get_or_404(Doctor, did)
    data = request.get_json() or {}
    for field in ['name', 'specialization', 'available_from', 'available_until']:
        if field in data:
            setattr(doctor, field, data[field])
    if 'department_id' in data:
        doctor.department_id = safe_int(data['department_id'], doctor.department_id)
    if 'max_patients_per_day' in data:
        doctor.max_patients_per_day = safe_int(data['max_patients_per_day'], doctor.max_patients_per_day)
    db.session.commit()
    log_audit('UPDATE', 'doctor', doctor.id, f"Updated doctor {doctor.name}")
    return jsonify(doctor.to_dict())


@app.route('/api/doctors/<int:did>', methods=['DELETE'])
@login_required
@role_required(['admin'])
def api_delete_doctor(did):
    doctor = db.get_or_404(Doctor, did)
    active_count = Appointment.query.filter(
        Appointment.doctor_id == did,
        Appointment.status.in_(['scheduled', 'in_progress'])
    ).count()
    if active_count > 0:
        return jsonify({
            'error': f"Cannot delete doctor '{doctor.name}' who has {active_count} active appointment(s). Please reassign them first."
        }), 400

    name = doctor.name
    Appointment.query.filter_by(doctor_id=did).delete()
    db.session.delete(doctor)
    db.session.commit()
    log_audit('DELETE', 'doctor', did, f"Deleted doctor {name}")
    return jsonify({'message': f'Doctor {name} deleted successfully'})


# ─── API: Rooms ───────────────────────────────────────────────────────────────

@app.route('/api/rooms', methods=['GET'])
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_rooms():
    rooms = Room.query.options(joinedload(Room.dept), joinedload(Room.beds)).all()
    return jsonify([r.to_dict() for r in rooms])


@app.route('/api/rooms', methods=['POST'])
@login_required
@role_required(['admin'])
def api_add_room():
    data = request.get_json() or {}
    room_number = data.get('room_number')
    if not room_number:
        return jsonify({'error': 'Room number is required'}), 400
    if Room.query.filter_by(room_number=room_number).first():
        return jsonify({'error': f"Room '{room_number}' already exists"}), 409

    room = Room(
        room_number=room_number,
        department_id=safe_int(data.get('department_id'), 1),
        room_type=data.get('room_type', 'consultation'),
        capacity=safe_int(data.get('capacity'), 1),
        status=data.get('status', 'available')
    )
    db.session.add(room)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({'error': f"Room '{room_number}' already exists"}), 409

    log_audit('CREATE', 'room', room.id, f"Added room {room.room_number}")
    return jsonify(room.to_dict()), 201


@app.route('/api/rooms/<int:rid>', methods=['PUT'])
@login_required
@role_required(['admin'])
def api_update_room(rid):
    room = db.get_or_404(Room, rid)
    data = request.get_json() or {}
    for field in ['room_type', 'status']:
        if field in data:
            setattr(room, field, data[field])
    if 'room_number' in data and data['room_number'] != room.room_number:
        existing = Room.query.filter_by(room_number=data['room_number']).first()
        if existing:
            return jsonify({'error': f"Room number '{data['room_number']}' already in use"}), 409
        room.room_number = data['room_number']
    if 'department_id' in data:
        room.department_id = safe_int(data['department_id'], room.department_id)
    if 'capacity' in data:
        room.capacity = safe_int(data['capacity'], room.capacity)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({'error': f"Conflict updating room {room.id}"}), 409

    log_audit('UPDATE', 'room', room.id, f"Updated room {room.room_number}")
    return jsonify(room.to_dict())


@app.route('/api/rooms/<int:rid>', methods=['DELETE'])
@login_required
@role_required(['admin'])
def api_delete_room(rid):
    room = db.get_or_404(Room, rid)
    active_appts = Appointment.query.filter(
        Appointment.room_id == rid,
        Appointment.status.in_(['scheduled', 'in_progress'])
    ).count()
    if active_appts > 0:
        return jsonify({
            'error': f"Cannot delete room '{room.room_number}' with {active_appts} active appointment(s). Please reassign them first."
        }), 400
    occupied_beds = Bed.query.filter_by(room_id=rid, status='occupied').count()
    if occupied_beds > 0:
        return jsonify({
            'error': f"Cannot delete room '{room.room_number}' with {occupied_beds} occupied bed(s). Please discharge or transfer patients first."
        }), 400

    number = room.room_number
    Appointment.query.filter_by(room_id=rid).delete()
    Bed.query.filter_by(room_id=rid).delete()
    db.session.delete(room)
    db.session.commit()
    log_audit('DELETE', 'room', rid, f"Deleted room {number}")
    return jsonify({'message': f'Room {number} deleted successfully'})


# ─── API: Departments ─────────────────────────────────────────────────────────

@app.route('/api/departments', methods=['GET'])
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_departments():
    depts = Department.query.all()
    return jsonify([d.to_dict() for d in depts])


@app.route('/api/departments', methods=['POST'])
@login_required
@role_required(['admin'])
def api_add_department():
    data = request.get_json() or {}
    name = data.get('name')
    if not name:
        return jsonify({'error': 'Department name is required'}), 400
    if Department.query.filter_by(name=name).first():
        return jsonify({'error': f"Department '{name}' already exists"}), 409

    dept = Department(
        name=name,
        capacity=safe_int(data.get('capacity'), 50),
        description=data.get('description', '')
    )
    db.session.add(dept)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({'error': f"Department '{name}' already exists"}), 409

    log_audit('CREATE', 'department', dept.id, f"Added department {dept.name}")
    return jsonify(dept.to_dict()), 201


# ─── API: Inpatient Beds ──────────────────────────────────────────────────────

@app.route('/api/beds', methods=['GET'])
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_beds():
    beds = Bed.query.options(
        joinedload(Bed.room),
        joinedload(Bed.dept),
        joinedload(Bed.patient)
    ).all()
    return jsonify([b.to_dict() for b in beds])


@app.route('/api/beds', methods=['POST'])
@login_required
@role_required(['admin'])
def api_add_bed():
    data = request.get_json() or {}
    bed_number = data.get('bed_number')
    if not bed_number:
        return jsonify({'error': 'Bed number is required'}), 400
    if Bed.query.filter_by(bed_number=bed_number).first():
        return jsonify({'error': f"Bed '{bed_number}' already exists"}), 409

    bed = Bed(
        bed_number=bed_number,
        room_id=safe_int(data.get('room_id'), 1),
        department_id=safe_int(data.get('department_id'), 1),
        status=data.get('status', 'vacant'),
        notes=data.get('notes', '')
    )
    db.session.add(bed)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        return jsonify({'error': f"Bed '{bed_number}' already exists"}), 409

    log_audit('CREATE', 'bed', bed.id, f"Added bed {bed.bed_number}")
    return jsonify(bed.to_dict()), 201


@app.route('/api/beds/<int:bid>/status', methods=['PATCH'])
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_update_bed_status(bid):
    bed = db.get_or_404(Bed, bid)
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
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_admit_patient_to_bed(bid):
    bed = db.get_or_404(Bed, bid)
    if bed.status == 'occupied':
        return jsonify({'error': f"Bed {bed.bed_number} is already occupied"}), 400
    if bed.status == 'maintenance':
        return jsonify({'error': f"Bed {bed.bed_number} is under maintenance and cannot accept patients"}), 400

    data = request.get_json() or {}
    patient_id = data.get('patient_id')
    if not patient_id:
        return jsonify({'error': 'patient_id is required for admission'}), 400

    patient = db.session.get(Patient, patient_id)
    if not patient:
        return jsonify({'error': f'Patient #{patient_id} not found'}), 404

    # Validate patient is not already admitted in another bed
    existing_bed = Bed.query.filter_by(patient_id=patient.id).first()
    if existing_bed and existing_bed.id != bed.id:
        return jsonify({
            'error': f"Patient '{patient.name}' is already admitted to bed {existing_bed.bed_number}"
        }), 400

    bed.patient_id = patient.id
    bed.status = 'occupied'
    bed.admission_date = data.get('admission_date') or get_current_date()
    bed.expected_discharge = data.get('expected_discharge', '')
    bed.notes = data.get('notes', '')
    db.session.commit()

    log_audit('ADMIT', 'bed', bed.id, f"Admitted {patient.name} to bed {bed.bed_number}")
    return jsonify(bed.to_dict())


@app.route('/api/beds/<int:bid>/discharge', methods=['POST'])
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_discharge_patient_from_bed(bid):
    bed = db.get_or_404(Bed, bid)
    if bed.status != 'occupied' and not bed.patient_id:
        return jsonify({'error': f"Bed {bed.bed_number} is not currently occupied"}), 400
    patient_name = bed.patient.name if bed.patient else 'Patient'
    bed.patient_id = None
    bed.status = 'cleaning'  # Moves to cleaning first before vacant
    db.session.commit()

    log_audit('DISCHARGE', 'bed', bed.id, f"Discharged {patient_name} from bed {bed.bed_number} (marked for cleaning)")
    return jsonify(bed.to_dict())


# ─── API: Medical Equipment ───────────────────────────────────────────────────

@app.route('/api/equipment', methods=['GET'])
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_equipment():
    equip = Equipment.query.options(joinedload(Equipment.dept), joinedload(Equipment.room)).all()
    return jsonify([e.to_dict() for e in equip])


@app.route('/api/equipment', methods=['POST'])
@login_required
@role_required(['admin'])
def api_add_equipment():
    data = request.get_json() or {}
    if not data.get('name'):
        return jsonify({'error': 'Equipment name is required'}), 400
    eq = Equipment(
        name=data.get('name'),
        equipment_type=data.get('equipment_type', 'ecg'),
        department_id=safe_int(data.get('department_id'), 1),
        room_id=safe_int(data.get('room_id'), None) if data.get('room_id') else None,
        status=data.get('status', 'available'),
        notes=data.get('notes', '')
    )
    db.session.add(eq)
    db.session.commit()
    log_audit('CREATE', 'equipment', eq.id, f"Added equipment {eq.name}")
    return jsonify(eq.to_dict()), 201


@app.route('/api/equipment/<int:eid>/status', methods=['PATCH'])
@login_required
@role_required(['admin', 'manager', 'receptionist'])
def api_update_equipment_status(eid):
    eq = db.get_or_404(Equipment, eid)
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
@login_required
@role_required(['admin', 'manager', 'doctor', 'receptionist'])
def api_appointments():
    status = request.args.get('status', '')
    date_filter = request.args.get('date', '')
    appts = Appointment.query.options(
        joinedload(Appointment.patient),
        joinedload(Appointment.doctor),
        joinedload(Appointment.room),
        joinedload(Appointment.equipment)
    )
    if status:
        appts = appts.filter_by(status=status)
    if date_filter:
        appts = appts.filter_by(date=date_filter)
    return jsonify([a.to_dict() for a in appts.order_by(Appointment.date, Appointment.start_time).all()])


VALID_APPOINTMENT_TRANSITIONS = {
    'scheduled': {'in_progress', 'cancelled', 'no_show'},
    'in_progress': {'completed', 'cancelled'},
    'completed': set(),
    'cancelled': set(),
    'no_show': set(),
}


@app.route('/api/appointments/<int:aid>/status', methods=['PATCH'])
@login_required
@role_required(['admin', 'manager', 'doctor'])
def api_update_appointment_status(aid):
    appt = db.get_or_404(Appointment, aid)
    current_user = get_current_user()
    if session.get('role') == 'doctor':
        if current_user and current_user.doctor_id and appt.doctor_id != current_user.doctor_id:
            return jsonify({'error': 'Doctors can only update their own appointments'}), 403

    data = request.get_json() or {}
    new_status = data.get('status')
    if new_status not in ('scheduled', 'in_progress', 'completed', 'cancelled', 'no_show'):
        return jsonify({'error': 'Invalid appointment status'}), 400

    # Validate state machine transitions
    if new_status != appt.status:
        allowed = VALID_APPOINTMENT_TRANSITIONS.get(appt.status, set())
        if new_status not in allowed:
            return jsonify({
                'error': f"Invalid status transition from '{appt.status}' to '{new_status}'. Allowed transitions: {sorted(list(allowed)) if allowed else 'None (terminal state)'}"
            }), 400

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
@login_required
@role_required(['admin', 'manager', 'receptionist'])
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
    app_tz = app.config.get('APP_TIMEZONE', 'Africa/Cairo')
    res = handle_emergency_preemption(patient, existing_appts, doctors, rooms, today_iso, app_timezone=app_tz)

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
        bumped_plan = res.get('bumped_plan') or {}
        bumped_appt = db.session.get(Appointment, bumped_id)
        if bumped_appt:
            if bumped_plan.get('rescheduled_slot'):
                slot = bumped_plan['rescheduled_slot']
                bumped_appt.start_time = slot['start_time']
                bumped_appt.end_time = slot['end_time']
                bumped_appt.room_id = slot['room_id']
                bumped_appt.waiting_time = slot['waiting_time']
                bumped_appt.notes = f"Rescheduled to {slot['start_time']} due to Emergency Code Red insertion #{emergency_appt.id}"
                bumped_msg = f"Patient {bumped_appt.patient.name}'s appointment relocated to {slot['start_time']}"
            else:
                bumped_appt.status = 'needs_reschedule'
                bumped_appt.notes = f"Preempted by Emergency Code Red #{emergency_appt.id} (Doctor shift full, needs reschedule)"
                bumped_msg = f"Patient {bumped_appt.patient.name} bumped (shift full, marked for rescheduling)"

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
@login_required
@role_required(['admin', 'manager'])
def api_optimize():
    data = request.get_json() or {}
    algorithm = data.get('algorithm', 'hybrid')
    target_date = data.get('date', date.today().isoformat())
    clear_existing = data.get('clear_existing', False)

    patients = Patient.query.all()
    doctors = Doctor.query.all()
    rooms = Room.query.all()

    existing_appts = Appointment.query.filter_by(date=target_date).all()
    active_appts = [a for a in existing_appts if a.status in ('scheduled', 'in_progress', 'completed')]
    if clear_existing:
        already_scheduled_patient_ids = {a.patient_id for a in active_appts if a.is_emergency}
    else:
        already_scheduled_patient_ids = {a.patient_id for a in active_appts}

    unscheduled_patients = [
        p for p in patients
        if p.id not in already_scheduled_patient_ids
    ]

    if not unscheduled_patients:
        return jsonify({
            'status': 'warning',
            'message': f'All eligible patients are already scheduled for {target_date}.',
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': 0}
        })

    # Filter patients with target_date or unassigned preferred_date
    patients_to_schedule = [
        p for p in unscheduled_patients
        if not p.preferred_date or p.preferred_date == target_date
    ]

    if not patients_to_schedule:
        return jsonify({
            'status': 'warning',
            'message': f'No eligible unscheduled patients available for {target_date}.',
            'metrics': {'total': 0, 'assigned': 0, 'unassigned': 0}
        })

    try:
        with db.session.begin_nested():
            if clear_existing:
                Appointment.query.filter_by(date=target_date, is_emergency=False).delete()
                db.session.flush()

            remaining_existing = Appointment.query.filter_by(date=target_date).all()
            result = run_optimization(algorithm, patients_to_schedule, doctors, rooms, target_date, existing_appointments=remaining_existing)

            run = OptimizationRun(
                algorithm=algorithm,
                algorithm_used=result.get('algorithm_used', algorithm),
                fallback_reason=result.get('fallback_reason'),
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
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': f'Optimization transaction failed: {str(e)}'}), 500

    log_audit('OPTIMIZE', 'optimization_run', run.id, f"Executed {run.algorithm_used} optimization ({run.assigned_patients}/{run.total_patients} assigned)")

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

    run_status = 'success' if result['metrics']['assigned'] > 0 else 'warning'
    return jsonify({
        'status': run_status,
        'run_id': run.id,
        'algorithm': algorithm,
        'algorithm_used': run.algorithm_used,
        'fallback_reason': run.fallback_reason,
        'metrics': result['metrics'],
        'assignments': assignments_out,
        'unassigned': unassigned_out,
        'log': result['log']
    })


# ─── API: Crisis Scenario Simulation ("What-If" Analysis) ─────────────────────

@app.route('/api/simulation/run', methods=['POST'])
@login_required
@role_required(['admin', 'manager'])
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
@login_required
@role_required(['admin', 'manager'])
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
@login_required
@role_required(['admin', 'manager'])
def api_analytics_utilization():
    target_date = request.args.get('date', date.today().isoformat())
    doctors = Doctor.query.all()
    util_data = []
    for doc in doctors:
        avail_mins = time_to_minutes(doc.available_until) - time_to_minutes(doc.available_from)
        total_slots = avail_mins // 30
        doc_appts = Appointment.query.filter_by(doctor_id=doc.id, date=target_date, status='scheduled').all()
        booked_mins = sum(a.duration_minutes for a in doc_appts)
        util_pct = round((booked_mins / avail_mins * 100), 1) if avail_mins > 0 else 0
        util_data.append({
            'doctor': doc.name,
            'specialization': doc.specialization,
            'booked': len(doc_appts),
            'booked_minutes': booked_mins,
            'total_slots': total_slots,
            'utilization': min(util_pct, 100)
        })
    return jsonify(util_data)


@app.route('/api/analytics/patients-status')
@login_required
@role_required(['admin', 'manager'])
def api_analytics_patients_status():
    all_patients = Patient.query.all()
    assigned_ids = {a.patient_id for a in Appointment.query.filter_by(status='scheduled').all()}
    assigned = len([p for p in all_patients if p.id in assigned_ids])
    unassigned = len(all_patients) - assigned
    return jsonify({'assigned': assigned, 'unassigned': unassigned})


@app.route('/api/optimization-runs')
@login_required
@role_required(['admin', 'manager'])
def api_optimization_runs():
    runs = OptimizationRun.query.order_by(OptimizationRun.created_at.desc()).all()
    return jsonify([r.to_dict() for r in runs])


@app.route('/api/audit-logs')
@login_required
@role_required(['admin'])
def api_audit_logs():
    logs = AuditLog.query.order_by(AuditLog.created_at.desc()).limit(100).all()
    return jsonify([l.to_dict() for l in logs])


# ─── API: Export to CSV ───────────────────────────────────────────────────────

def sanitize_csv_cell(val):
    if val is None:
        return ""
    s = str(val)
    if s and s[0] in ('=', '+', '-', '@', '\t', '\r'):
        return "'" + s
    return s


@app.route('/api/export/appointments/csv')
@login_required
@role_required(['admin', 'manager'])
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
        row = [
            a.id, a.date, a.start_time, a.end_time, a.duration_minutes,
            a.patient.name if a.patient else '',
            a.patient.priority if a.patient else '',
            a.patient.triage_level if a.patient else 3,
            a.doctor.name if a.doctor else '',
            a.doctor.specialization if a.doctor else '',
            a.room.room_number if a.room else '',
            'YES' if a.is_emergency else 'NO',
            a.status, a.waiting_time
        ]
        writer.writerow([sanitize_csv_cell(c) for c in row])

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
    print("=" * 65)
    app.run(debug=True, port=5000)

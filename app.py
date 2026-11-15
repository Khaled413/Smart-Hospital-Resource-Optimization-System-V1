"""
app.py - Enterprise Application for Smart Hospital Resource Optimization System
Includes Authentication, RBAC, Bed Management, Equipment Tracking, Emergency Code Red Preemption,
Crisis Simulation, Export, and Optimization Services.
"""

from flask import Flask, jsonify, request, render_template, session, redirect, url_for, Response, send_from_directory, g
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
    Appointment, OptimizationRun, User, AuditLog,
    Permission, Role, UserPermissionOverride, role_permissions, mask_patient_name
)
from permissions import (
    PERMISSION_CATALOG, PERMISSION_MAP, PERMISSION_GROUPS,
    DEFAULT_ROLE_PERMISSIONS, get_permissions_by_group, get_all_permissions
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
    """Return the currently authenticated User instance or None."""
    if hasattr(g, 'current_user'):
        return g.current_user
    user_id = session.get('user_id')
    if not user_id:
        g.current_user = None
        return None
    user = db.session.get(User, user_id)
    if not user or not user.is_active:
        g.current_user = None
        return None
    g.current_user = user
    return user


def get_user_effective_permissions(user):
    """
    Return effective permission set for user, cached in flask.g.
    Invalidates immediately on permissions_version or role version changes.
    """
    if not user or not user.is_active:
        return set()

    cache_key = f"_eff_perms_{user.id}"
    version_key = f"_eff_version_{user.id}"
    role_ver = user.assigned_role.version if user.assigned_role else 1
    current_ver = (user.permissions_version, role_ver)

    if hasattr(g, cache_key) and getattr(g, version_key, None) == current_ver:
        return getattr(g, cache_key)

    perms = user.get_effective_permissions()
    setattr(g, cache_key, perms)
    setattr(g, version_key, current_ver)
    return perms


def user_has_permission(user, permission_key: str) -> bool:
    """Check if user holds the given permission key."""
    if not user or not user.is_active:
        return False
    perms = get_user_effective_permissions(user)
    return permission_key in perms


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user = get_current_user()
        if not user:
            if request.path.startswith('/api/'):
                return jsonify({'error': 'Unauthorized', 'message': 'Authentication required. Please sign in.'}), 401
            next_url = request.full_path if request.query_string else request.path
            return redirect(url_for('login_page', next=next_url))
        if not user.is_active:
            session.clear()
            if request.path.startswith('/api/'):
                return jsonify({'error': 'AccountDisabled', 'message': 'Account is deactivated.'}), 403
            return redirect(url_for('login_page'))
        return f(*args, **kwargs)
    decorated_function._permission_protected = True
    return decorated_function


def require_permission(perm_key: str):
    """
    Enforces that current authenticated user has the specified permission key.
    Returns 401 if unauthenticated, 403 if unauthorized or disabled.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = get_current_user()
            if not user:
                if request.path.startswith('/api/'):
                    return jsonify({'error': 'Unauthorized', 'message': 'Authentication required. Please sign in.'}), 401
                next_url = request.full_path if request.query_string else request.path
                return redirect(url_for('login_page', next=next_url))

            if not user.is_active:
                session.clear()
                if request.path.startswith('/api/'):
                    return jsonify({'error': 'AccountDisabled', 'message': 'Account is deactivated.'}), 403
                return redirect(url_for('login_page'))

            if not user_has_permission(user, perm_key):
                if request.path.startswith('/api/'):
                    return jsonify({
                        'error': 'Forbidden',
                        'required_permission': perm_key,
                        'message': f'Access denied. Missing required permission: {perm_key}'
                    }), 403
                return render_template('403.html', required_permission=perm_key), 403

            return f(*args, **kwargs)
        decorated_function._permission_protected = True
        decorated_function._required_permission = perm_key
        return decorated_function
    return decorator


def require_any(perm_keys: list):
    """
    Enforces that current authenticated user has AT LEAST ONE of the specified permission keys.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = get_current_user()
            if not user:
                if request.path.startswith('/api/'):
                    return jsonify({'error': 'Unauthorized', 'message': 'Authentication required. Please sign in.'}), 401
                next_url = request.full_path if request.query_string else request.path
                return redirect(url_for('login_page', next=next_url))

            if not user.is_active:
                session.clear()
                if request.path.startswith('/api/'):
                    return jsonify({'error': 'AccountDisabled', 'message': 'Account is deactivated.'}), 403
                return redirect(url_for('login_page'))

            user_perms = get_user_effective_permissions(user)
            if not any(k in user_perms for k in perm_keys):
                if request.path.startswith('/api/'):
                    return jsonify({
                        'error': 'Forbidden',
                        'required_any_permissions': perm_keys,
                        'message': f'Access denied. One of permissions required: {", ".join(perm_keys)}'
                    }), 403
                return render_template('403.html', required_permission=' / '.join(perm_keys)), 403

            return f(*args, **kwargs)
        decorated_function._permission_protected = True
        decorated_function._required_any_permissions = perm_keys
        return decorated_function
    return decorator


def role_required(allowed_roles):
    """Legacy role check fallback maintaining full backwards-compatibility."""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            user = get_current_user()
            if not user:
                return jsonify({'error': 'Unauthorized', 'message': 'Authentication required. Please sign in.'}), 401
            effective_role = user.get_role_name()
            if effective_role not in allowed_roles:
                return jsonify({'error': f'Access denied. Required roles: {", ".join(allowed_roles)}'}), 403
            return f(*args, **kwargs)
        decorated_function._permission_protected = True
        decorated_function._allowed_roles = allowed_roles
        return decorated_function
    return decorator


def verify_step_up_auth(user):
    """
    Requires the current user to re-enter their current password for sensitive operations.
    Accepts password via 'X-Admin-Password' header or 'admin_password' / 'confirm_password' in request body.
    """
    if not user:
        return False, "Authentication required"

    pw = request.headers.get('X-Admin-Password')
    if not pw and request.is_json:
        data = request.get_json(silent=True) or {}
        pw = data.get('admin_password') or data.get('confirm_password') or data.get('current_password')
    if not pw and request.form:
        pw = request.form.get('admin_password') or request.form.get('confirm_password')

    if not pw:
        return False, "Step-up authentication required: Please confirm your password to perform this sensitive action."

    if not user.check_password(pw):
        return False, "Step-up authentication failed: Current password is incorrect."

    return True, None


def scoped_query(model, viewer=None):
    """
    Returns an SQLAlchemy query filtered by the viewer's data-level permissions.
    - If viewer has <resource>.view_all: returns unfiltered model query.
    - If viewer only has <resource>.view without view_all (e.g. Doctor):
      filters to records assigned to viewer.doctor_id.
    - If viewer lacks view permission: returns empty query (filter(false())).
    """
    if viewer is None:
        viewer = get_current_user()

    if not viewer or not viewer.is_active:
        return model.query.filter(db.false())

    if model == Patient:
        if user_has_permission(viewer, 'patients.view_all'):
            return Patient.query
        elif user_has_permission(viewer, 'patients.view'):
            if viewer.doctor_id:
                doc_patient_ids = [
                    r[0] for r in db.session.query(Appointment.patient_id)
                    .filter(Appointment.doctor_id == viewer.doctor_id).distinct().all()
                ]
                return Patient.query.filter(Patient.id.in_(doc_patient_ids))
            return Patient.query
        else:
            return Patient.query.filter(db.false())

    elif model == Appointment:
        if user_has_permission(viewer, 'appointments.view_all'):
            return Appointment.query
        elif user_has_permission(viewer, 'appointments.view'):
            if viewer.doctor_id:
                return Appointment.query.filter(Appointment.doctor_id == viewer.doctor_id)
            return Appointment.query
        else:
            return Appointment.query.filter(db.false())

    return model.query


@app.context_processor
def inject_rbac_helpers():
    user = get_current_user()
    user_perms = get_user_effective_permissions(user) if user else set()

    def can(perm_key):
        return perm_key in user_perms

    def can_any(keys):
        return any(k in user_perms for k in keys)

    return dict(
        current_user=user,
        can=can,
        can_any=can_any,
        user_permissions=sorted(list(user_perms))
    )


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
@require_permission('dashboard.view')
def index():
    return render_template('index.html')

@app.route('/login')
def login_page():
    if 'user_id' in session and get_current_user():
        return redirect(url_for('index'))
    return render_template('login.html')

@app.route('/patients')
@require_permission('patients.view')
def patients_page():
    return render_template('patients.html')

@app.route('/doctors')
@require_permission('doctors.view')
def doctors_page():
    return render_template('doctors.html')

@app.route('/rooms')
@require_permission('rooms.view')
def rooms_page():
    return render_template('rooms.html')

@app.route('/departments')
@require_permission('departments.view')
def departments_page():
    return render_template('departments.html')

@app.route('/appointments')
@require_permission('appointments.view')
def appointments_page():
    return render_template('appointments.html')

@app.route('/optimize')
@require_any(['optimization.run', 'optimization.history.view'])
def optimize_page():
    return render_template('optimize.html')

@app.route('/analytics')
@require_permission('analytics.view')
def analytics_page():
    return render_template('analytics.html')

@app.route('/history')
@require_permission('optimization.history.view')
def history_page():
    return render_template('history.html')

@app.route('/beds')
@require_permission('beds.view')
def beds_page():
    return render_template('beds.html')

@app.route('/equipment')
@require_permission('equipment.view')
def equipment_page():
    return render_template('equipment.html')

@app.route('/simulator')
@require_permission('simulation.run')
def simulator_page():
    return render_template('simulator.html')

@app.route('/queue-display')
@require_permission('queue_display.view')
def queue_display_page():
    return render_template('queue_display.html')

@app.route('/roles')
@require_permission('roles.view')
def roles_page():
    return render_template('roles.html')

@app.route('/users')
@require_permission('users.view')
def users_page():
    return render_template('users.html')

@app.route('/profile')
@login_required
def profile_page():
    return render_template('profile.html')

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
        perms = sorted(list(get_user_effective_permissions(user)))
        return jsonify({
            'authenticated': True,
            'user': user.to_dict(include_permissions=True),
            'role': user.get_role_name(),
            'permissions': perms,
            'permissions_version': user.permissions_version
        })
    return jsonify({'authenticated': False, 'user': None, 'permissions': []})
api_me._permission_protected = True


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


@app.route('/api/user/profile', methods=['GET'])
@login_required
def api_get_profile():
    user = get_current_user()
    if not user:
        return jsonify({'error': 'Authentication required'}), 401
    
    data = user.to_dict(include_permissions=True)
    if user.doctor:
        data['doctor'] = {
            'id': user.doctor.id,
            'name': user.doctor.name,
            'specialization': user.doctor.specialization,
            'department_name': user.doctor.department.name if user.doctor.department else ''
        }
    return jsonify({'success': True, 'user': data})


@app.route('/api/user/profile', methods=['PUT'])
@login_required
def api_update_profile():
    user = get_current_user()
    if not user:
        return jsonify({'error': 'Authentication required'}), 401

    data = request.get_json() or {}
    full_name = (data.get('full_name') or '').strip()
    email = (data.get('email') or '').strip().lower()

    if not full_name:
        return jsonify({'error': 'Full name cannot be empty'}), 400
    if not email or '@' not in email:
        return jsonify({'error': 'Valid email address is required'}), 400

    existing = User.query.filter(User.email == email, User.id != user.id).first()
    if existing:
        return jsonify({'error': 'Email address is already in use by another account'}), 409

    old_name = user.full_name
    old_email = user.email
    user.full_name = full_name
    user.email = email

    if user.doctor and old_name != full_name:
        user.doctor.name = full_name

    db.session.add(AuditLog(
        action='UPDATE',
        resource_type='user',
        resource_id=user.id,
        user_name=user.username,
        details=f"User updated personal profile (name: '{old_name}' -> '{full_name}', email: '{old_email}' -> '{email}')"
    ))
    db.session.commit()

    return jsonify({
        'success': True,
        'message': 'Profile updated successfully',
        'user': user.to_dict(include_permissions=True)
    })


# ─── API: Dashboard ───────────────────────────────────────────────────────────

@app.route('/api/dashboard')
@require_permission('dashboard.view')
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
@require_permission('patients.view')
def api_patients():
    user = get_current_user()
    search = request.args.get('search', '').strip().lower()
    priority = request.args.get('priority', '')
    query = scoped_query(Patient, user).options(joinedload(Patient.appointments))
    if search:
        query = query.filter(Patient.name.ilike(f'%{search}%'))
    if priority:
        query = query.filter_by(priority=priority)
    return jsonify([p.to_dict(viewer=user) for p in query.order_by(Patient.registered_at.desc()).all()])


@app.route('/api/patients', methods=['POST'])
@require_permission('patients.create')
def api_add_patient():
    user = get_current_user()
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
    return jsonify(patient.to_dict(viewer=user)), 201


@app.route('/api/patients/<int:pid>', methods=['PUT'])
@require_permission('patients.update')
def api_update_patient(pid):
    user = get_current_user()
    patient = db.get_or_404(Patient, pid)

    # Row-level guard: if not view_all and doctor, ensure patient belongs to doctor
    if not user_has_permission(user, 'patients.view_all') and user.doctor_id:
        doc_patient_ids = [
            r[0] for r in db.session.query(Appointment.patient_id)
            .filter(Appointment.doctor_id == user.doctor_id).distinct().all()
        ]
        if pid not in doc_patient_ids:
            return jsonify({'error': 'Forbidden', 'message': 'You cannot update patients outside your care.'}), 403

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
    return jsonify(patient.to_dict(viewer=user))


@app.route('/api/patients/<int:pid>', methods=['DELETE'])
@require_permission('patients.delete')
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
@require_permission('doctors.view')
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
@require_permission('doctors.manage')
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
@require_permission('doctors.manage')
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
@require_permission('doctors.manage')
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
@require_permission('rooms.view')
def api_rooms():
    rooms = Room.query.options(joinedload(Room.dept), joinedload(Room.beds)).all()
    return jsonify([r.to_dict() for r in rooms])


@app.route('/api/rooms', methods=['POST'])
@require_permission('rooms.manage')
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
@require_permission('rooms.manage')
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
@require_permission('rooms.manage')
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
@require_permission('departments.view')
def api_departments():
    depts = Department.query.all()
    return jsonify([d.to_dict() for d in depts])


@app.route('/api/departments', methods=['POST'])
@require_permission('departments.manage')
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
@require_permission('beds.view')
def api_beds():
    beds = Bed.query.options(
        joinedload(Bed.room),
        joinedload(Bed.dept),
        joinedload(Bed.patient)
    ).all()
    return jsonify([b.to_dict() for b in beds])


@app.route('/api/beds', methods=['POST'])
@require_permission('beds.manage')
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
@require_permission('beds.manage')
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
@require_permission('beds.admit_discharge')
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
@require_permission('beds.admit_discharge')
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
@require_permission('equipment.view')
def api_equipment():
    equip = Equipment.query.options(joinedload(Equipment.dept), joinedload(Equipment.room)).all()
    return jsonify([e.to_dict() for e in equip])


@app.route('/api/equipment', methods=['POST'])
@require_permission('equipment.manage')
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
@require_permission('equipment.manage')
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
@require_permission('appointments.view')
def api_appointments():
    user = get_current_user()
    status = request.args.get('status', '')
    date_filter = request.args.get('date', '')
    query = scoped_query(Appointment, user).options(
        joinedload(Appointment.patient),
        joinedload(Appointment.doctor),
        joinedload(Appointment.room),
        joinedload(Appointment.equipment)
    )
    if status:
        query = query.filter(Appointment.status == status)
    if date_filter:
        query = query.filter(Appointment.date == date_filter)
    return jsonify([a.to_dict(viewer=user) for a in query.order_by(Appointment.date, Appointment.start_time).all()])


VALID_APPOINTMENT_TRANSITIONS = {
    'scheduled': {'in_progress', 'cancelled', 'no_show'},
    'in_progress': {'completed', 'cancelled'},
    'completed': set(),
    'cancelled': set(),
    'no_show': set(),
}


@app.route('/api/appointments/<int:aid>/status', methods=['PATCH'])
@require_permission('appointments.update_status')
def api_update_appointment_status(aid):
    appt = db.get_or_404(Appointment, aid)
    current_user = get_current_user()
    if session.get('role') == 'doctor' or not user_has_permission(current_user, 'appointments.view_all'):
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
    return jsonify(appt.to_dict(viewer=current_user))


# ─── API: Emergency Code Red Walk-In ──────────────────────────────────────────

@app.route('/api/emergency/walkin', methods=['POST'])
@require_permission('emergency.trigger')
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
@require_permission('optimization.run')
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
@require_permission('simulation.run')
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
@require_permission('analytics.view')
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
@require_permission('analytics.view')
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
@require_permission('analytics.view')
def api_analytics_patients_status():
    all_patients = Patient.query.all()
    assigned_ids = {a.patient_id for a in Appointment.query.filter_by(status='scheduled').all()}
    assigned = len([p for p in all_patients if p.id in assigned_ids])
    unassigned = len(all_patients) - assigned
    return jsonify({'assigned': assigned, 'unassigned': unassigned})


@app.route('/api/optimization-runs')
@require_permission('optimization.history.view')
def api_optimization_runs():
    runs = OptimizationRun.query.order_by(OptimizationRun.created_at.desc()).all()
    return jsonify([r.to_dict() for r in runs])


@app.route('/api/audit-logs')
@require_permission('audit.view')
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
@require_permission('export.csv')
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


# ─── API: Roles & Permissions (Dynamic RBAC) ──────────────────────────────────

@app.route('/api/roles', methods=['GET'])
@require_permission('roles.view')
def api_roles_list():
    roles = Role.query.order_by(Role.is_system.desc(), Role.name.asc()).all()
    perms = Permission.query.order_by(Permission.group, Permission.key).all()
    return jsonify({
        'roles': [r.to_dict(include_permissions=True) for r in roles],
        'catalog': [p.to_dict() for p in perms],
        'groups': PERMISSION_GROUPS
    })


@app.route('/api/roles', methods=['POST'])
@require_permission('roles.manage')
def api_create_role():
    user = get_current_user()
    ok, err_msg = verify_step_up_auth(user)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    data = request.get_json() or {}
    name = (data.get('name') or '').strip().lower()
    description = (data.get('description') or '').strip()
    perm_keys = data.get('permissions') or []

    if not name:
        return jsonify({'error': 'Role name is required'}), 400
    if len(name) < 2 or not name.isalnum():
        return jsonify({'error': 'Role name must be alphanumeric and at least 2 characters'}), 400
    if Role.query.filter_by(name=name).first():
        return jsonify({'error': f"Role '{name}' already exists"}), 409

    # Privilege escalation guard: non-admin cannot grant permissions they do not possess
    user_perms = get_user_effective_permissions(user)
    if user.get_role_name() != 'admin':
        unauthorized_grants = [k for k in perm_keys if k not in user_perms]
        if unauthorized_grants:
            return jsonify({
                'error': 'PrivilegeEscalationBlocked',
                'message': f"Cannot grant permissions you do not possess: {', '.join(unauthorized_grants)}"
            }), 403

    perms_objs = Permission.query.filter(Permission.key.in_(perm_keys)).all()

    new_role = Role(
        name=name,
        description=description,
        is_system=False,
        is_locked=False,
        version=1
    )
    new_role.permissions = perms_objs
    db.session.add(new_role)

    log_audit('CREATE', 'role', None, f"Created custom role '{name}' with {len(perms_objs)} permissions")
    db.session.commit()

    return jsonify(new_role.to_dict(include_permissions=True)), 201


@app.route('/api/roles/<int:rid>', methods=['GET'])
@require_permission('roles.view')
def api_get_role(rid):
    role = db.get_or_404(Role, rid)
    return jsonify(role.to_dict(include_permissions=True))


@app.route('/api/roles/<int:rid>', methods=['PUT'])
@require_permission('roles.manage')
def api_update_role(rid):
    user = get_current_user()
    ok, err_msg = verify_step_up_auth(user)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    role = db.get_or_404(Role, rid)
    if role.is_locked:
        return jsonify({'error': 'RoleLocked', 'message': f"Role '{role.name}' is locked and its permissions cannot be modified."}), 403

    data = request.get_json() or {}
    description = data.get('description', role.description)
    perm_keys = data.get('permissions')

    if perm_keys is not None:
        user_perms = get_user_effective_permissions(user)
        if user.get_role_name() != 'admin':
            unauthorized_grants = [k for k in perm_keys if k not in user_perms]
            if unauthorized_grants:
                return jsonify({
                    'error': 'PrivilegeEscalationBlocked',
                    'message': f"Cannot grant permissions you do not possess: {', '.join(unauthorized_grants)}"
                }), 403

        perms_objs = Permission.query.filter(Permission.key.in_(perm_keys)).all()
        role.permissions = perms_objs

    role.description = description
    role.version += 1  # Invalidate cached permissions for users of this role

    log_audit('UPDATE', 'role', role.id, f"Updated role '{role.name}' permissions (v{role.version})")
    db.session.commit()

    return jsonify(role.to_dict(include_permissions=True))


@app.route('/api/roles/<int:rid>', methods=['DELETE'])
@require_permission('roles.manage')
def api_delete_role(rid):
    user = get_current_user()
    ok, err_msg = verify_step_up_auth(user)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    role = db.get_or_404(Role, rid)
    if role.is_system:
        return jsonify({'error': 'SystemRoleProtected', 'message': f"System role '{role.name}' cannot be deleted."}), 400

    if role.users:
        return jsonify({'error': 'RoleInUse', 'message': f"Cannot delete role '{role.name}': {len(role.users)} users are currently assigned to it."}), 400

    role_name = role.name
    db.session.delete(role)
    log_audit('DELETE', 'role', rid, f"Deleted custom role '{role_name}'")
    db.session.commit()

    return jsonify({'message': f"Role '{role_name}' deleted successfully"})


# ─── API: User Management & Overrides ──────────────────────────────────────────

@app.route('/api/users', methods=['GET'])
@require_permission('users.view')
def api_users_list():
    users = User.query.order_by(User.username.asc()).all()
    roles = Role.query.order_by(Role.name.asc()).all()
    doctors = Doctor.query.order_by(Doctor.name.asc()).all()
    return jsonify({
        'users': [u.to_dict(include_permissions=True) for u in users],
        'roles': [{'id': r.id, 'name': r.name, 'is_locked': r.is_locked, 'description': r.description} for r in roles],
        'doctors': [{'id': d.id, 'name': d.name, 'specialization': d.specialization} for d in doctors]
    })


@app.route('/api/users', methods=['POST'])
@require_permission('users.manage')
def api_create_user():
    user = get_current_user()
    ok, err_msg = verify_step_up_auth(user)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    data = request.get_json() or {}
    username = (data.get('username') or '').strip().lower()
    email = (data.get('email') or '').strip().lower()
    password = data.get('password', '')
    full_name = (data.get('full_name') or '').strip()
    role_id = safe_int(data.get('role_id'))
    doctor_id = safe_int(data.get('doctor_id')) or None

    if not username or not email or not password:
        return jsonify({'error': 'Username, email, and password are required'}), 400
    if len(password) < 8:
        return jsonify({'error': 'Password must be at least 8 characters long'}), 400

    if User.query.filter_by(username=username).first():
        return jsonify({'error': f"Username '{username}' is already taken"}), 409
    if User.query.filter_by(email=email).first():
        return jsonify({'error': f"Email '{email}' is already in use"}), 409

    role = db.session.get(Role, role_id) if role_id else Role.query.filter_by(name='receptionist').first()
    if not role:
        return jsonify({'error': 'Selected role does not exist'}), 400

    new_user = User(
        username=username,
        email=email,
        role=role.name,
        role_id=role.id,
        full_name=full_name or username,
        doctor_id=doctor_id,
        is_active=True,
        must_change_password=data.get('must_change_password', True)
    )
    new_user.set_password(password)
    db.session.add(new_user)
    db.session.flush()

    log_audit('CREATE', 'user', new_user.id, f"Created user {username} with role {role.name}")
    db.session.commit()

    return jsonify(new_user.to_dict(include_permissions=True)), 201


@app.route('/api/users/<int:uid>/role', methods=['PUT'])
@require_permission('users.manage')
def api_assign_user_role(uid):
    current_admin = get_current_user()
    ok, err_msg = verify_step_up_auth(current_admin)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    target_user = db.get_or_404(User, uid)
    data = request.get_json() or {}
    new_role_id = safe_int(data.get('role_id'))
    new_role = db.session.get(Role, new_role_id)
    if not new_role:
        return jsonify({'error': 'Invalid role_id'}), 400

    # Safeguard 1: Admin cannot demote themselves
    if target_user.id == current_admin.id and target_user.get_role_name() == 'admin' and new_role.name != 'admin':
        return jsonify({'error': 'SelfDemotionBlocked', 'message': 'You cannot remove your own administrator role.'}), 400

    # Safeguard 2: Cannot demote the last active administrator
    if target_user.get_role_name() == 'admin' and new_role.name != 'admin':
        admin_role = Role.query.filter_by(name='admin').first()
        active_admins = User.query.filter(User.role_id == admin_role.id, User.is_active == True).count() if admin_role else 0
        if active_admins <= 1:
            return jsonify({'error': 'LastAdminProtected', 'message': 'Cannot demote the last active administrator in the system.'}), 400

    old_role_name = target_user.get_role_name()
    target_user.role_id = new_role.id
    target_user.role = new_role.name
    target_user.permissions_version += 1  # Invalidate permission cache

    log_audit('UPDATE_ROLE', 'user', target_user.id, f"Changed user {target_user.username} role from {old_role_name} to {new_role.name}")
    db.session.commit()

    return jsonify(target_user.to_dict(include_permissions=True))


@app.route('/api/users/<int:uid>/status', methods=['PATCH'])
@require_permission('users.manage')
def api_toggle_user_status(uid):
    current_admin = get_current_user()
    ok, err_msg = verify_step_up_auth(current_admin)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    target_user = db.get_or_404(User, uid)
    data = request.get_json() or {}
    new_status = data.get('is_active')
    if new_status is None:
        new_status = not target_user.is_active

    # Safeguard 1: Cannot disable own account
    if target_user.id == current_admin.id and not new_status:
        return jsonify({'error': 'SelfDisableBlocked', 'message': 'You cannot deactivate your own account.'}), 400

    # Safeguard 2: Cannot deactivate the last active administrator
    if target_user.get_role_name() == 'admin' and not new_status:
        admin_role = Role.query.filter_by(name='admin').first()
        active_admins = User.query.filter(User.role_id == admin_role.id, User.is_active == True).count() if admin_role else 0
        if active_admins <= 1:
            return jsonify({'error': 'LastAdminProtected', 'message': 'Cannot deactivate the last active administrator.'}), 400

    target_user.is_active = bool(new_status)
    target_user.permissions_version += 1

    status_str = 'activated' if target_user.is_active else 'deactivated'
    log_audit('UPDATE_STATUS', 'user', target_user.id, f"Account {target_user.username} {status_str}")
    db.session.commit()

    return jsonify(target_user.to_dict(include_permissions=True))


@app.route('/api/users/<int:uid>/overrides', methods=['POST'])
@require_permission('users.manage')
def api_add_user_override(uid):
    current_admin = get_current_user()
    ok, err_msg = verify_step_up_auth(current_admin)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    target_user = db.get_or_404(User, uid)
    data = request.get_json() or {}
    perm_key = data.get('permission_key')
    perm_id = safe_int(data.get('permission_id'))
    effect = (data.get('effect') or '').strip().lower()
    reason = (data.get('reason') or '').strip()

    if effect not in ('grant', 'deny'):
        return jsonify({'error': "Effect must be 'grant' or 'deny'"}), 400
    if not reason:
        return jsonify({'error': 'Reason is required for auditing security overrides'}), 400

    perm = None
    if perm_id:
        perm = db.session.get(Permission, perm_id)
    elif perm_key:
        perm = Permission.query.filter_by(key=perm_key).first()

    if not perm:
        return jsonify({'error': 'Permission not found'}), 404

    # Privilege escalation guard: non-admin cannot grant permissions they don't have
    if effect == 'grant' and current_admin.get_role_name() != 'admin':
        if not user_has_permission(current_admin, perm.key):
            return jsonify({
                'error': 'PrivilegeEscalationBlocked',
                'message': f"Cannot grant permission '{perm.key}' that you do not hold."
            }), 403

    override = UserPermissionOverride.query.filter_by(user_id=target_user.id, permission_id=perm.id).first()
    if not override:
        override = UserPermissionOverride(
            user_id=target_user.id,
            permission_id=perm.id,
            effect=effect,
            reason=reason,
            created_by=current_admin.username
        )
        db.session.add(override)
    else:
        override.effect = effect
        override.reason = reason
        override.created_by = current_admin.username

    target_user.permissions_version += 1  # Invalidate permission cache
    log_audit('OVERRIDE', 'user', target_user.id, f"Set {effect.upper()} override for {perm.key} on {target_user.username}: {reason}")
    db.session.commit()

    return jsonify(target_user.to_dict(include_permissions=True)), 201


@app.route('/api/users/<int:uid>/overrides/<int:perm_id>', methods=['DELETE'])
@require_permission('users.manage')
def api_delete_user_override(uid, perm_id):
    current_admin = get_current_user()
    ok, err_msg = verify_step_up_auth(current_admin)
    if not ok:
        return jsonify({'error': 'StepUpAuthRequired', 'message': err_msg}), 401

    target_user = db.get_or_404(User, uid)
    override = UserPermissionOverride.query.filter_by(user_id=target_user.id, permission_id=perm_id).first()
    if not override:
        return jsonify({'error': 'Override not found'}), 404

    perm_key = override.permission.key if override.permission else str(perm_id)
    db.session.delete(override)
    target_user.permissions_version += 1
    log_audit('DELETE_OVERRIDE', 'user', target_user.id, f"Removed override for {perm_key} on {target_user.username}")
    db.session.commit()

    return jsonify(target_user.to_dict(include_permissions=True))


# ─── Main Execution ───────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("=" * 65)
    print("  Smart Hospital Resource Optimization System (Enterprise Pro)")
    print("  Running at: http://127.0.0.1:5000")
    print("=" * 65)
    app.run(debug=True, port=5000)

"""
models.py - Enhanced Database Models for Smart Hospital Resource Optimization System
Includes Users, RBAC, Beds, Equipment, Triage Vitals, and Audit Logs.
"""

from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import validates
from datetime import datetime, timezone
import secrets
import re
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()


def utc_now():
    """Return timezone-aware current UTC datetime."""
    return datetime.now(timezone.utc)


COMMON_INSECURE_PASSWORDS = {
    'password', 'password123', 'admin', 'admin123', 'hospital',
    'hospital123', 'doctor', 'doctor123', 'nurse', 'reception',
    'manager', 'medicare', '123456789012', 'qwertyuiopas', 'welcome12345'
}


def validate_password_complexity(password: str, user=None) -> tuple[bool, str | None]:
    """
    Validate password complexity:
    - Minimum length: 12 characters.
    - Requires at least one uppercase letter, one lowercase letter, one digit, and one special symbol.
    - Rejects common patterns, predictable repetitions, sequences, and personal identifier leaks.
    """
    if not password or len(password) < 12:
        return False, "Password must be at least 12 characters long."
    if not re.search(r'[A-Z]', password):
        return False, "Password must contain at least one uppercase letter (A-Z)."
    if not re.search(r'[a-z]', password):
        return False, "Password must contain at least one lowercase letter (a-z)."
    if not re.search(r'\d', password):
        return False, "Password must contain at least one digit (0-9)."
    if not re.search(r'[!@#$%^&*()_+\-=\[\]{}|;:,.<>?~`]', password):
        return False, "Password must contain at least one special character (e.g. !@#$%^&*)."
    if re.search(r'(.)\1{3,}', password):
        return False, "Password contains too many repeated consecutive characters."

    lower_pwd = password.lower()
    common_sequences = ['123456', '654321', '234567', '765432', 'abcdef', 'qwerty', 'asdfgh', 'zxcvbn']
    for seq in common_sequences:
        if seq in lower_pwd:
            return False, f"Password cannot contain simple keyboard sequences like '{seq}'."

    for word in COMMON_INSECURE_PASSWORDS:
        if word in lower_pwd:
            return False, "Password contains common or predictable words."

    if user:
        uname = (getattr(user, 'username', '') or '').lower()
        if len(uname) >= 3 and uname in lower_pwd:
            return False, "Password cannot contain your username."
        email = (getattr(user, 'email', '') or '').lower()
        email_prefix = email.split('@')[0] if '@' in email else ''
        if len(email_prefix) >= 3 and email_prefix in lower_pwd:
            return False, "Password cannot contain your email identifier."

    return True, None


def generate_secure_temporary_password(length=14) -> str:
    """Generate a cryptographically secure temporary password exceeding minimum complexity requirements."""
    chars_upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    chars_lower = "abcdefghijkmnopqrstuvwxyz"
    chars_digits = "23456789"
    chars_symbols = "!@#$%^&*()_+-="
    all_chars = chars_upper + chars_lower + chars_digits + chars_symbols

    pwd = [
        secrets.choice(chars_upper), secrets.choice(chars_upper),
        secrets.choice(chars_lower), secrets.choice(chars_lower),
        secrets.choice(chars_digits), secrets.choice(chars_digits),
        secrets.choice(chars_symbols), secrets.choice(chars_symbols),
    ]
    pwd += [secrets.choice(all_chars) for _ in range(max(0, length - len(pwd)))]
    secrets.SystemRandom().shuffle(pwd)
    return ''.join(pwd)


def format_doctor_name(name: str | None, with_title: bool = True) -> str:
    """
    Normalizes a doctor's name, stripping duplicate or unwanted 'Dr.' prefixes.
    When with_title=True, returns 'Dr. <Name>' (e.g., 'Dr. Sarah Mitchell').
    When with_title=False, returns bare '<Name>' (e.g., 'Sarah Mitchell').
    Guarantees it will never produce 'Dr. Dr. <Name>'.
    """
    if not name:
        return ""
    cleaned = str(name).strip()
    while re.match(r'^(?:dr\.|dr\b)\s*', cleaned, flags=re.IGNORECASE):
        cleaned = re.sub(r'^(?:dr\.|dr\b)\s*', '', cleaned, count=1, flags=re.IGNORECASE).strip()
    if cleaned.lower() in ('dr', 'dr.'):
        cleaned = ""
    if not cleaned:
        return ""
    return f"Dr. {cleaned}" if with_title else cleaned


# ─── Dynamic RBAC Models ───────────────────────────────────────────────────────

# Association table for Role <-> Permission Many-to-Many
role_permissions = db.Table(
    'role_permissions',
    db.Column('role_id', db.Integer, db.ForeignKey('roles.id', ondelete='CASCADE'), primary_key=True),
    db.Column('permission_id', db.Integer, db.ForeignKey('permissions.id', ondelete='CASCADE'), primary_key=True)
)


class Permission(db.Model):
    """Authoritative Permission registry entry stored in DB"""
    __tablename__ = 'permissions'

    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(80), unique=True, nullable=False, index=True)
    group = db.Column(db.String(50), nullable=False, index=True)
    label_en = db.Column(db.String(120), nullable=False)
    label_ar = db.Column(db.String(120), nullable=False)
    description = db.Column(db.Text, default='')
    is_sensitive = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    def to_dict(self):
        return {
            'id': self.id,
            'key': self.key,
            'group': self.group,
            'label_en': self.label_en,
            'label_ar': self.label_ar,
            'description': self.description,
            'is_sensitive': self.is_sensitive
        }


class Role(db.Model):
    """Dynamic Role with assigned permissions and lock guards"""
    __tablename__ = 'roles'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(60), unique=True, nullable=False, index=True)
    description = db.Column(db.String(255), default='')
    is_system = db.Column(db.Boolean, default=False, nullable=False)  # System roles cannot be deleted
    is_locked = db.Column(db.Boolean, default=False, nullable=False)  # Admin role is locked: permissions immutable
    version = db.Column(db.Integer, default=1, nullable=False)        # Incremented on permission edit for cache busting
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)
    updated_at = db.Column(db.DateTime(timezone=True), default=utc_now, onupdate=utc_now)

    # Relationships
    permissions = db.relationship('Permission', secondary=role_permissions, backref=db.backref('roles', lazy='dynamic'), lazy='joined')
    users = db.relationship('User', backref='assigned_role', lazy='select')

    def to_dict(self, include_permissions=True):
        data = {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'is_system': self.is_system,
            'is_locked': self.is_locked,
            'version': self.version,
            'users_count': len(self.users),
            'permissions_count': len(self.permissions),
            'created_at': self.created_at.isoformat() if self.created_at else '',
            'updated_at': self.updated_at.isoformat() if self.updated_at else ''
        }
        if include_permissions:
            data['permissions'] = [p.key for p in self.permissions]
        return data


class UserPermissionOverride(db.Model):
    """Per-user permission override (explicit grant or deny)"""
    __tablename__ = 'user_permission_overrides'
    __table_args__ = (
        db.UniqueConstraint('user_id', 'permission_id', name='uq_user_permission_override'),
    )

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    permission_id = db.Column(db.Integer, db.ForeignKey('permissions.id', ondelete='CASCADE'), nullable=False)
    effect = db.Column(db.String(10), nullable=False)  # 'grant' or 'deny'
    reason = db.Column(db.String(255), nullable=False)
    created_by = db.Column(db.String(80), default='admin')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    # Relationship
    permission = db.relationship('Permission', lazy='joined')

    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'permission_id': self.permission_id,
            'permission_key': self.permission.key if self.permission else None,
            'effect': self.effect,
            'reason': self.reason,
            'created_by': self.created_by,
            'created_at': self.created_at.isoformat() if self.created_at else ''
        }


# ─── User & Authentication Model ──────────────────────────────────────────────

class User(db.Model):
    """System User for Role-Based Access Control (Admin, Doctor, Receptionist, Manager)"""
    __tablename__ = 'users'

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(30), default='receptionist')  # Legacy string fallback
    role_id = db.Column(db.Integer, db.ForeignKey('roles.id'), nullable=True)
    full_name = db.Column(db.String(150), default='')
    doctor_id = db.Column(db.Integer, db.ForeignKey('doctors.id'), nullable=True)
    must_change_password = db.Column(db.Boolean, default=False, nullable=False)
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    failed_login_attempts = db.Column(db.Integer, default=0, nullable=False)
    locked_until = db.Column(db.DateTime(timezone=True), nullable=True)
    permissions_version = db.Column(db.Integer, default=1, nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    doctor = db.relationship('Doctor', backref=db.backref('user_account', uselist=False))
    permission_overrides = db.relationship('UserPermissionOverride', backref='user', cascade='all, delete-orphan', lazy='joined')

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def get_role_name(self) -> str:
        """Return role name from assigned_role relationship or fallback to role column."""
        if self.assigned_role:
            return self.assigned_role.name
        return self.role or 'receptionist'

    def get_effective_permissions(self) -> set:
        """
        Compute effective permissions dynamically:
        Effective = (Role Permissions ∪ User Grants) - User Denies.
        Deny always takes absolute precedence.
        """
        perms = set()
        if self.assigned_role and self.assigned_role.permissions:
            perms = {p.key for p in self.assigned_role.permissions}

        # Apply user overrides
        for ovr in self.permission_overrides:
            if ovr.permission:
                if ovr.effect == 'grant':
                    perms.add(ovr.permission.key)
                elif ovr.effect == 'deny':
                    perms.discard(ovr.permission.key)
        return perms

    def has_permission(self, perm_key: str) -> bool:
        """Check if user holds an active permission."""
        if not self.is_active:
            return False
        return perm_key in self.get_effective_permissions()

    def to_dict(self, include_permissions=False):
        effective_role = self.get_role_name()
        data = {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'role': effective_role,
            'role_id': self.role_id,
            'full_name': self.full_name or self.username,
            'doctor_id': self.doctor_id,
            'is_active': self.is_active,
            'must_change_password': self.must_change_password,
            'permissions_version': self.permissions_version
        }
        if include_permissions:
            data['permissions'] = sorted(list(self.get_effective_permissions()))
            data['overrides'] = [ovr.to_dict() for ovr in self.permission_overrides]
        return data


# ─── Department Model ─────────────────────────────────────────────────────────

class Department(db.Model):
    """Hospital Department model"""
    __tablename__ = 'departments'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False, unique=True)
    capacity = db.Column(db.Integer, default=50)
    description = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    # Relationships
    doctors = db.relationship('Doctor', backref='dept', lazy=True)
    rooms = db.relationship('Room', backref='dept', lazy=True)
    beds = db.relationship('Bed', backref='dept', lazy=True)
    equipment = db.relationship('Equipment', backref='dept', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'capacity': self.capacity,
            'description': self.description,
            'doctor_count': len(self.doctors),
            'room_count': len(self.rooms),
            'bed_count': len(self.beds),
            'equipment_count': len(self.equipment)
        }


# ─── Doctor Model ─────────────────────────────────────────────────────────────

class Doctor(db.Model):
    """Doctor model with scheduling parameters"""
    __tablename__ = 'doctors'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    specialization = db.Column(db.String(100), nullable=False)
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    max_patients_per_day = db.Column(db.Integer, default=10)
    available_from = db.Column(db.String(10), default='08:00')  # HH:MM
    available_until = db.Column(db.String(10), default='17:00')  # HH:MM
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    # Relationships
    appointments = db.relationship('Appointment', backref='doctor', lazy=True)

    @validates('name')
    def validate_name(self, key, value):
        return format_doctor_name(value, with_title=True)

    @property
    def clean_name(self):
        return format_doctor_name(self.name, with_title=False)

    @property
    def formatted_name(self):
        return format_doctor_name(self.name, with_title=True)

    @property
    def department(self):
        """Compatibility property alias for department relationship (backref 'dept')."""
        return self.dept

    def to_dict(self, appointments_today=None):
        if appointments_today is None:
            today_iso = datetime.now(timezone.utc).date().isoformat()
            appointments_today = Appointment.query.filter(
                Appointment.doctor_id == self.id,
                Appointment.date == today_iso,
                Appointment.status != 'cancelled'
            ).count()
        return {
            'id': self.id,
            'name': format_doctor_name(self.name, with_title=True),
            'clean_name': format_doctor_name(self.name, with_title=False),
            'specialization': self.specialization,
            'department_id': self.department_id,
            'department_name': self.dept.name if self.dept else 'Unknown',
            'max_patients_per_day': self.max_patients_per_day,
            'available_from': self.available_from,
            'available_until': self.available_until,
            'appointments_today': appointments_today,
            'utilization_today': round((appointments_today / self.max_patients_per_day * 100), 1) if self.max_patients_per_day else 0
        }


# ─── Room Model ───────────────────────────────────────────────────────────────

class Room(db.Model):
    """Hospital Room model"""
    __tablename__ = 'rooms'

    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(20), nullable=False, unique=True)
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    room_type = db.Column(db.String(50), default='consultation')  # consultation, surgery, icu, ward
    capacity = db.Column(db.Integer, default=1)
    status = db.Column(db.String(20), default='available')  # available, occupied, maintenance
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    # Relationships
    appointments = db.relationship('Appointment', backref='room', lazy=True)
    beds = db.relationship('Bed', backref='room', lazy=True)
    equipment = db.relationship('Equipment', backref='room', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'room_number': self.room_number,
            'department_id': self.department_id,
            'department_name': self.dept.name if self.dept else 'Unknown',
            'room_type': self.room_type,
            'capacity': self.capacity,
            'status': self.status,
            'bed_count': len(self.beds)
        }


# ─── Bed Model ────────────────────────────────────────────────────────────────

class Bed(db.Model):
    """Hospital Inpatient Bed Model"""
    __tablename__ = 'beds'

    id = db.Column(db.Integer, primary_key=True)
    bed_number = db.Column(db.String(30), nullable=False, unique=True)
    room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=False)
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    status = db.Column(db.String(20), default='vacant')  # vacant, occupied, cleaning, reserved
    patient_id = db.Column(db.Integer, db.ForeignKey('patients.id'), nullable=True)
    admission_date = db.Column(db.String(20), default='')
    expected_discharge = db.Column(db.String(20), default='')
    notes = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    patient = db.relationship('Patient', backref=db.backref('admitted_bed', uselist=False))

    def to_dict(self):
        return {
            'id': self.id,
            'bed_number': self.bed_number,
            'room_id': self.room_id,
            'room_number': self.room.room_number if self.room else '',
            'department_id': self.department_id,
            'department_name': self.dept.name if self.dept else '',
            'status': self.status,
            'patient_id': self.patient_id,
            'patient_name': self.patient.name if self.patient else None,
            'admission_date': self.admission_date,
            'expected_discharge': self.expected_discharge,
            'notes': self.notes
        }


# ─── Equipment Model ──────────────────────────────────────────────────────────

class Equipment(db.Model):
    """Medical Device / Equipment Inventory Model"""
    __tablename__ = 'equipment'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    equipment_type = db.Column(db.String(60), nullable=False)  # ventilator, mri, ct_scanner, ecg, surgical_kit, ultrasound
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=True)
    status = db.Column(db.String(30), default='available')  # available, in_use, maintenance
    notes = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'equipment_type': self.equipment_type,
            'department_id': self.department_id,
            'department_name': self.dept.name if self.dept else '',
            'room_id': self.room_id,
            'room_number': self.room.room_number if self.room else 'Portable / Mobile',
            'status': self.status,
            'notes': self.notes
        }


def mask_patient_name(name: str) -> str:
    """Mask patient name for privacy in demo or public displays (e.g. Alice Johnson -> A*** J.)"""
    if not name:
        return ""
    parts = name.strip().split()
    if len(parts) == 1:
        w = parts[0]
        return (w[0] + "***") if len(w) > 1 else w
    first = parts[0][0] + "***"
    last = parts[-1][0] + "."
    return f"{first} {last}"


# ─── Patient Model ────────────────────────────────────────────────────────────

class Patient(db.Model):
    """Patient model with vital signs, triage ESI level, and predictive no-show score"""
    __tablename__ = 'patients'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    gender = db.Column(db.String(10), nullable=False)
    priority = db.Column(db.String(20), default='normal')  # critical, urgent, normal, low
    required_specialization = db.Column(db.String(100), nullable=False)
    condition_description = db.Column(db.Text, default='')
    # TODO: Convert preferred_date string to Date native type in a future schema migration.
    preferred_date = db.Column(db.String(20), default='')
    
    # Clinical Triage & Vitals
    triage_level = db.Column(db.Integer, default=3)  # ESI Level 1 (Resuscitation) to 5 (Non-urgent)
    blood_pressure = db.Column(db.String(20), default='120/80')
    heart_rate = db.Column(db.Integer, default=75)
    spo2 = db.Column(db.Integer, default=98)  # Oxygen saturation %
    temperature = db.Column(db.Float, default=37.0)
    
    # ML Prediction
    no_show_risk = db.Column(db.Float, default=0.1)  # 0.0 to 1.0 probability
    
    registered_at = db.Column(db.DateTime(timezone=True), default=utc_now)
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        db.Index('idx_patients_priority_preferred_date', 'priority', 'preferred_date'),
    )

    # Relationships
    appointments = db.relationship('Appointment', backref='patient', lazy=True)

    def priority_score(self):
        """Numeric priority score for optimization (higher = more priority)"""
        scores = {'critical': 4, 'urgent': 3, 'normal': 2, 'low': 1}
        return scores.get(self.priority, 2)

    def to_dict(self, latest_status=None, viewer=None):
        if latest_status is None:
            if self.appointments:
                latest_status = sorted(self.appointments, key=lambda a: a.created_at, reverse=True)[0].status
            else:
                latest_status = 'unscheduled'

        display_name = self.name
        is_demo = False
        can_view_clinical = True

        if viewer:
            if hasattr(viewer, 'has_permission'):
                can_view_clinical = viewer.has_permission('patients.view_clinical')
                if getattr(viewer, 'get_role_name', lambda: '')() == 'demo_viewer':
                    is_demo = True
            elif isinstance(viewer, dict):
                can_view_clinical = 'patients.view_clinical' in viewer.get('permissions', [])
                if viewer.get('role') == 'demo_viewer':
                    is_demo = True

        if is_demo:
            display_name = mask_patient_name(self.name)

        return {
            'id': self.id,
            'name': display_name,
            'age': self.age,
            'gender': self.gender,
            'priority': self.priority,
            'triage_level': self.triage_level if can_view_clinical else None,
            'required_specialization': self.required_specialization,
            'condition_description': self.condition_description if can_view_clinical else '[Protected Clinical Details]',
            'preferred_date': self.preferred_date,
            'vitals': {
                'bp': self.blood_pressure or '120/80',
                'hr': self.heart_rate or 75,
                'spo2': self.spo2 or 98,
                'temp': self.temperature or 37.0
            } if can_view_clinical else None,
            'no_show_risk': round(self.no_show_risk or 0.1, 2),
            'registered_at': self.registered_at.isoformat() if self.registered_at else '',
            'appointment_status': latest_status
        }


# ─── Appointment Model ────────────────────────────────────────────────────────

class Appointment(db.Model):
    """Appointment / Schedule model with procedure duration, buffers, and clinical logs"""
    __tablename__ = 'appointments'

    id = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey('patients.id'), nullable=False)
    doctor_id = db.Column(db.Integer, db.ForeignKey('doctors.id'), nullable=False)
    room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=False)
    # TODO: Convert date, start_time, end_time strings to Date and Time native types in a future schema migration.
    date = db.Column(db.String(20), nullable=False)
    start_time = db.Column(db.String(10), nullable=False)
    end_time = db.Column(db.String(10), nullable=False)
    duration_minutes = db.Column(db.Integer, default=30)
    buffer_minutes = db.Column(db.Integer, default=10)
    waiting_time = db.Column(db.Integer, default=0)  # in minutes
    status = db.Column(db.String(20), default='scheduled')  # scheduled, in_progress, completed, cancelled, no_show
    is_emergency = db.Column(db.Boolean, default=False)
    equipment_id = db.Column(db.Integer, db.ForeignKey('equipment.id'), nullable=True)
    notes = db.Column(db.Text, default='')
    clinical_notes = db.Column(db.Text, default='')
    prescription = db.Column(db.Text, default='')
    optimization_run_id = db.Column(db.Integer, db.ForeignKey('optimization_runs.id'), nullable=True)
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        db.Index('idx_appointments_lookup', 'date', 'doctor_id', 'room_id', 'status'),
    )

    equipment = db.relationship('Equipment', backref='appointments', lazy=True)

    def to_dict(self, viewer=None):
        display_patient_name = self.patient.name if self.patient else 'Unknown'
        can_view_clinical = True
        is_demo = False

        if viewer:
            if hasattr(viewer, 'has_permission'):
                can_view_clinical = viewer.has_permission('patients.view_clinical')
                if getattr(viewer, 'get_role_name', lambda: '')() == 'demo_viewer':
                    is_demo = True
            elif isinstance(viewer, dict):
                can_view_clinical = 'patients.view_clinical' in viewer.get('permissions', [])
                if viewer.get('role') == 'demo_viewer':
                    is_demo = True

        if is_demo and self.patient:
            display_patient_name = mask_patient_name(self.patient.name)

        return {
            'id': self.id,
            'patient_id': self.patient_id,
            'patient_name': display_patient_name,
            'patient_priority': self.patient.priority if self.patient else 'normal',
            'patient_triage': (self.patient.triage_level if self.patient else 3) if can_view_clinical else None,
            'doctor_id': self.doctor_id,
            'doctor_name': format_doctor_name(self.doctor.name, with_title=True) if self.doctor else 'Unknown',
            'doctor_specialization': self.doctor.specialization if self.doctor else '',
            'room_id': self.room_id,
            'room_number': self.room.room_number if self.room else 'Unknown',
            'equipment_name': self.equipment.name if self.equipment else None,
            'date': self.date,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'duration_minutes': self.duration_minutes,
            'buffer_minutes': self.buffer_minutes,
            'waiting_time': self.waiting_time,
            'status': self.status,
            'is_emergency': bool(self.is_emergency),
            'notes': self.notes,
            'clinical_notes': self.clinical_notes if can_view_clinical else '[Protected Clinical Notes]',
            'prescription': self.prescription if can_view_clinical else '[Protected Prescription]',
            'created_at': self.created_at.isoformat() if self.created_at else ''
        }


# ─── Optimization Run Model ───────────────────────────────────────────────────

class OptimizationRun(db.Model):
    """Optimization Run History model"""
    __tablename__ = 'optimization_runs'

    id = db.Column(db.Integer, primary_key=True)
    algorithm = db.Column(db.String(50), nullable=False)  # requested algorithm: lp, greedy, hybrid
    algorithm_used = db.Column(db.String(50), nullable=True)  # actual algorithm executed: lp, greedy, hybrid
    fallback_reason = db.Column(db.String(255), nullable=True)
    run_date = db.Column(db.String(20), nullable=False)
    total_patients = db.Column(db.Integer, default=0)
    assigned_patients = db.Column(db.Integer, default=0)
    unassigned_patients = db.Column(db.Integer, default=0)
    avg_wait_time = db.Column(db.Float, default=0.0)
    utilization_rate = db.Column(db.Float, default=0.0)
    status = db.Column(db.String(20), default='success')  # success, failed, partial
    solver_log = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    # Relationships
    appointments = db.relationship('Appointment', backref='optimization_run', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'algorithm': self.algorithm,
            'algorithm_used': getattr(self, 'algorithm_used', None) or self.algorithm,
            'fallback_reason': getattr(self, 'fallback_reason', None) or '',
            'run_date': self.run_date,
            'total_patients': self.total_patients,
            'assigned_patients': self.assigned_patients,
            'unassigned_patients': self.unassigned_patients,
            'avg_wait_time': round(self.avg_wait_time, 2),
            'utilization_rate': round(self.utilization_rate, 2),
            'status': self.status,
            'solver_log': self.solver_log,
            'created_at': self.created_at.isoformat() if self.created_at else ''
        }


# ─── Audit Log Model ──────────────────────────────────────────────────────────

class AuditLog(db.Model):
    """Audit Trail for User Actions and Hospital Changes"""
    __tablename__ = 'audit_logs'

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=True)
    user_name = db.Column(db.String(80), default='system')
    action = db.Column(db.String(50), nullable=False)  # CREATE, UPDATE, DELETE, OPTIMIZE, EMERGENCY
    resource_type = db.Column(db.String(50), nullable=False)  # patient, doctor, appointment, bed, etc.
    resource_id = db.Column(db.Integer, nullable=True)
    details = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime(timezone=True), default=utc_now)

    __table_args__ = (
        db.Index('idx_audit_logs_created_at', 'created_at'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'user_name': self.user_name,
            'action': self.action,
            'resource_type': self.resource_type,
            'resource_id': self.resource_id,
            'details': self.details,
            'created_at': self.created_at.strftime('%Y-%m-%d %H:%M:%S') if self.created_at else ''
        }

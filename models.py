"""
models.py - Database Models for Smart Hospital Resource Optimization System
Defines all SQLAlchemy ORM models for the application.
"""

from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()


class Department(db.Model):
    """Hospital Department model"""
    __tablename__ = 'departments'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False, unique=True)
    capacity = db.Column(db.Integer, default=50)
    description = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    doctors = db.relationship('Doctor', backref='dept', lazy=True)
    rooms = db.relationship('Room', backref='dept', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'capacity': self.capacity,
            'description': self.description,
            'doctor_count': len(self.doctors),
            'room_count': len(self.rooms)
        }


class Doctor(db.Model):
    """Doctor model"""
    __tablename__ = 'doctors'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    specialization = db.Column(db.String(100), nullable=False)
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    max_patients_per_day = db.Column(db.Integer, default=10)
    available_from = db.Column(db.String(10), default='08:00')  # HH:MM
    available_until = db.Column(db.String(10), default='17:00')  # HH:MM
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    appointments = db.relationship('Appointment', backref='doctor', lazy=True)

    def to_dict(self):
        dept = Department.query.get(self.department_id)
        appointments_today = Appointment.query.filter(
            Appointment.doctor_id == self.id,
            Appointment.date == datetime.utcnow().date().isoformat()
        ).count()
        return {
            'id': self.id,
            'name': self.name,
            'specialization': self.specialization,
            'department_id': self.department_id,
            'department_name': dept.name if dept else 'Unknown',
            'max_patients_per_day': self.max_patients_per_day,
            'available_from': self.available_from,
            'available_until': self.available_until,
            'appointments_today': appointments_today
        }


class Patient(db.Model):
    """Patient model"""
    __tablename__ = 'patients'

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    gender = db.Column(db.String(10), nullable=False)
    priority = db.Column(db.String(20), default='normal')  # critical, urgent, normal, low
    required_specialization = db.Column(db.String(100), nullable=False)
    condition_description = db.Column(db.Text, default='')
    preferred_date = db.Column(db.String(20), default='')
    registered_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    appointments = db.relationship('Appointment', backref='patient', lazy=True)

    def priority_score(self):
        """Numeric priority score for optimization (higher = more priority)"""
        scores = {'critical': 4, 'urgent': 3, 'normal': 2, 'low': 1}
        return scores.get(self.priority, 2)

    def to_dict(self):
        latest_appt = Appointment.query.filter_by(patient_id=self.id)\
            .order_by(Appointment.created_at.desc()).first()
        return {
            'id': self.id,
            'name': self.name,
            'age': self.age,
            'gender': self.gender,
            'priority': self.priority,
            'required_specialization': self.required_specialization,
            'condition_description': self.condition_description,
            'preferred_date': self.preferred_date,
            'registered_at': self.registered_at.isoformat() if self.registered_at else '',
            'appointment_status': latest_appt.status if latest_appt else 'unscheduled'
        }


class Room(db.Model):
    """Hospital Room model"""
    __tablename__ = 'rooms'

    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(20), nullable=False, unique=True)
    department_id = db.Column(db.Integer, db.ForeignKey('departments.id'), nullable=False)
    room_type = db.Column(db.String(50), default='consultation')  # consultation, surgery, icu, ward
    capacity = db.Column(db.Integer, default=1)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    appointments = db.relationship('Appointment', backref='room', lazy=True)

    def to_dict(self):
        dept = Department.query.get(self.department_id)
        return {
            'id': self.id,
            'room_number': self.room_number,
            'department_id': self.department_id,
            'department_name': dept.name if dept else 'Unknown',
            'room_type': self.room_type,
            'capacity': self.capacity
        }


class Appointment(db.Model):
    """Appointment/Schedule model"""
    __tablename__ = 'appointments'

    id = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey('patients.id'), nullable=False)
    doctor_id = db.Column(db.Integer, db.ForeignKey('doctors.id'), nullable=False)
    room_id = db.Column(db.Integer, db.ForeignKey('rooms.id'), nullable=False)
    date = db.Column(db.String(20), nullable=False)
    start_time = db.Column(db.String(10), nullable=False)
    end_time = db.Column(db.String(10), nullable=False)
    waiting_time = db.Column(db.Integer, default=0)  # in minutes
    status = db.Column(db.String(20), default='scheduled')  # scheduled, completed, cancelled
    notes = db.Column(db.Text, default='')
    optimization_run_id = db.Column(db.Integer, db.ForeignKey('optimization_runs.id'), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'patient_id': self.patient_id,
            'patient_name': self.patient.name if self.patient else 'Unknown',
            'patient_priority': self.patient.priority if self.patient else 'normal',
            'doctor_id': self.doctor_id,
            'doctor_name': self.doctor.name if self.doctor else 'Unknown',
            'doctor_specialization': self.doctor.specialization if self.doctor else '',
            'room_id': self.room_id,
            'room_number': self.room.room_number if self.room else 'Unknown',
            'date': self.date,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'waiting_time': self.waiting_time,
            'status': self.status,
            'notes': self.notes,
            'created_at': self.created_at.isoformat() if self.created_at else ''
        }


class OptimizationRun(db.Model):
    """Optimization Run History model"""
    __tablename__ = 'optimization_runs'

    id = db.Column(db.Integer, primary_key=True)
    algorithm = db.Column(db.String(50), nullable=False)  # lp, greedy, hybrid
    run_date = db.Column(db.String(20), nullable=False)
    total_patients = db.Column(db.Integer, default=0)
    assigned_patients = db.Column(db.Integer, default=0)
    unassigned_patients = db.Column(db.Integer, default=0)
    avg_wait_time = db.Column(db.Float, default=0.0)
    utilization_rate = db.Column(db.Float, default=0.0)
    status = db.Column(db.String(20), default='success')  # success, failed, partial
    solver_log = db.Column(db.Text, default='')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    appointments = db.relationship('Appointment', backref='optimization_run', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'algorithm': self.algorithm,
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

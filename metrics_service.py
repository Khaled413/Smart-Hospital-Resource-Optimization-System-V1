"""
metrics_service.py - Centralized Aggregate SQL Metrics Service
Computes utilization, wait times, department load, and patient status using efficient
SQL aggregate queries (GROUP BY, AVG, SUM, COUNT) instead of memory-heavy Python loops.
"""

from models import db, Appointment, Doctor, Department, Patient, Room, Bed, Equipment, format_doctor_name
from optimizer import time_to_minutes


class MetricsService:
    """Service providing aggregate metrics for hospital dashboard, analytics, and capacity tracking."""

    @staticmethod
    def get_average_wait_time(target_date: str) -> float:
        """Calculate average patient wait time in minutes for given date using SQL AVG."""
        avg_wait = db.session.query(
            db.func.coalesce(db.func.avg(Appointment.waiting_time), 0.0)
        ).filter(
            Appointment.date == target_date,
            Appointment.status != 'cancelled'
        ).scalar()
        return round(float(avg_wait or 0.0), 1)

    @staticmethod
    def get_wait_time_by_priority(target_date: str | None = None) -> dict[str, float]:
        """Calculate average wait time in minutes grouped by patient priority via aggregate SQL AVG and GROUP BY."""
        query = (
            db.session.query(
                Patient.priority,
                db.func.coalesce(db.func.avg(Appointment.waiting_time), 0.0)
            )
            .join(Patient, Appointment.patient_id == Patient.id)
            .filter(Appointment.status != 'cancelled')
        )
        if target_date:
            query = query.filter(Appointment.date == target_date)
        rows = dict(query.group_by(Patient.priority).all())
        return {p: round(float(rows.get(p, 0.0)), 1) for p in ['critical', 'urgent', 'normal', 'low']}

    @staticmethod
    def get_overall_utilization(target_date: str) -> dict:
        """
        Calculate total hospital capacity utilization percentage for target_date.
        Uses SQL SUM for booked minutes and precomputed doctor shift hours.
        """
        booked_minutes = db.session.query(
            db.func.coalesce(db.func.sum(Appointment.duration_minutes), 0)
        ).filter(
            Appointment.date == target_date,
            Appointment.status.in_(['scheduled', 'in_progress', 'completed'])
        ).scalar() or 0

        doctors = Doctor.query.all()
        total_avail_minutes = sum(
            (time_to_minutes(d.available_until) - time_to_minutes(d.available_from))
            for d in doctors
        )
        util_pct = round((booked_minutes / total_avail_minutes * 100), 1) if total_avail_minutes > 0 else 0.0
        return {
            'utilization': util_pct,
            'booked_minutes': int(booked_minutes),
            'total_available_minutes': total_avail_minutes
        }

    @staticmethod
    def get_doctor_utilization(target_date: str) -> list[dict]:
        """
        Calculate per-doctor utilization via single aggregate SQL query with GROUP BY doctor_id.
        Avoids N+1 query loops.
        """
        # Aggregate booked counts and booked minutes per doctor
        doc_stats = {
            row[0]: (row[1], row[2])
            for row in db.session.query(
                Appointment.doctor_id,
                db.func.count(Appointment.id),
                db.func.coalesce(db.func.sum(Appointment.duration_minutes), 0)
            )
            .filter(
                Appointment.date == target_date,
                Appointment.status.in_(['scheduled', 'in_progress', 'completed'])
            )
            .group_by(Appointment.doctor_id)
            .all()
        }

        doctors = Doctor.query.all()
        util_data = []
        for doc in doctors:
            avail_mins = time_to_minutes(doc.available_until) - time_to_minutes(doc.available_from)
            total_slots = avail_mins // 30
            booked_count, booked_mins = doc_stats.get(doc.id, (0, 0))
            util_pct = round((booked_mins / avail_mins * 100), 1) if avail_mins > 0 else 0.0

            util_data.append({
                'name': doc.formatted_name,
                'doctor': doc.formatted_name,
                'doctor_id': doc.id,
                'specialization': doc.specialization,
                'spec': doc.specialization,
                'booked': booked_count,
                'booked_minutes': int(booked_mins),
                'total_slots': total_slots,
                'utilization': min(util_pct, 100.0)
            })
        return util_data

    @staticmethod
    def get_department_load(target_date: str | None = None) -> dict[str, int]:
        """
        Calculate appointment workload grouped by department using SQL JOIN and GROUP BY.
        Returns a dictionary mapping department name to appointment count.
        """
        query = (
            db.session.query(Department.name, db.func.count(Appointment.id))
            .join(Doctor, Doctor.department_id == Department.id)
            .join(Appointment, Appointment.doctor_id == Doctor.id)
            .filter(Appointment.status != 'cancelled')
        )
        if target_date:
            query = query.filter(Appointment.date == target_date)

        rows = query.group_by(Department.name).all()
        return {dept_name: count for dept_name, count in rows}

    @staticmethod
    def get_patient_status_counts(target_date: str | None = None) -> dict[str, int]:
        """
        Calculate count of assigned vs unassigned patients via SQL COUNT(DISTINCT).
        Avoids loading full patient records and appointment tables into Python memory.
        """
        total_patients = db.session.query(db.func.count(Patient.id)).scalar() or 0

        assigned_query = db.session.query(
            db.func.count(db.func.distinct(Appointment.patient_id))
        ).filter(
            Appointment.status.in_(['scheduled', 'in_progress', 'completed'])
        )
        if target_date:
            assigned_query = assigned_query.filter(Appointment.date == target_date)

        assigned = assigned_query.scalar() or 0
        unassigned = max(0, total_patients - assigned)
        return {'assigned': assigned, 'unassigned': unassigned}

    @classmethod
    def get_dashboard_summary(cls, target_date: str) -> dict:
        """
        Comprehensive dashboard metrics payload powered entirely by SQL aggregate queries.
        """
        total_patients = db.session.query(db.func.count(Patient.id)).scalar() or 0
        total_doctors = db.session.query(db.func.count(Doctor.id)).scalar() or 0
        total_rooms = db.session.query(db.func.count(Room.id)).scalar() or 0
        total_depts = db.session.query(db.func.count(Department.id)).scalar() or 0
        total_beds = db.session.query(db.func.count(Bed.id)).scalar() or 0
        occupied_beds = db.session.query(db.func.count(Bed.id)).filter(Bed.status == 'occupied').scalar() or 0
        total_equipment = db.session.query(db.func.count(Equipment.id)).scalar() or 0
        avail_equipment = db.session.query(db.func.count(Equipment.id)).filter(Equipment.status == 'available').scalar() or 0

        appts_today = db.session.query(db.func.count(Appointment.id)).filter(
            Appointment.date == target_date,
            Appointment.status != 'cancelled'
        ).scalar() or 0

        emergencies_today = db.session.query(db.func.count(Appointment.id)).filter(
            Appointment.date == target_date,
            Appointment.is_emergency == True,
            Appointment.status != 'cancelled'
        ).scalar() or 0

        avg_wait = cls.get_average_wait_time(target_date)
        overall_util = cls.get_overall_utilization(target_date)
        doc_util = cls.get_doctor_utilization(target_date)
        dept_workload = cls.get_department_load()

        priority_dist = dict(
            db.session.query(Patient.priority, db.func.count(Patient.id))
            .group_by(Patient.priority).all()
        )

        return {
            'total_patients': total_patients,
            'total_doctors': total_doctors,
            'total_rooms': total_rooms,
            'total_departments': total_depts,
            'total_beds': total_beds,
            'occupied_beds': occupied_beds,
            'bed_occupancy_rate': round((occupied_beds / total_beds * 100), 1) if total_beds > 0 else 0.0,
            'total_equipment': total_equipment,
            'available_equipment': avail_equipment,
            'appointments_today': appts_today,
            'emergencies_today': emergencies_today,
            'avg_wait_time': avg_wait,
            'utilization_rate': overall_util['utilization'],
            'overall_utilization': overall_util['utilization'],
            'doctor_utilization': doc_util,
            'department_workload': dept_workload,
            'priority_distribution': priority_dist,
            'date': target_date
        }

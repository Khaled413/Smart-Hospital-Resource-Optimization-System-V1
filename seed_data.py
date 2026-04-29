"""
seed_data.py - Sample data seeder for Smart Hospital Resource Optimization System
Inserts demo records: 5 Departments, 8 Doctors, 10 Rooms, 20 Patients.
"""

from models import db, Department, Doctor, Patient, Room
from datetime import datetime, timedelta
import random


def seed_database():
    """Seed database with sample hospital data if tables are empty."""
    if Department.query.count() > 0:
        return  # Already seeded

    print("[SEED] Seeding database with sample data...")

    # ── Departments ──────────────────────────────────────────────────────────
    departments_data = [
        {"name": "Cardiology",      "capacity": 60, "description": "Heart and cardiovascular care"},
        {"name": "Neurology",       "capacity": 40, "description": "Brain and nervous system"},
        {"name": "Orthopedics",     "capacity": 50, "description": "Bones, joints, and muscles"},
        {"name": "Pediatrics",      "capacity": 70, "description": "Child healthcare"},
        {"name": "General Surgery", "capacity": 55, "description": "Surgical procedures"},
    ]
    depts = {}
    for d in departments_data:
        dept = Department(**d)
        db.session.add(dept)
        db.session.flush()
        depts[d["name"]] = dept

    # ── Doctors ───────────────────────────────────────────────────────────────
    doctors_data = [
        {"name": "Dr. Sarah Mitchell",  "specialization": "Cardiology",      "dept": "Cardiology",      "max": 12, "from": "08:00", "until": "16:00"},
        {"name": "Dr. James Thornton",  "specialization": "Cardiology",      "dept": "Cardiology",      "max": 10, "from": "09:00", "until": "17:00"},
        {"name": "Dr. Emily Chen",      "specialization": "Neurology",       "dept": "Neurology",       "max": 8,  "from": "08:30", "until": "16:30"},
        {"name": "Dr. Robert Hayes",    "specialization": "Neurology",       "dept": "Neurology",       "max": 9,  "from": "10:00", "until": "18:00"},
        {"name": "Dr. Linda Park",      "specialization": "Orthopedics",     "dept": "Orthopedics",     "max": 11, "from": "08:00", "until": "16:00"},
        {"name": "Dr. Ahmed Al-Rashid","specialization": "Pediatrics",      "dept": "Pediatrics",      "max": 15, "from": "08:00", "until": "17:00"},
        {"name": "Dr. Maria Santos",    "specialization": "General Surgery", "dept": "General Surgery", "max": 6,  "from": "07:00", "until": "15:00"},
        {"name": "Dr. Kevin O'Brien",   "specialization": "General Surgery", "dept": "General Surgery", "max": 7,  "from": "11:00", "until": "19:00"},
    ]
    for doc in doctors_data:
        doctor = Doctor(
            name=doc["name"],
            specialization=doc["specialization"],
            department_id=depts[doc["dept"]].id,
            max_patients_per_day=doc["max"],
            available_from=doc["from"],
            available_until=doc["until"]
        )
        db.session.add(doctor)

    # ── Rooms ─────────────────────────────────────────────────────────────────
    rooms_data = [
        {"number": "C-101", "dept": "Cardiology",      "type": "consultation", "capacity": 1},
        {"number": "C-102", "dept": "Cardiology",      "type": "consultation", "capacity": 1},
        {"number": "N-201", "dept": "Neurology",       "type": "consultation", "capacity": 1},
        {"number": "N-202", "dept": "Neurology",       "type": "icu",          "capacity": 2},
        {"number": "O-301", "dept": "Orthopedics",     "type": "consultation", "capacity": 1},
        {"number": "O-302", "dept": "Orthopedics",     "type": "surgery",      "capacity": 1},
        {"number": "P-401", "dept": "Pediatrics",      "type": "consultation", "capacity": 2},
        {"number": "P-402", "dept": "Pediatrics",      "type": "ward",         "capacity": 4},
        {"number": "S-501", "dept": "General Surgery", "type": "surgery",      "capacity": 1},
        {"number": "S-502", "dept": "General Surgery", "type": "consultation", "capacity": 1},
    ]
    for r in rooms_data:
        room = Room(
            room_number=r["number"],
            department_id=depts[r["dept"]].id,
            room_type=r["type"],
            capacity=r["capacity"]
        )
        db.session.add(room)

    # ── Patients ──────────────────────────────────────────────────────────────
    today = datetime.utcnow().date()
    specializations = ["Cardiology", "Neurology", "Orthopedics", "Pediatrics", "General Surgery"]

    patients_data = [
        {"name": "Alice Johnson",    "age": 45, "gender": "Female", "priority": "critical", "spec": "Cardiology",      "condition": "Severe chest pain and irregular heartbeat", "pref": str(today)},
        {"name": "Bob Martinez",     "age": 62, "gender": "Male",   "priority": "urgent",   "spec": "Neurology",       "condition": "Recurring severe headaches with vision loss","pref": str(today)},
        {"name": "Carol White",      "age": 38, "gender": "Female", "priority": "normal",   "spec": "Orthopedics",     "condition": "Knee pain after sports injury",              "pref": str(today)},
        {"name": "David Brown",      "age": 7,  "gender": "Male",   "priority": "urgent",   "spec": "Pediatrics",      "condition": "High fever and respiratory distress",        "pref": str(today)},
        {"name": "Emma Davis",       "age": 55, "gender": "Female", "priority": "critical", "spec": "General Surgery", "condition": "Acute appendicitis requiring surgery",       "pref": str(today)},
        {"name": "Frank Wilson",     "age": 70, "gender": "Male",   "priority": "normal",   "spec": "Cardiology",      "condition": "Routine heart checkup",                      "pref": str(today)},
        {"name": "Grace Lee",        "age": 29, "gender": "Female", "priority": "low",      "spec": "Neurology",       "condition": "Mild migraines, non-disabling",              "pref": str(today)},
        {"name": "Henry Clark",      "age": 48, "gender": "Male",   "priority": "urgent",   "spec": "Orthopedics",     "condition": "Fracture in right arm",                      "pref": str(today)},
        {"name": "Iris Taylor",      "age": 5,  "gender": "Female", "priority": "critical", "spec": "Pediatrics",      "condition": "Severe allergic reaction - anaphylaxis",     "pref": str(today)},
        {"name": "James Anderson",   "age": 33, "gender": "Male",   "priority": "normal",   "spec": "General Surgery", "condition": "Hernia repair consultation",                 "pref": str(today)},
        {"name": "Karen Thompson",   "age": 52, "gender": "Female", "priority": "urgent",   "spec": "Cardiology",      "condition": "Elevated blood pressure with chest tightness","pref": str(today)},
        {"name": "Liam Robinson",    "age": 11, "gender": "Male",   "priority": "normal",   "spec": "Pediatrics",      "condition": "Routine pediatric checkup",                  "pref": str(today)},
        {"name": "Mia Harris",       "age": 65, "gender": "Female", "priority": "low",      "spec": "Orthopedics",     "condition": "Mild arthritis in hip joint",                "pref": str(today)},
        {"name": "Noah Jackson",     "age": 41, "gender": "Male",   "priority": "critical", "spec": "Neurology",       "condition": "Suspected stroke - urgent MRI needed",       "pref": str(today)},
        {"name": "Olivia Martin",    "age": 27, "gender": "Female", "priority": "normal",   "spec": "General Surgery", "condition": "Gallstone removal consultation",             "pref": str(today)},
        {"name": "Peter Garcia",     "age": 58, "gender": "Male",   "priority": "urgent",   "spec": "Cardiology",      "condition": "Post-bypass follow-up with complications",   "pref": str(today)},
        {"name": "Quinn Roberts",    "age": 19, "gender": "Female", "priority": "low",      "spec": "General Surgery", "condition": "Wisdom tooth extraction",                   "pref": str(today)},
        {"name": "Ryan Lewis",       "age": 44, "gender": "Male",   "priority": "normal",   "spec": "Neurology",       "condition": "Numbness in left arm, needs evaluation",     "pref": str(today)},
        {"name": "Sophia Walker",    "age": 3,  "gender": "Female", "priority": "urgent",   "spec": "Pediatrics",      "condition": "Persistent vomiting and dehydration",        "pref": str(today)},
        {"name": "Tyler Young",      "age": 36, "gender": "Male",   "priority": "normal",   "spec": "Orthopedics",     "condition": "Lower back pain from disc herniation",       "pref": str(today)},
    ]

    for p in patients_data:
        patient = Patient(
            name=p["name"],
            age=p["age"],
            gender=p["gender"],
            priority=p["priority"],
            required_specialization=p["spec"],
            condition_description=p["condition"],
            preferred_date=p["pref"],
            registered_at=datetime.utcnow()
        )
        db.session.add(patient)

    db.session.commit()
    print("[SEED] OK Database seeded successfully!")
    print(f"[SEED] Created: {len(departments_data)} departments, {len(doctors_data)} doctors, "
          f"{len(rooms_data)} rooms, {len(patients_data)} patients")

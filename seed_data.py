"""
seed_data.py - Enhanced Sample Data Seeder for Smart Hospital Resource Optimization System
Seeds Users (RBAC), Departments, Doctors, Rooms, Beds, Equipment, and Patients with clinical vitals.
"""

from models import db, Department, Doctor, Patient, Room, Bed, Equipment, User, Appointment
from optimizer import predict_no_show_risk
from datetime import datetime, date


def seed_database():
    """Seed comprehensive dataset if tables are empty."""
    # Check if database needs seeding
    if Department.query.count() > 0:
        return

    print("[SEED] Starting comprehensive database seeding...")

    # ── 1. Departments ────────────────────────────────────────────────────────
    departments_data = [
        {"name": "Cardiology",      "capacity": 60, "description": "Heart, vascular diagnostics, and critical cardiac care"},
        {"name": "Neurology",       "capacity": 45, "description": "Brain, spinal cord, and neuro-intensive care"},
        {"name": "Orthopedics",     "capacity": 50, "description": "Bones, joints, sports medicine, and trauma reconstruction"},
        {"name": "Pediatrics",      "capacity": 70, "description": "Neonatal, infant, and child healthcare services"},
        {"name": "General Surgery", "capacity": 55, "description": "Laparoscopic, trauma, and elective surgical suites"},
    ]
    depts = {}
    for d in departments_data:
        dept = Department(**d)
        db.session.add(dept)
        db.session.flush()
        depts[d["name"]] = dept

    # ── 2. Doctors ────────────────────────────────────────────────────────────
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
    docs = []
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
        db.session.flush()
        docs.append(doctor)

    # ── 3. Users (RBAC) ───────────────────────────────────────────────────────
    import os

    admin_initial_password = os.environ.get('ADMIN_INITIAL_PASSWORD', 'Admin#2025!')
    admin_must_change = False

    users_data = [
        {
            "username": "admin",
            "email": "admin@hospital.org",
            "role": "admin",
            "name": "Dr. Chief Administrator",
            "pass": admin_initial_password,
            "must_change": admin_must_change
        },
        {
            "username": "manager",
            "email": "manager@hospital.org",
            "role": "manager",
            "name": "Operations Director",
            "pass": os.environ.get('MANAGER_INITIAL_PASSWORD', 'Manager#2025!'),
            "must_change": False
        },
        {
            "username": "receptionist",
            "email": "frontdesk@hospital.org",
            "role": "receptionist",
            "name": "Front Desk Reception",
            "pass": os.environ.get('RECEPTIONIST_INITIAL_PASSWORD', 'Reception#2025!'),
            "must_change": False
        },
        {
            "username": "dr_sarah",
            "email": "s.mitchell@hospital.org",
            "role": "doctor",
            "name": "Dr. Sarah Mitchell",
            "pass": os.environ.get('DOCTOR_INITIAL_PASSWORD', 'Doctor#2025!'),
            "doc_id": docs[0].id,
            "must_change": False
        },
    ]
    for u in users_data:
        user = User(
            username=u["username"],
            email=u["email"],
            role=u["role"],
            full_name=u["name"],
            doctor_id=u.get("doc_id"),
            must_change_password=u.get("must_change", False)
        )
        user.set_password(u["pass"])
        db.session.add(user)

    # ── 4. Rooms ──────────────────────────────────────────────────────────────
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
    room_objs = {}
    for r in rooms_data:
        room = Room(
            room_number=r["number"],
            department_id=depts[r["dept"]].id,
            room_type=r["type"],
            capacity=r["capacity"]
        )
        db.session.add(room)
        db.session.flush()
        room_objs[r["number"]] = room

    # ── 5. Equipment ──────────────────────────────────────────────────────────
    equipment_data = [
        {"name": "Hamilton-C6 ICU Ventilator",    "type": "ventilator",    "dept": "Neurology",       "room": "N-202", "status": "available"},
        {"name": "Maquet Servo-u Ventilator",     "type": "ventilator",    "dept": "Pediatrics",      "room": "P-402", "status": "available"},
        {"name": "Siemens Magnetom 3T MRI",      "type": "mri",           "dept": "Neurology",       "room": "N-201", "status": "available"},
        {"name": "GE Revolution 256-Slice CT",   "type": "ct_scanner",    "dept": "General Surgery", "room": "S-501", "status": "available"},
        {"name": "Philips PageWriter TC70 ECG",   "type": "ecg",           "dept": "Cardiology",      "room": "C-101", "status": "available"},
        {"name": "Zoll R Series Defibrillator",   "type": "ecg",           "dept": "Pediatrics",      "room": "P-401", "status": "available"},
        {"name": "Stryker Laparoscopy Tower 4K",  "type": "surgical_kit",  "dept": "General Surgery", "room": "S-501", "status": "in_use"},
        {"name": "Ziehm Vision RFD 3D C-Arm",     "type": "ultrasound",    "dept": "Orthopedics",     "room": "O-302", "status": "available"},
    ]
    for eq in equipment_data:
        equipment = Equipment(
            name=eq["name"],
            equipment_type=eq["type"],
            department_id=depts[eq["dept"]].id,
            room_id=room_objs[eq["room"]].id if eq.get("room") else None,
            status=eq["status"]
        )
        db.session.add(equipment)

    # ── 6. Inpatient Beds ─────────────────────────────────────────────────────
    beds_data = [
        {"number": "BED-C101-A", "room": "C-101", "dept": "Cardiology",      "status": "vacant"},
        {"number": "BED-N202-01", "room": "N-202", "dept": "Neurology",       "status": "occupied", "notes": "Monitored neuro-ICU patient"},
        {"number": "BED-N202-02", "room": "N-202", "dept": "Neurology",       "status": "cleaning", "notes": "Under UV-C sterilization"},
        {"number": "BED-O301-A",  "room": "O-301", "dept": "Orthopedics",     "status": "vacant"},
        {"number": "BED-P402-01", "room": "P-402", "dept": "Pediatrics",      "status": "occupied", "notes": "Pediatric observation bed"},
        {"number": "BED-P402-02", "room": "P-402", "dept": "Pediatrics",      "status": "vacant"},
        {"number": "BED-P402-03", "room": "P-402", "dept": "Pediatrics",      "status": "reserved", "notes": "Reserved for elective surgery recovery"},
        {"number": "BED-P402-04", "room": "P-402", "dept": "Pediatrics",      "status": "vacant"},
        {"number": "BED-S501-A",  "room": "S-501", "dept": "General Surgery", "status": "vacant"},
    ]
    for b in beds_data:
        bed = Bed(
            bed_number=b["number"],
            room_id=room_objs[b["room"]].id,
            department_id=depts[b["dept"]].id,
            status=b["status"],
            notes=b.get("notes", "")
        )
        db.session.add(bed)

    # ── 7. Patients with Clinical Vitals & Triage ─────────────────────────────
    today = date.today().isoformat()
    patients_data = [
        {"name": "Alice Johnson",    "age": 45, "gender": "Female", "priority": "critical", "spec": "Cardiology",      "condition": "Severe acute chest pain radiating to left arm, ST elevation suspected", "triage": 1, "bp": "165/105", "hr": 112, "spo2": 93, "temp": 37.1},
        {"name": "Bob Martinez",     "age": 62, "gender": "Male",   "priority": "urgent",   "spec": "Neurology",       "condition": "Acute recurring migraine with hemiparesis and visual blur",              "triage": 2, "bp": "145/92",  "hr": 88,  "spo2": 97, "temp": 36.9},
        {"name": "Carol White",      "age": 38, "gender": "Female", "priority": "normal",   "spec": "Orthopedics",     "condition": "Right knee anterior cruciate ligament strain after fall",                 "triage": 4, "bp": "118/76",  "hr": 72,  "spo2": 99, "temp": 36.8},
        {"name": "David Brown",      "age": 7,  "gender": "Male",   "priority": "urgent",   "spec": "Pediatrics",      "condition": "High continuous fever (39.5C) with wheezing and respiratory retractions","triage": 2, "bp": "100/65",  "hr": 128, "spo2": 92, "temp": 39.5},
        {"name": "Emma Davis",       "age": 55, "gender": "Female", "priority": "critical", "spec": "General Surgery", "condition": "Acute McBurney point tenderness, suspected perforated appendicitis",      "triage": 1, "bp": "138/88",  "hr": 105, "spo2": 96, "temp": 38.8},
        {"name": "Frank Wilson",     "age": 70, "gender": "Male",   "priority": "normal",   "spec": "Cardiology",      "condition": "Routine annual hypertensive and pacemaker checkup",                      "triage": 4, "bp": "130/82",  "hr": 68,  "spo2": 98, "temp": 36.7},
        {"name": "Grace Lee",        "age": 29, "gender": "Female", "priority": "low",      "spec": "Neurology",       "condition": "Occasional mild tension headaches over past 3 months",                    "triage": 5, "bp": "115/74",  "hr": 70,  "spo2": 99, "temp": 36.6},
        {"name": "Henry Clark",      "age": 48, "gender": "Male",   "priority": "urgent",   "spec": "Orthopedics",     "condition": "Closed displaced radius fracture with neurovascular intact",              "triage": 3, "bp": "135/85",  "hr": 84,  "spo2": 98, "temp": 37.0},
        {"name": "Iris Taylor",      "age": 5,  "gender": "Female", "priority": "critical", "spec": "Pediatrics",      "condition": "Peanut allergen exposure with facial angioedema and stridor",             "triage": 1, "bp": "90/58",   "hr": 135, "spo2": 91, "temp": 37.2},
        {"name": "James Anderson",   "age": 33, "gender": "Male",   "priority": "normal",   "spec": "General Surgery", "condition": "Reducible right inguinal hernia consultation",                           "triage": 4, "bp": "122/78",  "hr": 74,  "spo2": 99, "temp": 36.7},
        {"name": "Karen Thompson",   "age": 52, "gender": "Female", "priority": "urgent",   "spec": "Cardiology",      "condition": "Hypertensive crisis (185/110) with occipital pressure",                  "triage": 2, "bp": "185/110", "hr": 96,  "spo2": 96, "temp": 37.0},
        {"name": "Liam Robinson",    "age": 11, "gender": "Male",   "priority": "normal",   "spec": "Pediatrics",      "condition": "Routine school physical and booster immunization",                        "triage": 5, "bp": "105/68",  "hr": 78,  "spo2": 99, "temp": 36.8},
        {"name": "Mia Harris",       "age": 65, "gender": "Female", "priority": "low",      "spec": "Orthopedics",     "condition": "Bilateral knee osteoarthritis conservative management review",            "triage": 5, "bp": "128/80",  "hr": 66,  "spo2": 98, "temp": 36.6},
        {"name": "Noah Jackson",     "age": 41, "gender": "Male",   "priority": "critical", "spec": "Neurology",       "condition": "Sudden onset facial droop and right arm pronator drift (<2 hrs)",        "triage": 1, "bp": "160/95",  "hr": 102, "spo2": 95, "temp": 37.3},
        {"name": "Olivia Martin",    "age": 27, "gender": "Female", "priority": "normal",   "spec": "General Surgery", "condition": "Symptomatic cholelithiasis for elective laparoscopic cholecystectomy",   "triage": 4, "bp": "116/74",  "hr": 76,  "spo2": 99, "temp": 36.9},
        {"name": "Peter Garcia",     "age": 58, "gender": "Male",   "priority": "urgent",   "spec": "Cardiology",      "condition": "Post-coronary stenting 30-day review with peripheral edema",             "triage": 3, "bp": "142/90",  "hr": 82,  "spo2": 96, "temp": 36.8},
        {"name": "Quinn Roberts",    "age": 19, "gender": "Female", "priority": "low",      "spec": "General Surgery", "condition": "Sebaceous cyst removal on back, non-infected",                           "triage": 5, "bp": "112/70",  "hr": 72,  "spo2": 100,"temp": 36.5},
        {"name": "Ryan Lewis",       "age": 44, "gender": "Male",   "priority": "normal",   "spec": "Neurology",       "condition": "Cervical radiculopathy with numbness in C6 dermatome",                   "triage": 4, "bp": "124/80",  "hr": 75,  "spo2": 98, "temp": 36.7},
        {"name": "Sophia Walker",    "age": 3,  "gender": "Female", "priority": "urgent",   "spec": "Pediatrics",      "condition": "Acute gastroenteritis with moderate dehydration and lethargy",           "triage": 2, "bp": "88/54",   "hr": 125, "spo2": 95, "temp": 38.4},
        {"name": "Tyler Young",      "age": 36, "gender": "Male",   "priority": "normal",   "spec": "Orthopedics",     "condition": "Chronic lumbar disc L5-S1 herniation follow-up",                         "triage": 4, "bp": "120/78",  "hr": 70,  "spo2": 99, "temp": 36.6},
    ]

    for p in patients_data:
        patient = Patient(
            name=p["name"],
            age=p["age"],
            gender=p["gender"],
            priority=p["priority"],
            required_specialization=p["spec"],
            condition_description=p["condition"],
            preferred_date=today,
            triage_level=p["triage"],
            blood_pressure=p["bp"],
            heart_rate=p["hr"],
            spo2=p["spo2"],
            temperature=p["temp"],
            registered_at=datetime.utcnow()
        )
        patient.no_show_risk = predict_no_show_risk(patient)
        db.session.add(patient)

    db.session.commit()
    print("[SEED] Comprehensive database seeded successfully!")
    print(f"[SEED] Created: {len(departments_data)} departments, {len(doctors_data)} doctors, "
          f"{len(users_data)} users, {len(rooms_data)} rooms, {len(beds_data)} beds, "
          f"{len(equipment_data)} equipment, {len(patients_data)} patients")

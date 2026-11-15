"""
seed_data.py - Enhanced Sample Data Seeder for Smart Hospital Resource Optimization System
Seeds Roles & Permissions (Dynamic RBAC), Users, Departments, Doctors, Rooms, Beds, Equipment, and Patients with clinical vitals.
"""

from models import db, Department, Doctor, Patient, Room, Bed, Equipment, User, Appointment, OptimizationRun, Permission, Role, UserPermissionOverride
from permissions import PERMISSION_CATALOG, DEFAULT_ROLE_PERMISSIONS
from optimizer import predict_no_show_risk
from datetime import datetime, date, timedelta
import os
import secrets


def seed_permissions_and_roles():
    """
    Idempotent seeding of authoritative permissions and system roles.
    - Synchronizes Permission table with PERMISSION_CATALOG.
    - Ensures core system roles exist (admin, manager, doctor, receptionist, demo_viewer).
    - Preserves custom permissions of unlocked roles.
    - Always enforces full permissions on locked system roles (admin).
    - Backfills role_id for existing users.
    """
    # 1. Sync Permissions Catalog
    for p_def in PERMISSION_CATALOG:
        perm = Permission.query.filter_by(key=p_def.key).first()
        if not perm:
            perm = Permission(
                key=p_def.key,
                group=p_def.group,
                label_en=p_def.label_en,
                label_ar=p_def.label_ar,
                description=p_def.description,
                is_sensitive=p_def.is_sensitive
            )
            db.session.add(perm)
        else:
            perm.group = p_def.group
            perm.label_en = p_def.label_en
            perm.label_ar = p_def.label_ar
            perm.description = p_def.description
            perm.is_sensitive = p_def.is_sensitive
    db.session.flush()

    all_perms = {p.key: p for p in Permission.query.all()}

    # 2. Sync System Roles
    system_roles_meta = {
        'admin': {
            'description': 'Chief Administrator with full access to all system modules and security controls',
            'is_system': True,
            'is_locked': True
        },
        'manager': {
            'description': 'Operations Manager overseeing departmental resources, schedules, and analytics',
            'is_system': True,
            'is_locked': False
        },
        'doctor': {
            'description': 'Attending Physician managing clinical consultations, patients, and diagnoses',
            'is_system': True,
            'is_locked': False
        },
        'receptionist': {
            'description': 'Front Desk Receptionist managing patient intake, appointments, and triage',
            'is_system': True,
            'is_locked': False
        },
        'demo_viewer': {
            'description': 'Public Demo Guest with read-only views and masked clinical details',
            'is_system': True,
            'is_locked': False
        }
    }

    roles_by_name = {}
    for role_name, meta in system_roles_meta.items():
        role = Role.query.filter_by(name=role_name).first()
        default_keys = DEFAULT_ROLE_PERMISSIONS.get(role_name, [])
        target_perms = [all_perms[k] for k in default_keys if k in all_perms]

        if not role:
            role = Role(
                name=role_name,
                description=meta['description'],
                is_system=meta['is_system'],
                is_locked=meta['is_locked'],
                version=1
            )
            role.permissions = target_perms
            db.session.add(role)
        else:
            role.is_system = meta['is_system']
            if role.is_locked:
                role.permissions = target_perms
        db.session.flush()
        roles_by_name[role_name] = role

    # 3. Backfill User role_id & ensure core user accounts exist
    admin_pass = os.environ.get('ADMIN_INITIAL_PASSWORD') or 'Admin#2025!'
    manager_pass = os.environ.get('MANAGER_INITIAL_PASSWORD') or 'Manager#2025!'
    doc_pass = os.environ.get('DOCTOR_INITIAL_PASSWORD') or 'Doctor#2025!'
    rec_pass = os.environ.get('RECEPTIONIST_INITIAL_PASSWORD') or 'Reception#2025!'
    demo_pass = os.environ.get('DEMO_PASSWORD') or 'DemoViewer#2025!'

    core_defaults = {
        'admin': {'email': 'admin@hospital.org', 'role': 'admin', 'name': 'Chief Administrator', 'pass': admin_pass},
        'manager': {'email': 'manager@hospital.org', 'role': 'manager', 'name': 'Operations Director', 'pass': manager_pass},
        'dr_sarah': {'email': 's.mitchell@hospital.org', 'role': 'doctor', 'name': 'Dr. Sarah Mitchell', 'pass': doc_pass},
        'receptionist': {'email': 'frontdesk@hospital.org', 'role': 'receptionist', 'name': 'Front Desk Reception', 'pass': rec_pass},
        'demo_viewer': {'email': 'demo@hospital.org', 'role': 'demo_viewer', 'name': 'Public Demo Guest (Read-Only)', 'pass': demo_pass}
    }

    for username, udata in core_defaults.items():
        user = User.query.filter_by(username=username).first()
        r_obj = roles_by_name.get(udata['role'])
        if not user:
            user = User(
                username=username,
                email=udata['email'],
                role=udata['role'],
                role_id=r_obj.id if r_obj else None,
                full_name=udata['name'],
                is_active=True,
                failed_login_attempts=0,
                locked_until=None
            )
            user.set_password(udata['pass'])
            db.session.add(user)
        else:
            if not user.role_id and r_obj:
                user.role_id = r_obj.id
            user.is_active = True
            user.must_change_password = False
            # Unlock account if previously locked out
            user.failed_login_attempts = 0
            user.locked_until = None
            # If default user password doesn't match configured password, synchronize it
            if not user.check_password(udata['pass']):
                user.set_password(udata['pass'])

    for user in User.query.all():
        if not user.role_id or not user.assigned_role:
            role_key = (user.role or 'receptionist').strip().lower()
            if role_key in roles_by_name:
                user.role_id = roles_by_name[role_key].id
            elif 'receptionist' in roles_by_name:
                user.role_id = roles_by_name['receptionist'].id

    db.session.commit()
    return roles_by_name


def seed_base_data(roles_by_name):
    """Seed base hospital entities (departments, doctors, users, rooms, beds, equipment, patients)."""
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
    import secrets

    # ── 3. Link Doctor Account ────────────────────────────────────────────────
    sarah_user = User.query.filter_by(username='dr_sarah').first()
    if sarah_user and docs:
        sarah_user.doctor_id = docs[0].id
        db.session.flush()

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
          f"{len(rooms_data)} rooms, {len(beds_data)} beds, "
          f"{len(equipment_data)} equipment, {len(patients_data)} patients")


def seed_appointments_and_runs():
    """Seed realistic clinical appointments and initial optimization run."""
    if Appointment.query.count() > 0:
        return

    print("[SEED] Seeding realistic hospital appointments and telemetry...")
    
    # Resolve current date in configured timezone
    try:
        from config import Config
        tz_name = getattr(Config, 'APP_TIMEZONE', 'Africa/Cairo')
    except Exception:
        tz_name = 'Africa/Cairo'
    try:
        import pytz
        tz = pytz.timezone(tz_name)
        now_dt = datetime.now(tz)
    except Exception:
        now_dt = datetime.now()

    today_str = now_dt.strftime('%Y-%m-%d')
    yesterday_str = (now_dt - timedelta(days=1)).strftime('%Y-%m-%d')
    tomorrow_str = (now_dt + timedelta(days=1)).strftime('%Y-%m-%d')

    # Query existing entities
    doctors_map = {d.name: d for d in Doctor.query.all()}
    rooms_map = {r.room_number: r for r in Room.query.all()}
    patients_map = {p.name: p for p in Patient.query.all()}

    if not doctors_map or not rooms_map or not patients_map:
        return

    # 1. Create Initial Optimization Run
    opt_run = OptimizationRun(
        algorithm='hybrid',
        algorithm_used='hybrid',
        fallback_reason='',
        run_date=today_str,
        total_patients=20,
        assigned_patients=20,
        unassigned_patients=0,
        avg_wait_time=24.5,
        utilization_rate=68.4,
        status='success',
        solver_log=(
            "[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...\n"
            "[HYBRID] High-priority queue: 10 patients\n"
            "[HYBRID] Standard queue: 10 patients\n"
            "[LP] Formulating MIP model with 980 candidate decision variables.\n"
            "[LP] Executing CBC solver (limit 25s)...\n"
            "[LP] Solver ended with status: Optimal (code=1)\n"
            "[LP] 10/10 High-priority patients scheduled.\n"
            "[GREEDY] Scheduling 10 standard patients with dynamic procedure durations.\n"
            "[GREEDY] Finished. Assigned: 10, Unassigned: 0\n"
            "[HYBRID] Final Result: Assigned=20, Unassigned=0, Room Conflicts=0"
        ),
        created_at=datetime.utcnow()
    )
    db.session.add(opt_run)
    db.session.flush()

    # 2. Appointment definitions for TODAY
    appointments_today = [
        # Cardiology (Dr. Sarah Mitchell, Dr. James Thornton)
        ("Alice Johnson", "Dr. Sarah Mitchell", "C-101", "08:00", "08:40", 40, 10, 0, "completed", "Severe acute chest pain", "ECG performed; normal sinus rhythm restored with sublingual nitrates. Admitted to telemetry.", "Aspirin 81mg PO daily, Atorvastatin 40mg PO at bedtime"),
        ("Frank Wilson", "Dr. Sarah Mitchell", "C-101", "08:50", "09:20", 30, 10, 20, "completed", "Routine pacemaker check", "Pacemaker battery life 85%, leads intact. Medication dosage maintained.", "Lisinopril 10mg PO daily"),
        ("Karen Thompson", "Dr. Sarah Mitchell", "C-101", "09:30", "10:10", 40, 10, 15, "in_progress", "Hypertensive crisis evaluation", "IV Labetalol started, continuous BP monitoring at bedside.", "Labetalol 20mg IV bolus, monitor BP q15m"),
        ("Peter Garcia", "Dr. James Thornton", "C-102", "09:15", "09:45", 30, 10, 0, "completed", "Post-coronary stenting 30d review", "Femoral puncture site healed cleanly. Dual antiplatelet therapy confirmed.", "Clopidogrel 75mg PO daily, Aspirin 81mg PO daily"),

        # Neurology (Dr. Emily Chen, Dr. Robert Hayes)
        ("Noah Jackson", "Dr. Emily Chen", "N-201", "08:30", "09:25", 55, 10, 0, "completed", "Sudden right arm weakness", "Immediate non-contrast CT brain negative for hemorrhage. Thrombolysis protocol initiated.", "Alteplase IV per neuro protocol, ICU admission"),
        ("Ryan Lewis", "Dr. Emily Chen", "N-201", "09:45", "10:30", 45, 10, 15, "in_progress", "Cervical radiculopathy consultation", "C6-C7 disk protrusion on MRI; referred for targeted physical rehabilitation.", "Gabapentin 300mg PO TID, physical therapy referral"),
        ("Bob Martinez", "Dr. Robert Hayes", "N-202", "10:15", "11:10", 55, 10, 25, "scheduled", "Acute migraine with hemiparesis", "Triptan administered, prophylactic topiramate titration started.", "Sumatriptan 50mg PO PRN, Topiramate 25mg PO QHS"),
        ("Grace Lee", "Dr. Robert Hayes", "N-202", "11:20", "12:05", 45, 10, 10, "scheduled", "Mild tension headaches", "Sleep hygiene and stress management protocol provided.", "Acetaminophen 500mg PO PRN"),

        # Orthopedics (Dr. Linda Park)
        ("Henry Clark", "Dr. Linda Park", "O-302", "08:00", "08:30", 30, 10, 0, "completed", "Closed displaced radius fracture", "Closed reduction under Bier block successful, fiberglass splint applied.", "Ibuprofen 600mg PO TID PRN pain, sling immobilizer"),
        ("Carol White", "Dr. Linda Park", "O-301", "08:40", "09:10", 30, 10, 15, "completed", "Right knee ACL strain", "Lachman test grade 1. Conservative management with brace and NSAIDs.", "Naproxen 500mg PO BID with meals"),
        ("Tyler Young", "Dr. Linda Park", "O-302", "09:20", "09:50", 30, 10, 20, "scheduled", "Chronic lumbar disc herniation", "Scheduled for elective fluoroscopic epidural steroid injection.", "Cyclobenzaprine 5mg PO QHS"),
        ("Mia Harris", "Dr. Linda Park", "O-301", "10:00", "10:30", 30, 10, 10, "scheduled", "Bilateral knee osteoarthritis", "Intra-articular hyaluronic acid injection administered.", "Topical Diclofenac gel 1% TID"),

        # Pediatrics (Dr. Ahmed Al-Rashid)
        ("Iris Taylor", "Dr. Ahmed Al-Rashid", "P-402", "08:00", "08:30", 30, 10, 0, "completed", "Peanut allergen exposure with stridor", "IM Epinephrine 0.15mg given; oxygen via cannula; stridor resolved.", "Diphenhydramine 12.5mg PO q6h PRN, Prednisolone 15mg PO daily x 3d"),
        ("David Brown", "Dr. Ahmed Al-Rashid", "P-401", "08:40", "09:10", 30, 10, 10, "completed", "High fever with wheezing", "Nebulized salbutamol and oral dexamethasone administered. Afebrile.", "Albuterol inhaler 2 puffs q4h PRN, Amoxicillin 250mg/5ml TID"),
        ("Sophia Walker", "Dr. Ahmed Al-Rashid", "P-402", "09:20", "09:50", 30, 10, 15, "in_progress", "Acute gastroenteritis with dehydration", "Oral rehydration therapy tolerated, electrolyte panel normal.", "Oral rehydration salts 500ml/day, Ondansetron 2mg ODT PRN"),
        ("Liam Robinson", "Dr. Ahmed Al-Rashid", "P-401", "10:00", "10:20", 20, 10, 5, "scheduled", "Routine school physical & booster", "DTaP-IPV booster given, development on 50th percentile.", "Multivitamin chewable daily"),

        # General Surgery (Dr. Maria Santos, Dr. Kevin O'Brien)
        ("Emma Davis", "Dr. Maria Santos", "S-501", "07:00", "08:10", 70, 10, 0, "completed", "Acute appendicitis with peritonitis", "Laparoscopic appendectomy performed. Suppurative appendix removed, no perforation.", "Cefazolin 1g IV q8h, Acetaminophen 1000mg IV q6h"),
        ("Olivia Martin", "Dr. Maria Santos", "S-502", "08:20", "09:20", 60, 10, 20, "scheduled", "Symptomatic cholelithiasis", "Pre-operative evaluation completed, booked for elective laparoscopic cholecystectomy.", "Hyoscine butylbromide 10mg PO PRN spasms"),
        ("James Anderson", "Dr. Kevin O'Brien", "S-501", "11:00", "12:00", 60, 10, 0, "scheduled", "Right inguinal hernia", "Direct inguinal hernia identified, mesh repair discussed.", "Stool softener daily, avoid heavy lifting"),
        ("Quinn Roberts", "Dr. Kevin O'Brien", "S-502", "12:15", "13:15", 60, 10, 15, "scheduled", "Sebaceous cyst excision", "Local anesthesia minor procedure booked.", "Chlorhexidine skin wash BID")
    ]

    for spec in appointments_today:
        p_name, d_name, r_num, s_time, e_time, dur, buf, wait, status, notes, clin_notes, rx = spec
        p = patients_map.get(p_name)
        d = doctors_map.get(d_name)
        r = rooms_map.get(r_num)
        if p and d and r:
            appt = Appointment(
                patient_id=p.id,
                doctor_id=d.id,
                room_id=r.id,
                date=today_str,
                start_time=s_time,
                end_time=e_time,
                duration_minutes=dur,
                buffer_minutes=buf,
                waiting_time=wait,
                status=status,
                is_emergency=(p.priority == 'critical'),
                notes=notes,
                clinical_notes=clin_notes,
                prescription=rx,
                optimization_run_id=opt_run.id,
                created_at=datetime.utcnow()
            )
            db.session.add(appt)

    # 3. Add appointments for yesterday (for realistic analytics historical trends)
    yesterday_specs = [
        ("Alice Johnson", "Dr. Sarah Mitchell", "C-101", "08:00", "08:30", 30, 10, 0, "completed", "Pre-admission evaluation", "Cardiac baseline stable.", "Aspirin 81mg"),
        ("Carol White", "Dr. Linda Park", "O-301", "09:00", "09:30", 30, 10, 5, "completed", "Initial orthopedic triage", "Knee joint effusion noted.", "Ice packs, rest"),
        ("Noah Jackson", "Dr. Emily Chen", "N-201", "10:00", "10:45", 45, 10, 0, "completed", "Neurology consultation", "Mild transient ischemic symptoms.", "Neurology follow-up"),
        ("Emma Davis", "Dr. Maria Santos", "S-501", "11:00", "12:00", 60, 10, 10, "completed", "Surgical triage", "RLQ tenderness confirmed.", "Surgical admission"),
    ]
    for spec in yesterday_specs:
        p_name, d_name, r_num, s_time, e_time, dur, buf, wait, status, notes, clin_notes, rx = spec
        p = patients_map.get(p_name)
        d = doctors_map.get(d_name)
        r = rooms_map.get(r_num)
        if p and d and r:
            appt = Appointment(
                patient_id=p.id,
                doctor_id=d.id,
                room_id=r.id,
                date=yesterday_str,
                start_time=s_time,
                end_time=e_time,
                duration_minutes=dur,
                buffer_minutes=buf,
                waiting_time=wait,
                status=status,
                is_emergency=False,
                notes=notes,
                clinical_notes=clin_notes,
                prescription=rx,
                optimization_run_id=opt_run.id,
                created_at=datetime.utcnow() - timedelta(days=1)
            )
            db.session.add(appt)

    # 4. Add appointments for tomorrow
    tomorrow_specs = [
        ("Frank Wilson", "Dr. Sarah Mitchell", "C-101", "09:00", "09:30", 30, 10, 0, "scheduled", "Follow-up", "Holter monitor review.", ""),
        ("Henry Clark", "Dr. Linda Park", "O-302", "10:00", "10:30", 30, 10, 0, "scheduled", "Cast check", "Check neurovascular status in splint.", ""),
        ("David Brown", "Dr. Ahmed Al-Rashid", "P-401", "11:00", "11:30", 30, 10, 0, "scheduled", "Pediatric follow-up", "Post-bronchospasm review.", "")
    ]
    for spec in tomorrow_specs:
        p_name, d_name, r_num, s_time, e_time, dur, buf, wait, status, notes, clin_notes, rx = spec
        p = patients_map.get(p_name)
        d = doctors_map.get(d_name)
        r = rooms_map.get(r_num)
        if p and d and r:
            appt = Appointment(
                patient_id=p.id,
                doctor_id=d.id,
                room_id=r.id,
                date=tomorrow_str,
                start_time=s_time,
                end_time=e_time,
                duration_minutes=dur,
                buffer_minutes=buf,
                waiting_time=wait,
                status=status,
                is_emergency=False,
                notes=notes,
                clinical_notes=clin_notes,
                prescription=rx,
                optimization_run_id=None,
                created_at=datetime.utcnow()
            )
            db.session.add(appt)

    db.session.commit()
    print(f"[SEED] Seeded {len(appointments_today) + len(yesterday_specs) + len(tomorrow_specs)} appointments and 1 OptimizationRun successfully for {today_str}!")


def seed_database():
    """Seed comprehensive dataset if tables are empty or incomplete."""
    # Always ensure permissions and system roles are synced first
    roles_by_name = seed_permissions_and_roles()

    # Seed base tables if empty
    if Department.query.count() == 0:
        seed_base_data(roles_by_name)

    # Seed appointments and initial runs if appointments table is empty
    if Appointment.query.count() == 0:
        seed_appointments_and_runs()

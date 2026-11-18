-- ====================================================================
-- MediOptim Pro - Full Supabase PostgreSQL Database Initializer
-- Paste and run this script in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/vnoonkhiqnggtbtaqhqz/sql
-- ====================================================================

BEGIN;

-- 1. Create Alembic Version Tracking Table
CREATE TABLE IF NOT EXISTS alembic_version (
    version_num VARCHAR(32) NOT NULL, 
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- 2. Core Tables
CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(100) NOT NULL UNIQUE, 
    capacity INTEGER, 
    description TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS optimization_runs (
    id SERIAL PRIMARY KEY, 
    algorithm VARCHAR(50) NOT NULL, 
    algorithm_used VARCHAR(50), 
    fallback_reason VARCHAR(255), 
    run_date VARCHAR(20) NOT NULL, 
    total_patients INTEGER, 
    assigned_patients INTEGER, 
    unassigned_patients INTEGER, 
    avg_wait_time FLOAT, 
    utilization_rate FLOAT, 
    status VARCHAR(20), 
    solver_log TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patients (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(150) NOT NULL, 
    age INTEGER NOT NULL, 
    gender VARCHAR(10) NOT NULL, 
    priority VARCHAR(20), 
    required_specialization VARCHAR(100) NOT NULL, 
    condition_description TEXT, 
    preferred_date VARCHAR(20), 
    triage_level INTEGER, 
    blood_pressure VARCHAR(20), 
    heart_rate INTEGER, 
    spo2 INTEGER, 
    temperature FLOAT, 
    no_show_risk FLOAT, 
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_patients_priority_preferred_date ON patients (priority, preferred_date);

CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY, 
    key VARCHAR(80) NOT NULL UNIQUE, 
    "group" VARCHAR(50) NOT NULL, 
    label_en VARCHAR(120) NOT NULL, 
    label_ar VARCHAR(120) NOT NULL, 
    description TEXT, 
    is_sensitive BOOLEAN NOT NULL DEFAULT FALSE, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_permissions_group ON permissions ("group");

CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(60) NOT NULL UNIQUE, 
    description VARCHAR(255), 
    is_system BOOLEAN NOT NULL DEFAULT FALSE, 
    is_locked BOOLEAN NOT NULL DEFAULT FALSE, 
    version INTEGER NOT NULL DEFAULT 1, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), 
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctors (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(150) NOT NULL, 
    specialization VARCHAR(100) NOT NULL, 
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT, 
    max_patients_per_day INTEGER DEFAULT 15, 
    available_from VARCHAR(10) DEFAULT '08:00', 
    available_until VARCHAR(10) DEFAULT '16:00', 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE, 
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE, 
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY, 
    room_number VARCHAR(20) NOT NULL UNIQUE, 
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT, 
    room_type VARCHAR(50), 
    capacity INTEGER DEFAULT 1, 
    status VARCHAR(20) DEFAULT 'available', 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS beds (
    id SERIAL PRIMARY KEY, 
    bed_number VARCHAR(30) NOT NULL UNIQUE, 
    room_id INTEGER NOT NULL REFERENCES rooms(id) ON DELETE CASCADE, 
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT, 
    status VARCHAR(20) DEFAULT 'available', 
    patient_id INTEGER REFERENCES patients(id) ON DELETE SET NULL, 
    admission_date VARCHAR(20), 
    expected_discharge VARCHAR(20), 
    notes TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS equipment (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(120) NOT NULL, 
    equipment_type VARCHAR(60) NOT NULL, 
    department_id INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT, 
    room_id INTEGER REFERENCES rooms(id) ON DELETE SET NULL, 
    status VARCHAR(30) DEFAULT 'operational', 
    notes TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY, 
    username VARCHAR(80) NOT NULL UNIQUE, 
    email VARCHAR(120) NOT NULL UNIQUE, 
    password_hash VARCHAR(255) NOT NULL, 
    role VARCHAR(30), 
    role_id INTEGER REFERENCES roles(id) ON DELETE SET NULL, 
    full_name VARCHAR(150), 
    doctor_id INTEGER REFERENCES doctors(id) ON DELETE SET NULL, 
    must_change_password BOOLEAN NOT NULL DEFAULT FALSE, 
    is_active BOOLEAN NOT NULL DEFAULT TRUE, 
    failed_login_attempts INTEGER NOT NULL DEFAULT 0, 
    locked_until TIMESTAMP WITH TIME ZONE, 
    permissions_version INTEGER NOT NULL DEFAULT 1, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS appointments (
    id SERIAL PRIMARY KEY, 
    patient_id INTEGER NOT NULL REFERENCES patients(id) ON DELETE CASCADE, 
    doctor_id INTEGER NOT NULL REFERENCES doctors(id) ON DELETE RESTRICT, 
    room_id INTEGER NOT NULL REFERENCES rooms(id) ON DELETE RESTRICT, 
    date VARCHAR(20) NOT NULL, 
    start_time VARCHAR(10) NOT NULL, 
    end_time VARCHAR(10) NOT NULL, 
    duration_minutes INTEGER DEFAULT 30, 
    buffer_minutes INTEGER DEFAULT 10, 
    waiting_time INTEGER DEFAULT 0, 
    status VARCHAR(20) DEFAULT 'scheduled', 
    is_emergency BOOLEAN DEFAULT FALSE, 
    equipment_id INTEGER REFERENCES equipment(id) ON DELETE SET NULL, 
    notes TEXT, 
    clinical_notes TEXT, 
    prescription TEXT, 
    optimization_run_id INTEGER REFERENCES optimization_runs(id) ON DELETE SET NULL, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_appointments_lookup ON appointments (date, doctor_id, room_id, status);

CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY, 
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL, 
    user_name VARCHAR(80), 
    action VARCHAR(50) NOT NULL, 
    resource_type VARCHAR(50) NOT NULL, 
    resource_id INTEGER, 
    details TEXT, 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at);

CREATE TABLE IF NOT EXISTS user_permission_overrides (
    id SERIAL PRIMARY KEY, 
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, 
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE, 
    effect VARCHAR(10) NOT NULL, 
    reason VARCHAR(255) NOT NULL, 
    created_by VARCHAR(80), 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), 
    CONSTRAINT uq_user_permission_override UNIQUE (user_id, permission_id)
);

CREATE INDEX IF NOT EXISTS ix_user_permission_overrides_user_id ON user_permission_overrides (user_id);

-- Register Alembic Initial Revision
INSERT INTO alembic_version (version_num) VALUES ('8d64a86ca7f5') ON CONFLICT DO NOTHING;

-- 3. Baseline Seed Data

-- Seed data for departments (6 records)
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (1, 'Cardiology', 60, 'Heart, vascular diagnostics, and critical cardiac care', '2026-11-15 16:25:42.863435') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (2, 'Neurology', 45, 'Brain, spinal cord, and neuro-intensive care', '2026-11-15 16:25:42.864435') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (3, 'Orthopedics', 50, 'Bones, joints, sports medicine, and trauma reconstruction', '2026-11-15 16:25:42.865445') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (4, 'Pediatrics', 70, 'Neonatal, infant, and child healthcare services', '2026-11-15 16:25:42.865445') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (5, 'General Surgery', 55, 'Laparoscopic, trauma, and elective surgical suites', '2026-11-15 16:25:42.865445') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (6, 'Unauthorized Dept', 50, '', '2026-11-16 03:39:22.350098') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('departments', 'id'), COALESCE((SELECT MAX(id) FROM departments), 1));

-- Seed data for roles (5 records)
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (1, 'admin', 'Chief Administrator with full access to all system modules and security controls', 1, 1, 1, '2026-11-15 17:20:41.696532', '2026-11-15 17:20:41.696532') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (2, 'manager', 'Operations Manager overseeing departmental resources, schedules, and analytics', 1, 0, 1, '2026-11-15 17:20:41.698545', '2026-11-15 17:20:41.698545') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (3, 'doctor', 'Attending Physician managing clinical consultations, patients, and diagnoses', 1, 0, 1, '2026-11-15 17:20:41.700545', '2026-11-15 17:20:41.700545') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (4, 'receptionist', 'Front Desk Receptionist managing patient intake, appointments, and triage', 1, 0, 1, '2026-11-15 17:20:41.700545', '2026-11-15 17:20:41.700545') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (5, 'demo_viewer', 'Public Demo Guest with read-only views and masked clinical details', 1, 0, 1, '2026-11-15 17:20:41.701545', '2026-11-15 17:20:41.701545') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('roles', 'id'), COALESCE((SELECT MAX(id) FROM roles), 1));

-- Seed data for permissions (36 records)
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (1, 'dashboard.view', 'dashboard', 'View Operations Dashboard', 'عرض لوحة العمليات الرئيسية', 'Access hospital operations summary, beds occupancy, and live telemetry.', 0, '2026-11-15 17:20:41.676436') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (2, 'patients.view', 'patients', 'View Patients Directory', 'استعراض دليل المرضى', 'View patient registry and basic demographic records.', 0, '2026-11-15 17:20:41.678437') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (3, 'patients.view_all', 'patients', 'View All Patients (Hospital-Wide)', 'عرض جميع مرضى المستشفى', 'View patient records across all hospital departments beyond own assignments.', 0, '2026-11-15 17:20:41.679448') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (4, 'patients.view_clinical', 'patients', 'View Sensitive Clinical Details', 'الاطلاع على البيانات السريرية الحساسة', 'Access detailed vital signs, clinical conditions, notes, and medical diagnoses.', 1, '2026-11-15 17:20:41.679448') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (5, 'patients.create', 'patients', 'Register New Patient', 'تسجيل مريض جديد', 'Create and register new patient files in the clinic registry.', 0, '2026-11-15 17:20:41.680444') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (6, 'patients.update', 'patients', 'Update Patient Information', 'تعديل بيانات المريض', 'Edit patient demographic details and contact preferences.', 0, '2026-11-15 17:20:41.680444') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (7, 'patients.delete', 'patients', 'Delete Patient Records', 'حذف سجلات المرضى', 'Permanently remove patient files and medical entries.', 1, '2026-11-15 17:20:41.681443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (8, 'doctors.view', 'doctors', 'View Physicians Directory', 'استعراض الأطباء والعيادات', 'View doctor profiles, specializations, and working hours.', 0, '2026-11-15 17:20:41.681443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (9, 'doctors.manage', 'doctors', 'Manage Doctors & Quotas', 'إدارة الأطباء وساعات العمل والكوتا', 'Add, modify or deactivate doctors, shift windows, and consultation limits.', 1, '2026-11-15 17:20:41.682444') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (10, 'rooms.view', 'rooms', 'View Clinic Rooms & Theaters', 'استعراض الغرف وغرف العمليات', 'View room inventory, department mappings, and statuses.', 0, '2026-11-15 17:20:41.682444') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (11, 'rooms.manage', 'rooms', 'Manage Rooms & Facilities', 'إدارة الغرف والمرافق', 'Add, modify or decommission clinic rooms, surgery suites, and beds capacity.', 1, '2026-11-15 17:20:41.682444') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (12, 'departments.view', 'departments', 'View Departments', 'استعراض الأقسام الطبية', 'View department list and capacity metrics.', 0, '2026-11-15 17:20:41.683436') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (13, 'departments.manage', 'departments', 'Manage Departments', 'إدارة الأقسام والخدمات', 'Create or update hospital departments and operational descriptions.', 1, '2026-11-15 17:20:41.683436') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (14, 'beds.view', 'beds', 'View Bed Matrix', 'استعراض مصفوفة الأسرّة', 'View ward beds, room allocation, and occupancy states.', 0, '2026-11-15 17:20:41.683436') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (15, 'beds.manage', 'beds', 'Manage Bed Infrastructure', 'إدارة بنية الأسرّة', 'Add, edit or retire inpatient bed assets across wards.', 1, '2026-11-15 17:20:41.684443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (16, 'beds.admit_discharge', 'beds', 'Admit & Discharge Patients', 'تسكين وإخراج المرضى من الأسرّة', 'Execute patient bed admissions, transfers, and sanitization discharges.', 0, '2026-11-15 17:20:41.684443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (17, 'equipment.view', 'equipment', 'View Medical Equipment Inventory', 'استعراض الأجهزة الطبية', 'View ventilators, scanners, and monitoring devices.', 0, '2026-11-15 17:20:41.685443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (18, 'equipment.manage', 'equipment', 'Manage Equipment Fleet', 'إدارة أسطول الأجهزة والصيانة', 'Register devices, assign to rooms, and update maintenance states.', 1, '2026-11-15 17:20:41.685443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (19, 'appointments.view', 'appointments', 'View Appointments', 'استعراض المواعيد والجدول', 'Access appointments schedule and timeline.', 0, '2026-11-15 17:20:41.685443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (20, 'appointments.view_all', 'appointments', 'View All Physicians Appointments', 'استعراض مواعيد كافة الأطباء', 'View schedules across all hospital doctors beyond own appointments.', 0, '2026-11-15 17:20:41.686443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (21, 'appointments.update_status', 'appointments', 'Update Appointment Status', 'تحديث حالة الموعد', 'Progress consultation states (in_progress, completed, cancelled, no_show).', 0, '2026-11-15 17:20:41.686443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (22, 'appointments.edit_clinical_notes', 'appointments', 'Edit Clinical Notes & Prescriptions', 'تحرير الملاحظات الطبية والروشتات', 'Record medical diagnosis notes and pharmacy prescriptions for visits.', 1, '2026-11-15 17:20:41.686443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (23, 'appointments.cancel', 'appointments', 'Cancel Consultations', 'إلغاء المواعيد المجدولة', 'Cancel scheduled appointments with automatic room freeing.', 0, '2026-11-15 17:20:41.687443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (24, 'optimization.run', 'optimization', 'Execute AI Optimization', 'تشغيل خوارزميات الجدولة الذكية', 'Trigger Mixed-Integer LP and Hybrid optimization scheduling runs.', 0, '2026-11-15 17:20:41.687443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (25, 'optimization.history.view', 'optimization', 'View Optimization Run History', 'عرض سجل وتيليمتري المحسن', 'Review mathematical solver telemetry, logs, and historical convergence.', 0, '2026-11-15 17:20:41.688443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (26, 'simulation.run', 'simulation', 'Execute Crisis Stress Simulator', 'تشغيل محاكي الأزمات والضغط', 'Simulate epidemic surges, doctor outages, and decontamination stress.', 0, '2026-11-15 17:20:41.688443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (27, 'emergency.trigger', 'emergency', 'Trigger Code Red Emergency Preemption', 'تفعيل طوارئ كود رد واستباق المواعيد', 'Admit critical acute walk-in patients with automated slot preemption.', 1, '2026-11-15 17:20:41.688443') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (28, 'analytics.view', 'analytics', 'View Clinical Analytics', 'استعراض التحليلات ومؤشرات الأداء', 'Analyze capacity utilization, throughput, and triage breakdowns.', 0, '2026-11-15 17:20:41.689517') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (29, 'queue_display.view', 'queue_display', 'Access Waiting Hall Display', 'عرض شاشة صالة الانتظار العامة', 'Open full-screen clinic patient calling monitor.', 0, '2026-11-15 17:20:41.689517') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (30, 'export.csv', 'export', 'Export Hospital Data (CSV)', 'تصدير البيانات وتقارير CSV', 'Export sanitized patient schedules and clinical records to CSV.', 1, '2026-11-15 17:20:41.690526') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (31, 'audit.view', 'audit', 'View Audit Logs', 'الاطلاع على سجلات التدقيق الأمني', 'Inspect immutable activity history, access trails, and authentication events.', 1, '2026-11-15 17:20:41.690526') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (32, 'users.view', 'users', 'View Users & Staff Accounts', 'استعراض حسابات الكادر والمستخدمين', 'List administrative and medical staff accounts.', 0, '2026-11-15 17:20:41.690526') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (33, 'users.manage', 'users', 'Manage User Accounts & Overrides', 'إدارة الحسابات والاستثناءات الشخصية', 'Create, deactivate, assign roles, and configure per-user permission overrides.', 1, '2026-11-15 17:20:41.691533') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (34, 'roles.view', 'roles', 'View Roles & Access Matrices', 'استعراض الأدوار ومصفوفة الصلاحيات', 'View configured roles and active permission mappings.', 0, '2026-11-15 17:20:41.691533') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (35, 'roles.manage', 'roles', 'Manage Roles & Edit Permissions', 'إدارة الأدوار وتعديل الصلاحيات', 'Create custom roles, edit role-permission mappings, and configure access policies.', 1, '2026-11-15 17:20:41.691533') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (36, 'settings.manage', 'settings', 'Manage System Configuration', 'إدارة إعدادات النظام', 'Configure hospital operational buffers, timezone, and global settings.', 1, '2026-11-15 17:20:41.692532') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('permissions', 'id'), COALESCE((SELECT MAX(id) FROM permissions), 1));

-- Seed data for role_permissions (111 records)
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 4) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 26) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 22) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 18) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 35) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 34) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 31) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 11) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 36) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 30) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 32) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 9) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 15) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 24) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 25) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 33) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 7) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 13) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 26) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 18) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 34) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 31) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 11) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 30) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 32) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 24) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 15) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 9) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 25) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 13) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 4) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 22) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 25) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 10) ON CONFLICT DO NOTHING;
-- Seed data for doctors (33 records)
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (1, 'Dr. Sarah Mitchell', 'Cardiology', 1, 12, '08:00', '16:00', '2026-11-15 16:25:42.866519') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (2, 'Dr. James Thornton', 'Cardiology', 1, 10, '09:00', '17:00', '2026-11-15 16:25:42.866519') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (3, 'Dr. Emily Chen', 'Neurology', 2, 8, '08:30', '16:30', '2026-11-15 16:25:42.866519') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (4, 'Dr. Robert Hayes', 'Neurology', 2, 9, '10:00', '18:00', '2026-11-15 16:25:42.867514') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (5, 'Dr. Linda Park', 'Orthopedics', 3, 11, '08:00', '16:00', '2026-11-15 16:25:42.867514') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (6, 'Dr. Ahmed Al-Rashid', 'Pediatrics', 4, 15, '08:00', '17:00', '2026-11-15 16:25:42.867514') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (7, 'Dr. Maria Santos', 'General Surgery', 5, 6, '07:00', '15:00', '2026-11-15 16:25:42.867514') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (8, 'Dr. Kevin O''Brien', 'General Surgery', 5, 7, '11:00', '19:00', '2026-11-15 16:25:42.867514') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (9, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:16:40.201648') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (10, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:02.134480') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (11, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:02.183165') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (12, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:02.263284') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (13, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:26.295809') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (14, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:26.342482') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (15, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:17:26.422322') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (16, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:24:55.721946') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (17, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:24:55.766645') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (18, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:24:55.851642') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (19, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:40:44.782711') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (20, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:40:44.825328') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (21, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 03:40:44.897174') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (22, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:49:48.427745') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (23, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:49:48.467004') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (24, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:49:48.533739') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (25, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:53:01.141434') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (26, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:53:01.188605') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (27, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 04:53:01.275387') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (28, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 15:12:02.448158') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (29, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 15:12:02.496549') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (30, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-16 15:12:02.585415') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (31, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-18 21:23:09.957422') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (32, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-18 21:23:10.017858') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (33, 'Dr. Test Constrained Doc', 'Cardiology', 1, 1, '08:00', '10:00', '2026-11-18 21:23:10.146267') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('doctors', 'id'), COALESCE((SELECT MAX(id) FROM doctors), 1));

-- Seed data for rooms (12 records)
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (1, 'C-101', 1, 'consultation', 1, 'available', '2026-11-15 16:25:43.266439') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (2, 'C-102', 1, 'consultation', 1, 'available', '2026-11-15 16:25:43.269514') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (3, 'N-201', 2, 'consultation', 1, 'available', '2026-11-15 16:25:43.269514') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (4, 'N-202', 2, 'icu', 2, 'available', '2026-11-15 16:25:43.269514') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (5, 'O-301', 3, 'consultation', 1, 'available', '2026-11-15 16:25:43.269514') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (6, 'O-302', 3, 'surgery', 1, 'available', '2026-11-15 16:25:43.270519') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (7, 'P-401', 4, 'consultation', 2, 'available', '2026-11-15 16:25:43.270519') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (8, 'P-402', 4, 'ward', 4, 'available', '2026-11-15 16:25:43.270519') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (9, 'S-501', 5, 'surgery', 1, 'available', '2026-11-15 16:25:43.270519') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (10, 'S-502', 5, 'consultation', 1, 'available', '2026-11-15 16:25:43.270519') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (11, 'UNIQUE-TEST-101', 1, 'consultation', 1, 'available', '2026-11-15 16:25:47.245598') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (12, 'R-OPT-1', 1, 'consultation', 1, 'available', '2026-11-16 03:16:40.204648') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('rooms', 'id'), COALESCE((SELECT MAX(id) FROM rooms), 1));

-- Seed data for beds (9 records)
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (1, 'BED-C101-A', 1, 1, 'occupied', 1, '2026-11-18', '', '', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (2, 'BED-N202-01', 4, 2, 'vacant', NULL, '', '', 'Monitored neuro-ICU patient', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (3, 'BED-N202-02', 4, 2, 'vacant', NULL, '', '', 'Under UV-C sterilization', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (4, 'BED-O301-A', 5, 3, 'vacant', NULL, '', '', '', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (5, 'BED-P402-01', 8, 4, 'vacant', NULL, '', '', 'Pediatric observation bed', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (6, 'BED-P402-02', 8, 4, 'vacant', NULL, '', '', '', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (7, 'BED-P402-03', 8, 4, 'vacant', NULL, '', '', 'Reserved for elective surgery recovery', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (8, 'BED-P402-04', 8, 4, 'vacant', NULL, '', '', '', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (9, 'BED-S501-A', 9, 5, 'vacant', NULL, '', '', '', '2026-11-15 16:25:43.275800') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('beds', 'id'), COALESCE((SELECT MAX(id) FROM beds), 1));

-- Seed data for equipment (8 records)
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (1, 'Hamilton-C6 ICU Ventilator', 'ventilator', 2, 4, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (2, 'Maquet Servo-u Ventilator', 'ventilator', 4, 8, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (3, 'Siemens Magnetom 3T MRI', 'mri', 2, 3, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (4, 'GE Revolution 256-Slice CT', 'ct_scanner', 5, 9, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (5, 'Philips PageWriter TC70 ECG', 'ecg', 1, 1, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (6, 'Zoll R Series Defibrillator', 'ecg', 4, 7, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (7, 'Stryker Laparoscopy Tower 4K', 'surgical_kit', 5, 9, 'in_use', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (8, 'Ziehm Vision RFD 3D C-Arm', 'ultrasound', 3, 6, 'available', '', '2026-11-15 16:25:43.273572') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('equipment', 'id'), COALESCE((SELECT MAX(id) FROM equipment), 1));

-- Seed data for users (5 records)
INSERT INTO users (id, username, email, password_hash, role, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, created_at, role_id, permissions_version) VALUES (1, 'admin', 'admin@hospital.org', 'scrypt:32768:8:1$XWiRks2nrMqtdYio$72896ca2a5fb073745ffe14470ddbe9348cdf2ee94b52b6fb813c99aaf15c2e677df9857bc3138bb6bae0d8759974a56a278cf2cac2cdf7884a7f82e734a4718', 'admin', 'Chief Administrator', NULL, 0, 1, 0, NULL, '2026-11-18 21:23:05.003745', 1, 1) ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, created_at, role_id, permissions_version) VALUES (2, 'manager', 'manager@hospital.org', 'scrypt:32768:8:1$R2eki8QzQpERsf5p$e3f9bca897b3753d5307c5f3a291f2bff32f8af80cb5e091d4da03fd6fb676602703025f30d1b42f167a11bff0472e5167be86c9be48aec39b513c6d238e4347', 'manager', 'Operations Director', NULL, 0, 1, 0, NULL, '2026-11-18 21:23:05.097261', 2, 1) ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, created_at, role_id, permissions_version) VALUES (3, 'dr_sarah', 's.mitchell@hospital.org', 'scrypt:32768:8:1$xH9BgNDUAUwXycdF$86a0ede57bc040c4e7a03dbb7b82c9d2f20c3b12de4299e907ad0c67325acc06f520bfa11a7b12db2454535323af4cd00ab1c566a769674dbe0e4186715c1ecf', 'doctor', 'Dr. Sarah Mitchell', 1, 0, 1, 0, NULL, '2026-11-18 21:23:05.184151', 3, 1) ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, created_at, role_id, permissions_version) VALUES (4, 'receptionist', 'frontdesk@hospital.org', 'scrypt:32768:8:1$dOmk7yiWU3x9WfSP$4724f20d31edaaf00cf53462d4bf8a771267709813f39b6c9b9478fbfec98e01f5e52191bd5b9d57ba1741519ee205b14c5c78f4c5476e60fcdb79a77c05cfde', 'receptionist', 'Front Desk Reception', NULL, 0, 1, 0, NULL, '2026-11-18 21:23:05.279956', 4, 3) ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, created_at, role_id, permissions_version) VALUES (5, 'demo_viewer', 'demo@hospital.org', 'scrypt:32768:8:1$PJrSCJuahtH4jZlA$4337e6efd70b2812cb06a899c8ec1b1dde550ecac46319c01ad5e22a21a5cadc44be0360dbf8a057a052d4886d346a07258c389fda51e30a4c571b3acd2cde83', 'demo_viewer', 'Public Demo Guest (Read-Only)', NULL, 0, 1, 0, NULL, '2026-11-18 21:23:05.383975', 5, 1) ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('users', 'id'), COALESCE((SELECT MAX(id) FROM users), 1));

-- Seed data for patients (20 records)
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (1, 'Alice Johnson', 45, 'Female', 'critical', 'Cardiology', 'Severe acute chest pain radiating to left arm, ST elevation suspected', '2025-10-10', 1, '165/105', 112, 93, 37.1, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (2, 'Bob Martinez', 62, 'Male', 'urgent', 'Neurology', 'Acute recurring migraine with hemiparesis and visual blur', '2025-10-10', 2, '145/92', 88, 97, 36.9, 0.04, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (3, 'Carol White', 38, 'Female', 'normal', 'Orthopedics', 'Right knee anterior cruciate ligament strain after fall', '2025-10-10', 4, '118/76', 72, 99, 36.8, 0.18, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (4, 'David Brown', 7, 'Male', 'urgent', 'Pediatrics', 'High continuous fever (39.5C) with wheezing and respiratory retractions', '2025-10-10', 2, '100/65', 128, 92, 39.5, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (5, 'Emma Davis', 55, 'Female', 'critical', 'General Surgery', 'Acute McBurney point tenderness, suspected perforated appendicitis', '2025-10-10', 1, '138/88', 105, 96, 38.8, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (6, 'Frank Wilson', 70, 'Male', 'normal', 'Cardiology', 'Routine annual hypertensive and pacemaker checkup', '2025-10-10', 4, '130/82', 68, 98, 36.7, 0.13, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (7, 'Grace Lee', 29, 'Female', 'low', 'Neurology', 'Occasional mild tension headaches over past 3 months', '2025-10-10', 5, '115/74', 70, 99, 36.6, 0.34, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (8, 'Henry Clark', 48, 'Male', 'urgent', 'Orthopedics', 'Closed displaced radius fracture with neurovascular intact', '2025-10-10', 3, '135/85', 84, 98, 37.0, 0.04, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (9, 'Iris Taylor', 5, 'Female', 'critical', 'Pediatrics', 'Peanut allergen exposure with facial angioedema and stridor', '2025-10-10', 1, '90/58', 135, 91, 37.2, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (10, 'James Anderson', 33, 'Male', 'normal', 'General Surgery', 'Reducible right inguinal hernia consultation', '2025-10-10', 4, '122/78', 74, 99, 36.7, 0.18, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (11, 'Karen Thompson', 52, 'Female', 'urgent', 'Cardiology', 'Hypertensive crisis (185/110) with occipital pressure', '2025-10-10', 2, '185/110', 96, 96, 37.0, 0.04, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (12, 'Liam Robinson', 11, 'Male', 'normal', 'Pediatrics', 'Routine school physical and booster immunization', '2025-10-10', 5, '105/68', 78, 99, 36.8, 0.13, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (13, 'Mia Harris', 65, 'Female', 'low', 'Orthopedics', 'Bilateral knee osteoarthritis conservative management review', '2025-10-10', 5, '128/80', 66, 98, 36.6, 0.29, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (14, 'Noah Jackson', 41, 'Male', 'critical', 'Neurology', 'Sudden onset facial droop and right arm pronator drift (<2 hrs)', '2025-10-10', 1, '160/95', 102, 95, 37.3, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (15, 'Olivia Martin', 27, 'Female', 'normal', 'General Surgery', 'Symptomatic cholelithiasis for elective laparoscopic cholecystectomy', '2025-10-10', 4, '116/74', 76, 99, 36.9, 0.26, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (16, 'Peter Garcia', 58, 'Male', 'urgent', 'Cardiology', 'Post-coronary stenting 30-day review with peripheral edema', '2025-10-10', 3, '142/90', 82, 96, 36.8, 0.04, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (17, 'Quinn Roberts', 19, 'Female', 'low', 'General Surgery', 'Sebaceous cyst removal on back, non-infected', '2025-10-10', 5, '112/70', 72, 100, 36.5, 0.42, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (18, 'Ryan Lewis', 44, 'Male', 'normal', 'Neurology', 'Cervical radiculopathy with numbness in C6 dermatome', '2025-10-10', 4, '124/80', 75, 98, 36.7, 0.18, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (19, 'Sophia Walker', 3, 'Female', 'urgent', 'Pediatrics', 'Acute gastroenteritis with moderate dehydration and lethargy', '2025-10-10', 2, '88/54', 125, 95, 38.4, 0.01, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (20, 'Tyler Young', 36, 'Male', 'normal', 'Orthopedics', 'Chronic lumbar disc L5-S1 herniation follow-up', '2025-10-10', 4, '120/78', 70, 99, 36.6, 0.18, '2026-11-15 16:25:43.271519', '2026-11-15 16:25:43.274800') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('patients', 'id'), COALESCE((SELECT MAX(id) FROM patients), 1));

-- Seed data for optimization_runs (73 records)
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (1, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 980 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:30-09:00 | wait=30m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-502 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:00-09:30 | wait=60m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:00-08:30 | wait=0m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 16:25:46.500484') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (2, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 16:26:43.095284') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (3, 'hybrid', 'hybrid', NULL, '2026-11-15', 21, 21, 0, 0.0, 21.79, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 11 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 14:00-14:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Emily Chen | Room N-202 | 10:15-11:10 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 15:45-16:15 | wait=0m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Kevin O''Brien | Room S-501 | 13:00-14:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-301 | 08:15-08:45 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:30-09:00 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:30-12:10 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Robert Hayes | Room N-201 | 13:45-14:40 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:00-11:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 10:15-10:45 | wait=0m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 11 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 08:45-09:15 | Wait=0m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=0m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:15 | Wait=0m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:15-09:45 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=0m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:20 | Wait=0m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 10:00-10:45 | Wait=0m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:45-10:15 | Wait=0m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] Finished. Assigned: 11, Unassigned: 0
[HYBRID] Final Result: Assigned=21, Unassigned=0', '2026-11-15 17:09:34.823072') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (4, 'hybrid', 'hybrid', NULL, '2025-10-10', 1, 1, 0, 0.0, 0.77, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 1 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 1 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] Finished. Assigned: 1, Unassigned: 0
[HYBRID] Final Result: Assigned=1, Unassigned=0', '2026-11-15 17:20:57.844491') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (5, 'hybrid', 'hybrid', NULL, '2025-10-10', 22, 22, 0, 44.32, 23.85, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 12 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1487 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:10 | wait=30m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Kevin O''Brien | Room S-502 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:15-09:55 | wait=75m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room C-101 | 10:15-10:55 | wait=75m
[LP] Completed. Assigned: 12, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:15-10:45 | Wait=135m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=22, Unassigned=0', '2026-11-15 17:20:58.387298') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (6, 'hybrid', 'hybrid', NULL, '2025-10-10', 2, 2, 0, 0.0, 1.54, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 2 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 2 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] Finished. Assigned: 2, Unassigned: 0
[HYBRID] Final Result: Assigned=2, Unassigned=0', '2026-11-15 17:23:16.289400') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (7, 'hybrid', 'hybrid', NULL, '2025-10-10', 22, 22, 0, 48.41, 24.62, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 12 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1432 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:10 | wait=30m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Emily Chen | Room N-202 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-502 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 10:45-11:25 | wait=105m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Robert Hayes | Room N-201 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | wait=30m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:15-09:55 | wait=75m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:40 | wait=60m
[LP] Completed. Assigned: 12, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:15-10:45 | Wait=135m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-202 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=22, Unassigned=0', '2026-11-15 17:23:16.754659') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (8, 'hybrid', 'hybrid', NULL, '2025-10-10', 3, 3, 0, 10.0, 2.31, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 3 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 3 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] Finished. Assigned: 3, Unassigned: 0
[HYBRID] Final Result: Assigned=3, Unassigned=0', '2026-11-15 17:24:34.560435') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (9, 'hybrid', 'hybrid', NULL, '2025-10-10', 22, 22, 0, 51.82, 25.38, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 12 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1407 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. James Thornton | Room C-101 | 10:45-11:25 | wait=105m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Kevin O''Brien | Room S-502 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. Sarah Mitchell | Room C-101 | 09:45-10:25 | wait=105m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | wait=30m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:40 | wait=60m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 10:00-10:40 | wait=60m
[LP] Completed. Assigned: 12, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=22, Unassigned=0', '2026-11-15 17:24:34.889190') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (10, 'hybrid', 'hybrid', NULL, '2025-10-10', 3, 3, 0, 10.0, 2.31, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 3 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 3 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] Finished. Assigned: 3, Unassigned: 0
[HYBRID] Final Result: Assigned=3, Unassigned=0', '2026-11-15 17:24:51.500311') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (11, 'hybrid', 'hybrid', NULL, '2025-10-10', 22, 22, 0, 51.82, 25.38, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 12 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1407 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. James Thornton | Room C-101 | 10:45-11:25 | wait=105m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Kevin O''Brien | Room S-502 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. Sarah Mitchell | Room C-101 | 09:45-10:25 | wait=105m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | wait=30m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:40 | wait=60m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 10:00-10:40 | wait=60m
[LP] Completed. Assigned: 12, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=22, Unassigned=0', '2026-11-15 17:24:51.808946') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (12, 'hybrid', 'hybrid', NULL, '2025-10-10', 3, 3, 0, 10.0, 2.31, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 3 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 3 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] Finished. Assigned: 3, Unassigned: 0
[HYBRID] Final Result: Assigned=3, Unassigned=0', '2026-11-15 17:25:52.049919') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (13, 'greedy', 'greedy', NULL, '2026-11-15', 5, 5, 0, 0.0, 26.15, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 5 patients with dynamic procedure durations.
[GREEDY] ✓ Mohamed (CRITICAL, 40m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Mohamed (CRITICAL, 40m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:45-10:15 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 10:00-10:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 10:15-10:45 | Wait=0m
[GREEDY] Finished. Assigned: 5, Unassigned: 0', '2026-11-15 17:36:20.076658') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (14, 'greedy', 'greedy', NULL, '2026-11-15', 26, 26, 0, 0.0, 26.15, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 26 patients with dynamic procedure durations.
[GREEDY] ✓ Alice Johnson (CRITICAL, 40m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Emma Davis (CRITICAL, 70m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | Wait=0m
[GREEDY] ✓ Iris Taylor (CRITICAL, 30m) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Noah Jackson (CRITICAL, 55m) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | Wait=0m
[GREEDY] ✓ Mohamed (CRITICAL, 40m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Mohamed (CRITICAL, 40m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:25 | Wait=0m
[GREEDY] ✓ Bob Martinez (URGENT, 55m) → Dr. Dr. Robert Hayes | Room N-201 | 10:00-10:55 | Wait=0m
[GREEDY] ✓ David Brown (URGENT, 30m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | Wait=0m
[GREEDY] ✓ Karen Thompson (URGENT, 40m) → Dr. Dr. James Thornton | Room C-102 | 09:45-10:25 | Wait=0m
[GREEDY] ✓ Sophia Walker (URGENT, 30m) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ Henry Clark (URGENT, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Peter Garcia (URGENT, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:30-10:00 | Wait=0m
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=0m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:30-11:00 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=0m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-202 | 09:30-10:15 | Wait=0m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:15-10:45 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 11:00-11:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 11:00-11:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:30-12:00 | Wait=0m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=0m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=0m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=0m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=0m
[GREEDY] Finished. Assigned: 26, Unassigned: 0', '2026-11-15 17:36:22.957481') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (15, 'hybrid', 'hybrid', NULL, '2025-10-10', 4, 4, 0, 15.0, 3.08, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 4 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 4 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] Finished. Assigned: 4, Unassigned: 0
[HYBRID] Final Result: Assigned=4, Unassigned=0', '2026-11-15 17:52:31.829806') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (16, 'hybrid', 'hybrid', NULL, '2025-10-10', 5, 5, 0, 24.0, 3.85, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 5 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 5 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] Finished. Assigned: 5, Unassigned: 0
[HYBRID] Final Result: Assigned=5, Unassigned=0', '2026-11-15 18:14:08.663109') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (17, 'hybrid', 'hybrid', NULL, '2025-10-10', 6, 6, 0, 30.0, 4.62, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 6 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 6 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] Finished. Assigned: 6, Unassigned: 0
[HYBRID] Final Result: Assigned=6, Unassigned=0', '2026-11-15 18:14:50.943539') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (18, 'hybrid', 'hybrid', NULL, '2025-10-10', 7, 7, 0, 40.71, 5.38, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 7 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 7 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] Finished. Assigned: 7, Unassigned: 0
[HYBRID] Final Result: Assigned=7, Unassigned=0', '2026-11-15 18:27:22.599004') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (19, 'hybrid', 'hybrid', NULL, '2025-10-10', 8, 8, 0, 46.88, 6.15, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 8 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 8 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] Finished. Assigned: 8, Unassigned: 0
[HYBRID] Final Result: Assigned=8, Unassigned=0', '2026-11-15 18:30:51.704328') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (20, 'hybrid', 'hybrid', NULL, '2025-10-10', 9, 9, 0, 58.33, 6.92, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 9 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 9 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] Finished. Assigned: 9, Unassigned: 0
[HYBRID] Final Result: Assigned=9, Unassigned=0', '2026-11-15 19:00:59.529154') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (21, 'hybrid', 'hybrid', NULL, '2025-10-10', 10, 10, 0, 64.5, 7.69, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 10 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=10, Unassigned=0', '2026-11-15 19:04:04.533909') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (22, 'hybrid', 'hybrid', NULL, '2025-10-10', 11, 11, 0, 76.36, 8.46, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 11 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 11 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] Finished. Assigned: 11, Unassigned: 0
[HYBRID] Final Result: Assigned=11, Unassigned=0', '2026-11-15 19:05:25.314893') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (23, 'hybrid', 'hybrid', NULL, '2025-10-10', 12, 12, 0, 82.5, 9.23, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 12 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 12 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] Finished. Assigned: 12, Unassigned: 0
[HYBRID] Final Result: Assigned=12, Unassigned=0', '2026-11-15 19:22:22.279476') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (24, 'hybrid', 'hybrid', NULL, '2025-10-10', 13, 13, 0, 93.46, 10.0, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 13 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 13 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 11:45-12:15 | Wait=225m
[GREEDY] Finished. Assigned: 13, Unassigned: 0
[HYBRID] Final Result: Assigned=13, Unassigned=0', '2026-11-15 19:23:21.722084') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (25, 'hybrid', 'hybrid', NULL, '2025-10-10', 14, 14, 0, 99.64, 10.77, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 14 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 14 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 12:00-12:30 | Wait=180m
[GREEDY] Finished. Assigned: 14, Unassigned: 0
[HYBRID] Final Result: Assigned=14, Unassigned=0', '2026-11-15 20:55:50.404909') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (26, 'hybrid', 'hybrid', NULL, '2025-10-10', 15, 15, 0, 110.0, 11.54, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 15 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 15 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 12:00-12:30 | Wait=180m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 12:15-12:45 | Wait=255m
[GREEDY] Finished. Assigned: 15, Unassigned: 0
[HYBRID] Final Result: Assigned=15, Unassigned=0', '2026-11-15 21:33:03.559216') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (27, 'hybrid', 'hybrid', NULL, '2025-10-10', 16, 16, 0, 116.25, 12.31, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 16 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 16 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 12:00-12:30 | Wait=180m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 12:15-12:45 | Wait=255m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 12:30-13:00 | Wait=210m
[GREEDY] Finished. Assigned: 16, Unassigned: 0
[HYBRID] Final Result: Assigned=16, Unassigned=0', '2026-11-15 21:34:08.824299') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (28, 'hybrid', 'hybrid', NULL, '2025-10-10', 17, 17, 0, 126.18, 13.08, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 0 patients
[HYBRID] Standard queue: 17 patients
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 17 patients with dynamic procedure durations.
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:00 | Wait=30m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-101 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-102 | 12:00-12:30 | Wait=180m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 12:15-12:45 | Wait=255m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. James Thornton | Room C-101 | 12:30-13:00 | Wait=210m
[GREEDY] ✓ =SUM(1+1) (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 12:45-13:15 | Wait=285m
[GREEDY] Finished. Assigned: 17, Unassigned: 0
[HYBRID] Final Result: Assigned=17, Unassigned=0', '2026-11-15 21:50:56.501667') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (29, 'hybrid', 'hybrid', NULL, '2025-10-10', 22, 21, 1, 105.0, 35.38, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 12 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 947 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. James Thornton | Room C-101 | 14:00-14:40 | wait=300m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-301 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. Sarah Mitchell | Room C-102 | 13:45-14:25 | wait=345m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-202 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. Sarah Mitchell | Room C-101 | 13:15-13:45 | wait=315m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. James Thornton | Room UNIQUE-TEST-101 | 13:00-13:40 | wait=240m
[LP] ✓ Mohamed (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 14:30-15:10 | wait=390m
[LP] Completed. Assigned: 12, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=30m
[GREEDY] ✗ Could not schedule Frank Wilson (Capacity full or time window exceeded)
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 9, Unassigned: 1
[HYBRID] Final Result: Assigned=21, Unassigned=1', '2026-11-15 21:50:56.821590') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (30, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 22:00:52.918066') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (31, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 22:15:21.895425') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (32, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 22:54:25.027580') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (33, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 22:59:44.184599') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (34, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 23:01:44.511457') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (35, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 23:04:31.760334') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (36, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 23:20:58.645959') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (37, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-15 23:34:30.453792') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (38, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:24:08.491231') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (39, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:29:10.672296') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (40, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:36:13.582212') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (41, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:36:54.215392') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (42, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:37:21.704532') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (43, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:37:51.198570') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (44, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 00:41:17.408590') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (45, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:10:04.377266') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (46, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:11:27.598582') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (47, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:24:36.410454') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (48, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:25:24.942729') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (49, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:28:32.281429') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (50, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 01:55:09.489875') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (51, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:05:44.769386') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (52, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:07:15.326075') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (53, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:14:25.834410') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (54, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:19:05.797756') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (55, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:26:30.850724') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (56, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:44:55.771065') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (57, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 35.25, 21.03, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1162 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. James Thornton | Room C-102 | 09:30-10:10 | wait=30m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. James Thornton | Room C-101 | 09:00-09:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:45-09:15 | Wait=45m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 02:53:43.147616') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (58, 'greedy', 'greedy', NULL, '2032-04-16', 3, 2, 1, 0.0, 1.64, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 3 patients with dynamic procedure durations.
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] Finished. Assigned: 2, Unassigned: 1', '2026-11-16 03:17:02.212888') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (59, 'greedy', 'greedy', NULL, '2032-04-16', 14, 12, 2, 45.0, 9.09, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 14 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:30 | Wait=60m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 09:45-10:15 | Wait=45m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 10:15-10:45 | Wait=135m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room C-102 | 10:15-10:45 | Wait=75m
[GREEDY] Finished. Assigned: 12, Unassigned: 2', '2026-11-16 03:17:26.368579') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (60, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 31.5, 17.3, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 1876 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:00-08:30 | wait=0m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-502 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-402 | 09:00-09:30 | wait=60m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room C-101 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-202 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-401 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 03:17:36.441641') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (61, 'greedy', 'greedy', NULL, '2032-04-16', 11, 10, 1, 33.0, 7.03, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 11 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:30 | Wait=60m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=45m
[GREEDY] Finished. Assigned: 10, Unassigned: 1', '2026-11-16 03:24:55.794090') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (62, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 30.75, 16.08, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 2104 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:30-09:00 | wait=30m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-402 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room C-101 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-202 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 09:00-09:30 | wait=60m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-401 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 03:25:05.895306') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (63, 'greedy', 'greedy', NULL, '2032-04-16', 11, 10, 1, 33.0, 6.55, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 11 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:30 | Wait=60m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=45m
[GREEDY] Finished. Assigned: 10, Unassigned: 1', '2026-11-16 03:40:44.851881') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (64, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 30.75, 15.02, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 2332 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room C-101 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 03:40:55.804672') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (65, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 30.75, 15.02, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 2332 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room C-101 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 04:47:55.705080') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (66, 'greedy', 'greedy', NULL, '2032-04-16', 11, 10, 1, 33.0, 6.14, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 11 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:30 | Wait=60m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 09:45-10:15 | Wait=105m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 09:45-10:15 | Wait=45m
[GREEDY] Finished. Assigned: 10, Unassigned: 1', '2026-11-16 04:49:48.490716') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (67, 'greedy', 'greedy', NULL, '2032-04-16', 22, 20, 2, 115.5, 11.55, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 22 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Sarah Mitchell | Room C-101 | 10:00-10:40 | Wait=120m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. James Thornton | Room C-102 | 10:00-10:40 | Wait=60m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 10:45-11:15 | Wait=165m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. James Thornton | Room R-OPT-1 | 10:45-11:15 | Wait=105m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room C-102 | 11:15-11:45 | Wait=135m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 11:45-12:15 | Wait=165m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 12:15-12:45 | Wait=255m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room C-102 | 12:15-12:45 | Wait=195m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 12:45-13:15 | Wait=285m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 12:45-13:15 | Wait=225m
[GREEDY] Finished. Assigned: 20, Unassigned: 2', '2026-11-16 04:53:01.220302') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (68, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 31.5, 13.27, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 2788 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Sarah Mitchell | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-301 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room C-101 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. James Thornton | Room C-101 | 09:00-09:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 04:53:12.120391') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (69, 'greedy', 'greedy', NULL, '2032-04-16', 19, 18, 1, 96.67, 9.81, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 19 patients with dynamic procedure durations.
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Sarah Mitchell | Room C-101 | 10:00-10:40 | Wait=120m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. James Thornton | Room C-102 | 10:00-10:30 | Wait=60m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 10:45-11:15 | Wait=165m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=90m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 12:15-12:45 | Wait=255m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 12:00-12:30 | Wait=180m
[GREEDY] Finished. Assigned: 18, Unassigned: 1', '2026-11-16 15:12:02.533054') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (70, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 31.5, 12.54, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 3016 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Emily Chen | Room N-202 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-402 | 08:00-08:30 | wait=0m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-301 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-402 | 09:00-09:30 | wait=60m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:30-09:00 | wait=30m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-401 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-16 15:12:15.462913') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (71, 'greedy', 'greedy', NULL, '2026-11-18', 20, 20, 0, 30.75, 12.54, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 20 patients with dynamic procedure durations.
[GREEDY] ✓ Alice Johnson (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Emma Davis (CRITICAL, 70m) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | Wait=0m
[GREEDY] ✓ Iris Taylor (CRITICAL, 30m) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Noah Jackson (CRITICAL, 55m) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | Wait=0m
[GREEDY] ✓ Bob Martinez (URGENT, 55m) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | Wait=0m
[GREEDY] ✓ David Brown (URGENT, 30m) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Karen Thompson (URGENT, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ Sophia Walker (URGENT, 30m) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Henry Clark (URGENT, 30m) → Dr. Linda Park | Room O-301 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Peter Garcia (URGENT, 30m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 20, Unassigned: 0', '2026-11-18 21:21:53.984111') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (72, 'greedy', 'greedy', NULL, '2032-04-16', 35, 33, 2, 65.91, 18.88, 'success', '[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 35 patients with dynamic procedure durations.
[GREEDY] ✓ Alice Johnson (CRITICAL, 40m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Emma Davis (CRITICAL, 70m) → Dr. Maria Santos | Room S-501 | 07:00-08:10 | Wait=0m
[GREEDY] ✓ Iris Taylor (CRITICAL, 30m) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Noah Jackson (CRITICAL, 55m) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | Wait=0m
[GREEDY] ✓ TZ Test Patient (CRITICAL, 40m) → Dr. James Thornton | Room C-101 | 09:00-09:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ John Doe (CRITICAL, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:40 | Wait=0m
[GREEDY] ✓ Patient One (CRITICAL, 40m) → Dr. Test Constrained Doc | Room C-102 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Bob Martinez (URGENT, 55m) → Dr. Robert Hayes | Room N-201 | 10:00-10:55 | Wait=0m
[GREEDY] ✓ David Brown (URGENT, 30m) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Karen Thompson (URGENT, 40m) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sophia Walker (URGENT, 30m) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Test Constrained Doc | Room R-OPT-1 | 09:00-09:40 | Wait=60m
[GREEDY] ✓ Sarah Connor (URGENT, 40m) → Dr. Sarah Mitchell | Room C-101 | 10:00-10:40 | Wait=120m
[GREEDY] ✓ Henry Clark (URGENT, 30m) → Dr. Linda Park | Room O-301 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ Peter Garcia (URGENT, 30m) → Dr. James Thornton | Room C-102 | 10:00-10:30 | Wait=60m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. Sarah Mitchell | Room C-102 | 10:45-11:15 | Wait=165m
[GREEDY] ✓ Patient Two (URGENT, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 10:30-11:00 | Wait=90m
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✗ No matching doctor for Patient Three (Dermatology)
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 11:15-11:45 | Wait=195m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:15-09:15 | Wait=75m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-202 | 09:30-10:15 | Wait=60m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. James Thornton | Room R-OPT-1 | 11:00-11:30 | Wait=120m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-102 | 11:45-12:15 | Wait=225m
[GREEDY] ✓ Michael Brown (NORMAL, 30m) → Dr. James Thornton | Room UNIQUE-TEST-101 | 11:30-12:00 | Wait=150m
[GREEDY] ✓ Alice Wonderland (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 12:15-12:45 | Wait=255m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-202 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-302 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:00-13:00 | Wait=60m
[GREEDY] Finished. Assigned: 33, Unassigned: 2', '2026-11-18 21:23:10.060973') ON CONFLICT DO NOTHING;
INSERT INTO optimization_runs (id, algorithm, algorithm_used, fallback_reason, run_date, total_patients, assigned_patients, unassigned_patients, avg_wait_time, utilization_rate, status, solver_log, created_at) VALUES (73, 'hybrid', 'hybrid', NULL, '2025-10-10', 20, 20, 0, 31.5, 11.88, 'success', '[HYBRID] Starting Hybrid Scheduling (LP for Critical/Urgent + Greedy for Normal/Low)...
[HYBRID] High-priority queue: 10 patients
[HYBRID] Standard queue: 10 patients
[LP] Starting Mixed-Integer Linear Programming Optimization...
[LP] Formulating MIP model with 3244 candidate decision variables.
[LP] Executing CBC solver (limit 25s)...
[LP] Solver ended with status: Optimal (code=1)
[LP] ✓ Alice Johnson (CRITICAL) → Dr. Test Constrained Doc | Room C-102 | 08:00-08:40 | wait=0m
[LP] ✓ Bob Martinez (URGENT) → Dr. Emily Chen | Room N-201 | 08:30-09:25 | wait=0m
[LP] ✓ David Brown (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 09:00-09:30 | wait=60m
[LP] ✓ Emma Davis (CRITICAL) → Dr. Kevin O''Brien | Room S-501 | 11:00-12:10 | wait=0m
[LP] ✓ Henry Clark (URGENT) → Dr. Linda Park | Room O-302 | 08:00-08:30 | wait=0m
[LP] ✓ Iris Taylor (CRITICAL) → Dr. Ahmed Al-Rashid | Room P-402 | 08:30-09:00 | wait=30m
[LP] ✓ Karen Thompson (URGENT) → Dr. Test Constrained Doc | Room UNIQUE-TEST-101 | 08:00-08:40 | wait=0m
[LP] ✓ Noah Jackson (CRITICAL) → Dr. Robert Hayes | Room N-202 | 10:00-10:55 | wait=0m
[LP] ✓ Peter Garcia (URGENT) → Dr. Test Constrained Doc | Room R-OPT-1 | 08:00-08:30 | wait=0m
[LP] ✓ Sophia Walker (URGENT) → Dr. Ahmed Al-Rashid | Room P-401 | 08:00-08:30 | wait=0m
[LP] Completed. Assigned: 10, Unassigned: 0
[GREEDY] Starting Dynamic Greedy scheduling...
[GREEDY] Scheduling 10 patients with dynamic procedure durations.
[GREEDY] ✓ Carol White (NORMAL, 30m) → Dr. Linda Park | Room O-301 | 08:30-09:00 | Wait=30m
[GREEDY] ✓ Frank Wilson (NORMAL, 30m) → Dr. Sarah Mitchell | Room C-101 | 08:00-08:30 | Wait=0m
[GREEDY] ✓ James Anderson (NORMAL, 60m) → Dr. Maria Santos | Room S-501 | 07:00-08:00 | Wait=0m
[GREEDY] ✓ Olivia Martin (NORMAL, 60m) → Dr. Maria Santos | Room S-502 | 08:00-09:00 | Wait=60m
[GREEDY] ✓ Ryan Lewis (NORMAL, 45m) → Dr. Emily Chen | Room N-201 | 09:45-10:30 | Wait=75m
[GREEDY] ✓ Tyler Young (NORMAL, 30m) → Dr. Linda Park | Room O-302 | 09:00-09:30 | Wait=60m
[GREEDY] ✓ Liam Robinson (NORMAL, 20m) → Dr. Ahmed Al-Rashid | Room P-402 | 09:30-09:50 | Wait=90m
[GREEDY] ✓ Grace Lee (LOW, 45m) → Dr. Robert Hayes | Room N-201 | 11:00-11:45 | Wait=60m
[GREEDY] ✓ Mia Harris (LOW, 30m) → Dr. Linda Park | Room O-301 | 09:30-10:00 | Wait=90m
[GREEDY] ✓ Quinn Roberts (LOW, 60m) → Dr. Kevin O''Brien | Room S-502 | 12:15-13:15 | Wait=75m
[GREEDY] Finished. Assigned: 10, Unassigned: 0
[HYBRID] Final Result: Assigned=20, Unassigned=0', '2026-11-18 21:23:29.422785') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('optimization_runs', 'id'), COALESCE((SELECT MAX(id) FROM optimization_runs), 1));

-- Seed data for appointments (173 records)
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (45, 1, 1, 1, '2026-11-15', '08:00', '08:40', 40, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (46, 5, 7, 9, '2026-11-15', '07:00', '08:10', 70, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (47, 9, 6, 7, '2026-11-15', '08:00', '08:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (48, 14, 3, 3, '2026-11-15', '08:30', '09:25', 55, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (51, 2, 4, 3, '2026-11-15', '10:00', '10:55', 55, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (52, 4, 6, 8, '2026-11-15', '08:30', '09:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (53, 11, 2, 2, '2026-11-15', '09:45', '10:25', 40, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (54, 19, 6, 7, '2026-11-15', '09:00', '09:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (55, 8, 5, 5, '2026-11-15', '08:00', '08:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (56, 16, 1, 11, '2026-11-15', '09:30', '10:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (57, 3, 5, 6, '2026-11-15', '08:30', '09:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (58, 6, 2, 1, '2026-11-15', '10:30', '11:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (59, 10, 8, 9, '2026-11-15', '11:00', '12:00', 60, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (60, 15, 7, 10, '2026-11-15', '08:15', '09:15', 60, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (61, 18, 3, 4, '2026-11-15', '09:30', '10:15', 45, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (62, 20, 5, 5, '2026-11-15', '09:00', '09:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (67, 12, 6, 8, '2026-11-15', '09:30', '09:50', 20, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (68, 7, 4, 4, '2026-11-15', '11:00', '11:45', 45, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (69, 13, 5, 6, '2026-11-15', '09:30', '10:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (70, 17, 8, 10, '2026-11-15', '12:00', '13:00', 60, 10, 0, 'completed', 0, NULL, '', '', '', 14, '2026-11-15 17:36:22.963417') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (76, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 18:14:10.231250') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (77, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 18:14:10.231250') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (84, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 18:14:52.337046') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (85, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 18:14:52.337046') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (93, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 18:27:24.108927') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (94, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 18:27:24.108927') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (103, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 18:30:53.215387') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (104, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 18:30:53.215387') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (114, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 19:01:01.055258') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (115, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 19:01:01.055258') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (126, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 19:04:06.080532') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (127, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 19:04:06.080532') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (139, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 19:05:26.858102') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (140, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 19:05:26.858102') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (153, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 19:22:27.662169') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (154, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 19:22:27.662169') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (168, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 19:23:25.037268') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (169, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 19:23:25.037268') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (184, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 20:55:52.549899') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (185, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 20:55:52.549899') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (201, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 21:33:05.105913') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (202, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 21:33:05.105913') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (219, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 21:34:10.393050') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (220, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 21:34:10.393050') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (259, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 21:50:59.134955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (260, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 21:50:59.134955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (281, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 22:00:54.450105') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (282, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 22:00:54.450105') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (303, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 22:15:24.773449') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (304, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 22:15:24.773449') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (325, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 22:54:26.579651') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (326, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 22:54:26.579651') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (347, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 22:59:46.580253') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (348, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 22:59:46.580253') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (369, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 23:01:46.132895') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (370, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 23:01:46.132895') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (391, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 23:04:33.327133') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (392, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 23:04:33.327133') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (413, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 23:21:00.369787') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (414, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 23:21:00.369787') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (435, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-15 23:34:32.444258') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (436, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-15 23:34:32.444258') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (457, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:24:10.497941') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (458, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:24:10.497941') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (479, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:29:12.871360') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (480, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:29:12.871360') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (501, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:36:15.742275') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (502, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:36:15.742275') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (523, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:36:56.348642') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (524, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:36:56.348642') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (545, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:37:23.841450') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (546, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:37:23.841450') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (567, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:37:53.408231') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (568, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 00:37:53.408231') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (589, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 00:41:19.538871') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (590, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 00:41:19.538871') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (611, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 01:10:07.080938') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (612, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 01:10:07.080938') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (633, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 01:11:35.668224') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (634, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 01:11:35.668224') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (655, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 01:28:40.152126') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (656, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 01:28:40.152126') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (677, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 01:55:17.300850') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (678, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 01:55:17.300850') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (699, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:05:52.541021') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (700, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:05:52.541021') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (721, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:07:23.181968') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (722, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:07:23.181968') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (743, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:14:33.712327') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (744, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:14:33.712327') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (765, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:19:13.646290') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (766, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:19:13.646290') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (787, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:26:39.158692') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (788, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:26:39.158692') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (825, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:45:03.592920') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (826, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:45:03.592920') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (851, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 02:53:50.917941') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (852, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 02:53:50.917941') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (891, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 03:17:44.231630') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (892, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 03:17:44.231630') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (927, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 03:25:13.709040') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (928, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 03:25:13.709040') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (963, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 03:41:03.582870') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (964, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 03:41:03.582870') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (985, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 04:48:03.516009') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (986, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 04:48:03.516009') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1045, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 04:53:19.894598') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1046, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 04:53:19.894598') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1047, 34, 1, 1, '2026-11-16', '09:00', '09:30', 30, 10, 0, 'in_progress', 1, NULL, '', 'Confidential ECG anomaly ST elevation', 'Aspirin 300mg stat', NULL, '2026-11-16 15:12:02.415844') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1048, 35, 1, 1, '2026-11-16', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', 'Blood pressure monitoring notes', 'Amlodipine 5mg', NULL, '2026-11-16 15:12:02.415844') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1049, 36, 1, 1, '2026-11-16', '09:30', '10:00', 30, 10, 0, 'scheduled', 0, NULL, '', 'Stable routine checkup', '', NULL, '2026-11-16 15:12:02.416843') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1050, 37, 1, 1, '2026-11-16', '08:30', '09:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-16 15:12:02.416843') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1089, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-16 15:12:23.853890') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1090, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-16 15:12:23.853890') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1091, 26, 1, 1, '2026-11-18', '09:00', '09:30', 30, 10, 0, 'in_progress', 1, NULL, '', 'Confidential ECG anomaly ST elevation', 'Aspirin 300mg stat', NULL, '2026-11-18 21:23:09.922772') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1092, 27, 1, 1, '2026-11-18', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', 'Blood pressure monitoring notes', 'Amlodipine 5mg', NULL, '2026-11-18 21:23:09.922772') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1093, 28, 1, 1, '2026-11-18', '09:30', '10:00', 30, 10, 0, 'scheduled', 0, NULL, '', 'Stable routine checkup', '', NULL, '2026-11-18 21:23:09.923777') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1094, 29, 1, 1, '2026-11-18', '08:30', '09:00', 30, 10, 0, 'completed', 0, NULL, '', '', '', NULL, '2026-11-18 21:23:09.923777') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1095, 1, 1, 1, '2032-04-16', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1096, 5, 7, 9, '2032-04-16', '07:00', '08:10', 70, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1097, 9, 6, 7, '2032-04-16', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1098, 14, 3, 3, '2032-04-16', '08:30', '09:25', 55, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1099, 21, 2, 1, '2032-04-16', '09:00', '09:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1100, 22, 9, 2, '2032-04-16', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1101, 26, 10, 11, '2032-04-16', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1102, 30, 11, 12, '2032-04-16', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1103, 33, 12, 2, '2032-04-16', '09:00', '09:40', 40, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1104, 2, 4, 3, '2032-04-16', '10:00', '10:55', 55, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1105, 4, 6, 8, '2032-04-16', '08:30', '09:00', 30, 10, 30, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1106, 11, 13, 11, '2032-04-16', '09:00', '09:40', 40, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1107, 19, 6, 7, '2032-04-16', '09:00', '09:30', 30, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1108, 23, 14, 12, '2032-04-16', '09:00', '09:40', 40, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1109, 27, 1, 1, '2032-04-16', '10:00', '10:40', 40, 10, 120, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1110, 8, 5, 5, '2032-04-16', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1111, 16, 2, 2, '2032-04-16', '10:00', '10:30', 30, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1112, 31, 1, 2, '2032-04-16', '10:45', '11:15', 30, 10, 165, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1113, 34, 2, 11, '2032-04-16', '10:30', '11:00', 30, 10, 90, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1114, 3, 5, 6, '2032-04-16', '08:30', '09:00', 30, 10, 30, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1115, 6, 1, 1, '2032-04-16', '11:15', '11:45', 30, 10, 195, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1116, 10, 8, 9, '2032-04-16', '11:00', '12:00', 60, 10, 0, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1117, 15, 7, 10, '2032-04-16', '08:15', '09:15', 60, 10, 75, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1118, 18, 3, 4, '2032-04-16', '09:30', '10:15', 45, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1119, 20, 5, 5, '2032-04-16', '09:00', '09:30', 30, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1120, 24, 2, 12, '2032-04-16', '11:00', '11:30', 30, 10, 120, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1121, 25, 1, 2, '2032-04-16', '11:45', '12:15', 30, 10, 225, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1122, 28, 2, 11, '2032-04-16', '11:30', '12:00', 30, 10, 150, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1123, 29, 1, 1, '2032-04-16', '12:15', '12:45', 30, 10, 255, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1124, 12, 6, 8, '2032-04-16', '09:30', '09:50', 20, 10, 90, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1125, 7, 4, 4, '2032-04-16', '11:00', '11:45', 45, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1126, 13, 5, 6, '2032-04-16', '09:30', '10:00', 30, 10, 90, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1127, 17, 8, 10, '2032-04-16', '12:00', '13:00', 60, 10, 60, 'scheduled', 0, NULL, '', '', '', 72, '2026-11-18 21:23:10.067820') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1128, 1, 31, 2, '2025-10-10', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1129, 2, 3, 3, '2025-10-10', '08:30', '09:25', 55, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1130, 4, 6, 7, '2025-10-10', '09:00', '09:30', 30, 10, 60, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1131, 5, 8, 9, '2025-10-10', '11:00', '12:10', 70, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1132, 8, 5, 6, '2025-10-10', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1133, 9, 6, 8, '2025-10-10', '08:30', '09:00', 30, 10, 30, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1134, 11, 10, 11, '2025-10-10', '08:00', '08:40', 40, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1135, 14, 4, 4, '2025-10-10', '10:00', '10:55', 55, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1136, 16, 20, 12, '2025-10-10', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1137, 19, 6, 7, '2025-10-10', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1138, 3, 5, 5, '2025-10-10', '08:30', '09:00', 30, 10, 30, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1139, 6, 1, 1, '2025-10-10', '08:00', '08:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1140, 10, 7, 9, '2025-10-10', '07:00', '08:00', 60, 10, 0, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1141, 15, 7, 10, '2025-10-10', '08:00', '09:00', 60, 10, 60, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1142, 18, 3, 3, '2025-10-10', '09:45', '10:30', 45, 10, 75, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1143, 20, 5, 6, '2025-10-10', '09:00', '09:30', 30, 10, 60, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1144, 12, 6, 8, '2025-10-10', '09:30', '09:50', 20, 10, 90, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1145, 7, 4, 3, '2025-10-10', '11:00', '11:45', 45, 10, 60, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1146, 13, 5, 5, '2025-10-10', '09:30', '10:00', 30, 10, 90, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1147, 17, 8, 10, '2025-10-10', '12:15', '13:15', 60, 10, 75, 'scheduled', 0, NULL, '', '', '', 73, '2026-11-18 21:23:29.432955') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1148, 1, 1, 1, '2027-01-01', '09:00', '09:30', 30, 10, 0, 'in_progress', 0, NULL, '', '', '', NULL, '2026-11-18 21:23:37.872553') ON CONFLICT DO NOTHING;
INSERT INTO appointments (id, patient_id, doctor_id, room_id, date, start_time, end_time, duration_minutes, buffer_minutes, waiting_time, status, is_emergency, equipment_id, notes, clinical_notes, prescription, optimization_run_id, created_at) VALUES (1149, 2, 2, 2, '2027-01-01', '10:00', '10:30', 30, 10, 0, 'scheduled', 0, NULL, '', '', '', NULL, '2026-11-18 21:23:37.872553') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('appointments', 'id'), COALESCE((SELECT MAX(id) FROM appointments), 1));

-- 4. Enable Row Level Security (RLS) & Revoke Public PostgREST API
ALTER TABLE IF EXISTS alembic_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS beds ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS user_permission_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS optimization_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS audit_logs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon, authenticated;

COMMIT;

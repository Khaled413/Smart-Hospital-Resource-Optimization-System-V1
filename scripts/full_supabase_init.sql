-- ====================================================================
-- MediOptim Pro - Full Supabase PostgreSQL Database Initializer
-- Paste and run this script in the Supabase SQL Editor:
-- https://supabase.com/dashboard/project/vnoonkhiqnggtbtaqhqz/sql
-- ====================================================================

BEGIN;

-- 1. Alembic Migration Version Tracking
CREATE TABLE IF NOT EXISTS alembic_version (
    version_num VARCHAR(32) NOT NULL, 
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- 2. Core Tables DDL
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

-- 3. Baseline Production Seed Data

-- Seed data for departments (5 records)
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (1, 'Cardiology', 60, 'Heart, vascular diagnostics, and critical cardiac care', '2026-11-18 22:42:04.900543') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (2, 'Neurology', 45, 'Brain, spinal cord, and neuro-intensive care', '2026-11-18 22:42:04.901533') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (3, 'Orthopedics', 50, 'Bones, joints, sports medicine, and trauma reconstruction', '2026-11-18 22:42:04.901533') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (4, 'Pediatrics', 70, 'Neonatal, infant, and child healthcare services', '2026-11-18 22:42:04.902534') ON CONFLICT DO NOTHING;
INSERT INTO departments (id, name, capacity, description, created_at) VALUES (5, 'General Surgery', 55, 'Laparoscopic, trauma, and elective surgical suites', '2026-11-18 22:42:04.902534') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('departments', 'id'), COALESCE((SELECT MAX(id) FROM departments), 1));

-- Seed data for roles (5 records)
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (1, 'admin', 'Chief Administrator with full access to all system modules and security controls', TRUE, TRUE, 1, '2026-11-18 22:42:04.325560', '2026-11-18 22:42:04.325560') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (2, 'manager', 'Operations Manager overseeing departmental resources, schedules, and analytics', TRUE, FALSE, 1, '2026-11-18 22:42:04.327793', '2026-11-18 22:42:04.327793') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (3, 'doctor', 'Attending Physician managing clinical consultations, patients, and diagnoses', TRUE, FALSE, 1, '2026-11-18 22:42:04.328800', '2026-11-18 22:42:04.328800') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (4, 'receptionist', 'Front Desk Receptionist managing patient intake, appointments, and triage', TRUE, FALSE, 1, '2026-11-18 22:42:04.329797', '2026-11-18 22:42:04.329797') ON CONFLICT DO NOTHING;
INSERT INTO roles (id, name, description, is_system, is_locked, version, created_at, updated_at) VALUES (5, 'demo_viewer', 'Public Demo Guest with read-only views and masked clinical details', TRUE, FALSE, 1, '2026-11-18 22:42:04.330796', '2026-11-18 22:42:04.330796') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('roles', 'id'), COALESCE((SELECT MAX(id) FROM roles), 1));

-- Seed data for permissions (36 records)
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (1, 'dashboard.view', 'dashboard', 'View Operations Dashboard', 'عرض لوحة العمليات الرئيسية', 'Access hospital operations summary, beds occupancy, and live telemetry.', FALSE, '2026-11-18 22:42:04.303216') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (2, 'patients.view', 'patients', 'View Patients Directory', 'استعراض دليل المرضى', 'View patient registry and basic demographic records.', FALSE, '2026-11-18 22:42:04.304220') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (3, 'patients.view_all', 'patients', 'View All Patients (Hospital-Wide)', 'عرض جميع مرضى المستشفى', 'View patient records across all hospital departments beyond own assignments.', FALSE, '2026-11-18 22:42:04.305221') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (4, 'patients.view_clinical', 'patients', 'View Sensitive Clinical Details', 'الاطلاع على البيانات السريرية الحساسة', 'Access detailed vital signs, clinical conditions, notes, and medical diagnoses.', TRUE, '2026-11-18 22:42:04.305221') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (5, 'patients.create', 'patients', 'Register New Patient', 'تسجيل مريض جديد', 'Create and register new patient files in the clinic registry.', FALSE, '2026-11-18 22:42:04.306221') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (6, 'patients.update', 'patients', 'Update Patient Information', 'تعديل بيانات المريض', 'Edit patient demographic details and contact preferences.', FALSE, '2026-11-18 22:42:04.306221') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (7, 'patients.delete', 'patients', 'Delete Patient Records', 'حذف سجلات المرضى', 'Permanently remove patient files and medical entries.', TRUE, '2026-11-18 22:42:04.307572') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (8, 'doctors.view', 'doctors', 'View Physicians Directory', 'استعراض الأطباء والعيادات', 'View doctor profiles, specializations, and working hours.', FALSE, '2026-11-18 22:42:04.307572') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (9, 'doctors.manage', 'doctors', 'Manage Doctors & Quotas', 'إدارة الأطباء وساعات العمل والكوتا', 'Add, modify or deactivate doctors, shift windows, and consultation limits.', TRUE, '2026-11-18 22:42:04.308574') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (10, 'rooms.view', 'rooms', 'View Clinic Rooms & Theaters', 'استعراض الغرف وغرف العمليات', 'View room inventory, department mappings, and statuses.', FALSE, '2026-11-18 22:42:04.308574') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (11, 'rooms.manage', 'rooms', 'Manage Rooms & Facilities', 'إدارة الغرف والمرافق', 'Add, modify or decommission clinic rooms, surgery suites, and beds capacity.', TRUE, '2026-11-18 22:42:04.308574') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (12, 'departments.view', 'departments', 'View Departments', 'استعراض الأقسام الطبية', 'View department list and capacity metrics.', FALSE, '2026-11-18 22:42:04.309573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (13, 'departments.manage', 'departments', 'Manage Departments', 'إدارة الأقسام والخدمات', 'Create or update hospital departments and operational descriptions.', TRUE, '2026-11-18 22:42:04.309573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (14, 'beds.view', 'beds', 'View Bed Matrix', 'استعراض مصفوفة الأسرّة', 'View ward beds, room allocation, and occupancy states.', FALSE, '2026-11-18 22:42:04.310573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (15, 'beds.manage', 'beds', 'Manage Bed Infrastructure', 'إدارة بنية الأسرّة', 'Add, edit or retire inpatient bed assets across wards.', TRUE, '2026-11-18 22:42:04.310573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (16, 'beds.admit_discharge', 'beds', 'Admit & Discharge Patients', 'تسكين وإخراج المرضى من الأسرّة', 'Execute patient bed admissions, transfers, and sanitization discharges.', FALSE, '2026-11-18 22:42:04.310573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (17, 'equipment.view', 'equipment', 'View Medical Equipment Inventory', 'استعراض الأجهزة الطبية', 'View ventilators, scanners, and monitoring devices.', FALSE, '2026-11-18 22:42:04.311573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (18, 'equipment.manage', 'equipment', 'Manage Equipment Fleet', 'إدارة أسطول الأجهزة والصيانة', 'Register devices, assign to rooms, and update maintenance states.', TRUE, '2026-11-18 22:42:04.311573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (19, 'appointments.view', 'appointments', 'View Appointments', 'استعراض المواعيد والجدول', 'Access appointments schedule and timeline.', FALSE, '2026-11-18 22:42:04.311573') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (20, 'appointments.view_all', 'appointments', 'View All Physicians Appointments', 'استعراض مواعيد كافة الأطباء', 'View schedules across all hospital doctors beyond own appointments.', FALSE, '2026-11-18 22:42:04.312847') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (21, 'appointments.update_status', 'appointments', 'Update Appointment Status', 'تحديث حالة الموعد', 'Progress consultation states (in_progress, completed, cancelled, no_show).', FALSE, '2026-11-18 22:42:04.312847') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (22, 'appointments.edit_clinical_notes', 'appointments', 'Edit Clinical Notes & Prescriptions', 'تحرير الملاحظات الطبية والروشتات', 'Record medical diagnosis notes and pharmacy prescriptions for visits.', TRUE, '2026-11-18 22:42:04.314148') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (23, 'appointments.cancel', 'appointments', 'Cancel Consultations', 'إلغاء المواعيد المجدولة', 'Cancel scheduled appointments with automatic room freeing.', FALSE, '2026-11-18 22:42:04.314590') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (24, 'optimization.run', 'optimization', 'Execute AI Optimization', 'تشغيل خوارزميات الجدولة الذكية', 'Trigger Mixed-Integer LP and Hybrid optimization scheduling runs.', FALSE, '2026-11-18 22:42:04.315093') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (25, 'optimization.history.view', 'optimization', 'View Optimization Run History', 'عرض سجل وتيليمتري المحسن', 'Review mathematical solver telemetry, logs, and historical convergence.', FALSE, '2026-11-18 22:42:04.315093') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (26, 'simulation.run', 'simulation', 'Execute Crisis Stress Simulator', 'تشغيل محاكي الأزمات والضغط', 'Simulate epidemic surges, doctor outages, and decontamination stress.', FALSE, '2026-11-18 22:42:04.316097') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (27, 'emergency.trigger', 'emergency', 'Trigger Code Red Emergency Preemption', 'تفعيل طوارئ كود رد واستباق المواعيد', 'Admit critical acute walk-in patients with automated slot preemption.', TRUE, '2026-11-18 22:42:04.316097') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (28, 'analytics.view', 'analytics', 'View Clinical Analytics', 'استعراض التحليلات ومؤشرات الأداء', 'Analyze capacity utilization, throughput, and triage breakdowns.', FALSE, '2026-11-18 22:42:04.316097') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (29, 'queue_display.view', 'queue_display', 'Access Waiting Hall Display', 'عرض شاشة صالة الانتظار العامة', 'Open full-screen clinic patient calling monitor.', FALSE, '2026-11-18 22:42:04.317561') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (30, 'export.csv', 'export', 'Export Hospital Data (CSV)', 'تصدير البيانات وتقارير CSV', 'Export sanitized patient schedules and clinical records to CSV.', TRUE, '2026-11-18 22:42:04.317561') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (31, 'audit.view', 'audit', 'View Audit Logs', 'الاطلاع على سجلات التدقيق الأمني', 'Inspect immutable activity history, access trails, and authentication events.', TRUE, '2026-11-18 22:42:04.317561') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (32, 'users.view', 'users', 'View Users & Staff Accounts', 'استعراض حسابات الكادر والمستخدمين', 'List administrative and medical staff accounts.', FALSE, '2026-11-18 22:42:04.318561') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (33, 'users.manage', 'users', 'Manage User Accounts & Overrides', 'إدارة الحسابات والاستثناءات الشخصية', 'Create, deactivate, assign roles, and configure per-user permission overrides.', TRUE, '2026-11-18 22:42:04.318561') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (34, 'roles.view', 'roles', 'View Roles & Access Matrices', 'استعراض الأدوار ومصفوفة الصلاحيات', 'View configured roles and active permission mappings.', FALSE, '2026-11-18 22:42:04.319562') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (35, 'roles.manage', 'roles', 'Manage Roles & Edit Permissions', 'إدارة الأدوار وتعديل الصلاحيات', 'Create custom roles, edit role-permission mappings, and configure access policies.', TRUE, '2026-11-18 22:42:04.319562') ON CONFLICT DO NOTHING;
INSERT INTO permissions (id, "key", "group", label_en, label_ar, description, is_sensitive, created_at) VALUES (36, 'settings.manage', 'settings', 'Manage System Configuration', 'إدارة إعدادات النظام', 'Configure hospital operational buffers, timezone, and global settings.', TRUE, '2026-11-18 22:42:04.319562') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('permissions', 'id'), COALESCE((SELECT MAX(id) FROM permissions), 1));

-- Seed data for role_permissions (111 records)
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 22) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 24) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 11) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 33) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 31) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 9) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 34) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 32) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 15) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 25) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 35) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 13) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 26) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 18) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 4) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 30) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 7) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 36) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (1, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 24) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 11) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 31) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 32) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 34) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 9) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 15) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 25) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 13) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 26) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 18) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 30) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (2, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 4) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 16) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 22) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (3, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 23) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 5) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 6) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 21) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 27) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (4, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 3) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 8) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 14) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 1) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 19) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 28) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 20) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 10) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 17) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 29) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 12) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 2) ON CONFLICT DO NOTHING;
INSERT INTO role_permissions (role_id, permission_id) VALUES (5, 25) ON CONFLICT DO NOTHING;

-- Seed data for doctors (8 records)
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (1, 'Dr. Sarah Mitchell', 'Cardiology', 1, 12, '08:00', '16:00', '2026-11-18 22:42:04.903535') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (2, 'Dr. James Thornton', 'Cardiology', 1, 10, '09:00', '17:00', '2026-11-18 22:42:04.904536') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (3, 'Dr. Emily Chen', 'Neurology', 2, 8, '08:30', '16:30', '2026-11-18 22:42:04.904536') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (4, 'Dr. Robert Hayes', 'Neurology', 2, 9, '10:00', '18:00', '2026-11-18 22:42:04.905536') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (5, 'Dr. Linda Park', 'Orthopedics', 3, 11, '08:00', '16:00', '2026-11-18 22:42:04.905536') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (6, 'Dr. Ahmed Al-Rashid', 'Pediatrics', 4, 15, '08:00', '17:00', '2026-11-18 22:42:04.906747') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (7, 'Dr. Maria Santos', 'General Surgery', 5, 6, '07:00', '15:00', '2026-11-18 22:42:04.906747') ON CONFLICT DO NOTHING;
INSERT INTO doctors (id, name, specialization, department_id, max_patients_per_day, available_from, available_until, created_at) VALUES (8, 'Dr. Kevin O''Brien', 'General Surgery', 5, 7, '11:00', '19:00', '2026-11-18 22:42:04.907750') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('doctors', 'id'), COALESCE((SELECT MAX(id) FROM doctors), 1));

-- Seed data for rooms (10 records)
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (1, 'C-101', 1, 'consultation', 1, 'available', '2026-11-18 22:42:04.909752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (2, 'C-102', 1, 'consultation', 1, 'available', '2026-11-18 22:42:04.910752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (3, 'N-201', 2, 'consultation', 1, 'available', '2026-11-18 22:42:04.910752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (4, 'N-202', 2, 'icu', 2, 'available', '2026-11-18 22:42:04.911752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (5, 'O-301', 3, 'consultation', 1, 'available', '2026-11-18 22:42:04.911752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (6, 'O-302', 3, 'surgery', 1, 'available', '2026-11-18 22:42:04.911752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (7, 'P-401', 4, 'consultation', 2, 'available', '2026-11-18 22:42:04.911752') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (8, 'P-402', 4, 'ward', 4, 'available', '2026-11-18 22:42:04.913254') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (9, 'S-501', 5, 'surgery', 1, 'available', '2026-11-18 22:42:04.913254') ON CONFLICT DO NOTHING;
INSERT INTO rooms (id, room_number, department_id, room_type, capacity, status, created_at) VALUES (10, 'S-502', 5, 'consultation', 1, 'available', '2026-11-18 22:42:04.913254') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('rooms', 'id'), COALESCE((SELECT MAX(id) FROM rooms), 1));

-- Seed data for beds (9 records)
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (1, 'BED-C101-A', 1, 1, 'vacant', NULL, '', '', '', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (2, 'BED-N202-01', 4, 2, 'occupied', NULL, '', '', 'Monitored neuro-ICU patient', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (3, 'BED-N202-02', 4, 2, 'cleaning', NULL, '', '', 'Under UV-C sterilization', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (4, 'BED-O301-A', 5, 3, 'vacant', NULL, '', '', '', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (5, 'BED-P402-01', 8, 4, 'occupied', NULL, '', '', 'Pediatric observation bed', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (6, 'BED-P402-02', 8, 4, 'vacant', NULL, '', '', '', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (7, 'BED-P402-03', 8, 4, 'reserved', NULL, '', '', 'Reserved for elective surgery recovery', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (8, 'BED-P402-04', 8, 4, 'vacant', NULL, '', '', '', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
INSERT INTO beds (id, bed_number, room_id, department_id, status, patient_id, admission_date, expected_discharge, notes, created_at) VALUES (9, 'BED-S501-A', 9, 5, 'vacant', NULL, '', '', '', '2026-11-18 22:42:04.948323') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('beds', 'id'), COALESCE((SELECT MAX(id) FROM beds), 1));

-- Seed data for equipment (8 records)
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (1, 'Hamilton-C6 ICU Ventilator', 'ventilator', 2, 4, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (2, 'Maquet Servo-u Ventilator', 'ventilator', 4, 8, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (3, 'Siemens Magnetom 3T MRI', 'mri', 2, 3, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (4, 'GE Revolution 256-Slice CT', 'ct_scanner', 5, 9, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (5, 'Philips PageWriter TC70 ECG', 'ecg', 1, 1, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (6, 'Zoll R Series Defibrillator', 'ecg', 4, 7, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (7, 'Stryker Laparoscopy Tower 4K', 'surgical_kit', 5, 9, 'in_use', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
INSERT INTO equipment (id, name, equipment_type, department_id, room_id, status, notes, created_at) VALUES (8, 'Ziehm Vision RFD 3D C-Arm', 'ultrasound', 3, 6, 'available', '', '2026-11-18 22:42:04.943801') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('equipment', 'id'), COALESCE((SELECT MAX(id) FROM equipment), 1));

-- Seed data for users (5 records)
INSERT INTO users (id, username, email, password_hash, role, role_id, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, permissions_version, created_at) VALUES (1, 'admin', 'admin@hospital.org', 'scrypt:32768:8:1$PrfEuNkW69uckYCR$a1b95fb68d5835272a8261162bb8137418102a27aa422e59cc5f3c05630836fc5ab2169db033671459a68e55ec66eecdc05f8a19aa8f65e2c6a2d62dd8ab1e37', 'admin', 1, 'Chief Administrator', NULL, TRUE, TRUE, 0, NULL, 1, '2026-11-18 22:42:04.430075') ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, role_id, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, permissions_version, created_at) VALUES (2, 'manager', 'manager@hospital.org', 'scrypt:32768:8:1$FbjBQ6I3e5c7U9nE$5effae50ed26db8415447409a8a40b8ceb38c55d69d4cd8b8cba34b28a6c83f21bf105575d6107f7a77de8ae8813380ed83d8f423855b84a02f70f65980895a4', 'manager', 2, 'Operations Director', NULL, TRUE, TRUE, 0, NULL, 1, '2026-11-18 22:42:04.530072') ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, role_id, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, permissions_version, created_at) VALUES (3, 'dr_sarah', 's.mitchell@hospital.org', 'scrypt:32768:8:1$J9SZG5irWBk6BIlF$54d992b4bad39820498067b2407606d16ef4bf34ec4f45aceb21c6de8892fcc3939d1e5bae27b83a8c0eaf56a4034d2c1a78d98523d14f3fb4e1cc85986f3b35', 'doctor', 3, 'Dr. Sarah Mitchell', 1, TRUE, TRUE, 0, NULL, 1, '2026-11-18 22:42:04.626827') ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, role_id, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, permissions_version, created_at) VALUES (4, 'receptionist', 'frontdesk@hospital.org', 'scrypt:32768:8:1$LNezv5v2XOVrXFfe$daa8bcb2feec367659750bbbe2dd81deae45fa932e265c67976807ad174ccc03449a873e18368af580e74448f4a3990e2b4a5b31ec6dbdd302ef18a2880c4f21', 'receptionist', 4, 'Front Desk Reception', NULL, TRUE, TRUE, 0, NULL, 1, '2026-11-18 22:42:04.780359') ON CONFLICT DO NOTHING;
INSERT INTO users (id, username, email, password_hash, role, role_id, full_name, doctor_id, must_change_password, is_active, failed_login_attempts, locked_until, permissions_version, created_at) VALUES (5, 'demo_viewer', 'demo@hospital.org', 'scrypt:32768:8:1$Rn5AfmYbdauXXXZ7$a296831514e7cf699861a25368f2c0c376135226ab2b66fd15fc97a5d0abd81a65dd5b2b879e9216a15d914499541c52d1410c23a009ee63ce0a3d9ef01138e1', 'demo_viewer', 5, 'Public Demo Guest (Read-Only)', NULL, TRUE, TRUE, 0, NULL, 1, '2026-11-18 22:42:04.890838') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('users', 'id'), COALESCE((SELECT MAX(id) FROM users), 1));

-- Seed data for patients (20 records)
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (1, 'Alice Johnson', 45, 'Female', 'critical', 'Cardiology', 'Severe acute chest pain radiating to left arm, ST elevation suspected', '2026-11-19', 1, '165/105', 112, 93, 37.1, 0.01, '2026-11-18 22:42:04.940294', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (2, 'Bob Martinez', 62, 'Male', 'urgent', 'Neurology', 'Acute recurring migraine with hemiparesis and visual blur', '2026-11-19', 2, '145/92', 88, 97, 36.9, 0.04, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (3, 'Carol White', 38, 'Female', 'normal', 'Orthopedics', 'Right knee anterior cruciate ligament strain after fall', '2026-11-19', 4, '118/76', 72, 99, 36.8, 0.18, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (4, 'David Brown', 7, 'Male', 'urgent', 'Pediatrics', 'High continuous fever (39.5C) with wheezing and respiratory retractions', '2026-11-19', 2, '100/65', 128, 92, 39.5, 0.01, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (5, 'Emma Davis', 55, 'Female', 'critical', 'General Surgery', 'Acute McBurney point tenderness, suspected perforated appendicitis', '2026-11-19', 1, '138/88', 105, 96, 38.8, 0.01, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (6, 'Frank Wilson', 70, 'Male', 'normal', 'Cardiology', 'Routine annual hypertensive and pacemaker checkup', '2026-11-19', 4, '130/82', 68, 98, 36.7, 0.13, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (7, 'Grace Lee', 29, 'Female', 'low', 'Neurology', 'Occasional mild tension headaches over past 3 months', '2026-11-19', 5, '115/74', 70, 99, 36.6, 0.34, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (8, 'Henry Clark', 48, 'Male', 'urgent', 'Orthopedics', 'Closed displaced radius fracture with neurovascular intact', '2026-11-19', 3, '135/85', 84, 98, 37.0, 0.04, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (9, 'Iris Taylor', 5, 'Female', 'critical', 'Pediatrics', 'Peanut allergen exposure with facial angioedema and stridor', '2026-11-19', 1, '90/58', 135, 91, 37.2, 0.01, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (10, 'James Anderson', 33, 'Male', 'normal', 'General Surgery', 'Reducible right inguinal hernia consultation', '2026-11-19', 4, '122/78', 74, 99, 36.7, 0.18, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (11, 'Karen Thompson', 52, 'Female', 'urgent', 'Cardiology', 'Hypertensive crisis (185/110) with occipital pressure', '2026-11-19', 2, '185/110', 96, 96, 37.0, 0.04, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (12, 'Liam Robinson', 11, 'Male', 'normal', 'Pediatrics', 'Routine school physical and booster immunization', '2026-11-19', 5, '105/68', 78, 99, 36.8, 0.13, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (13, 'Mia Harris', 65, 'Female', 'low', 'Orthopedics', 'Bilateral knee osteoarthritis conservative management review', '2026-11-19', 5, '128/80', 66, 98, 36.6, 0.29, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (14, 'Noah Jackson', 41, 'Male', 'critical', 'Neurology', 'Sudden onset facial droop and right arm pronator drift (<2 hrs)', '2026-11-19', 1, '160/95', 102, 95, 37.3, 0.01, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (15, 'Olivia Martin', 27, 'Female', 'normal', 'General Surgery', 'Symptomatic cholelithiasis for elective laparoscopic cholecystectomy', '2026-11-19', 4, '116/74', 76, 99, 36.9, 0.26, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (16, 'Peter Garcia', 58, 'Male', 'urgent', 'Cardiology', 'Post-coronary stenting 30-day review with peripheral edema', '2026-11-19', 3, '142/90', 82, 96, 36.8, 0.04, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (17, 'Quinn Roberts', 19, 'Female', 'low', 'General Surgery', 'Sebaceous cyst removal on back, non-infected', '2026-11-19', 5, '112/70', 72, 100, 36.5, 0.42, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (18, 'Ryan Lewis', 44, 'Male', 'normal', 'Neurology', 'Cervical radiculopathy with numbness in C6 dermatome', '2026-11-19', 4, '124/80', 75, 98, 36.7, 0.18, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (19, 'Sophia Walker', 3, 'Female', 'urgent', 'Pediatrics', 'Acute gastroenteritis with moderate dehydration and lethargy', '2026-11-19', 2, '88/54', 125, 95, 38.4, 0.01, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
INSERT INTO patients (id, name, age, gender, priority, required_specialization, condition_description, preferred_date, triage_level, blood_pressure, heart_rate, spo2, temperature, no_show_risk, registered_at, created_at) VALUES (20, 'Tyler Young', 36, 'Male', 'normal', 'Orthopedics', 'Chronic lumbar disc L5-S1 herniation follow-up', '2026-11-19', 4, '120/78', 70, 99, 36.6, 0.18, '2026-11-18 22:42:04.941293', '2026-11-18 22:42:04.947322') ON CONFLICT DO NOTHING;
SELECT setval(pg_get_serial_sequence('patients', 'id'), COALESCE((SELECT MAX(id) FROM patients), 1));
-- 4. Enable Row Level Security (RLS) & Shield Public PostgREST API
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

-- Revoke PostgREST direct access on public tables so only the Flask backend can access them
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon, authenticated;

COMMIT;

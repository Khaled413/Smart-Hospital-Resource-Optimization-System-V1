"""
permissions.py - Central Permission Registry and Catalog for MediOptim Pro
Defines the authoritative permissions taxonomy, resource groups, bilingual metadata,
and sensitivity classifications for dynamic, database-driven RBAC.
"""

from dataclasses import dataclass
from typing import Dict, List, Optional


@dataclass(frozen=True)
class PermissionDefinition:
    key: str
    group: str
    label_en: str
    label_ar: str
    description: str
    is_sensitive: bool = False


# Resource Groups with bilingual metadata
PERMISSION_GROUPS: Dict[str, Dict[str, str]] = {
    'dashboard': {
        'en': 'Dashboard & Overview',
        'ar': 'لوحة المعلومات والمؤشرات'
    },
    'patients': {
        'en': 'Patient Management',
        'ar': 'إدارة المرضى والسجلات'
    },
    'doctors': {
        'en': 'Physicians & Doctors',
        'ar': 'الأطباء والكوادر الطبية'
    },
    'rooms': {
        'en': 'Rooms & Operating Theaters',
        'ar': 'الغرف والعمليات'
    },
    'departments': {
        'en': 'Hospital Departments',
        'ar': 'أقسام المستشفى'
    },
    'beds': {
        'en': 'Inpatient Beds & Wards',
        'ar': 'الأسرّة والأجنحة'
    },
    'equipment': {
        'en': 'Medical Devices & Equipment',
        'ar': 'الأجهزة والمعدات الطبية'
    },
    'appointments': {
        'en': 'Consultations & Scheduling',
        'ar': 'المواعيد والعيادات'
    },
    'optimization': {
        'en': 'AI Operations Research & Optimizer',
        'ar': 'محرك التحسين والذكاء الاصطناعي'
    },
    'simulation': {
        'en': 'Crisis & Surge Simulator',
        'ar': 'محاكي الأزمات والطوارئ'
    },
    'emergency': {
        'en': 'Emergency Code Red Actions',
        'ar': 'طوارئ كود رد والاستباق'
    },
    'analytics': {
        'en': 'Clinical Telemetry & Analytics',
        'ar': 'التحليلات والتقارير المتقدمة'
    },
    'queue_display': {
        'en': 'Public Displays & Waiting Monitors',
        'ar': 'شاشات الانتظار العامة'
    },
    'export': {
        'en': 'Data Export & Reports',
        'ar': 'تصدير البيانات والملفات'
    },
    'audit': {
        'en': 'Security & Audit Logging',
        'ar': 'سجلات التدقيق والأمان'
    },
    'users': {
        'en': 'User Accounts & Access',
        'ar': 'المستخدمين والحسابات'
    },
    'roles': {
        'en': 'Role & Permission Management',
        'ar': 'الأدوار والصلاحيات'
    },
    'settings': {
        'en': 'System Settings & Config',
        'ar': 'إعدادات النظام'
    }
}


# The authoritative permission catalog
PERMISSION_CATALOG: List[PermissionDefinition] = [
    # Dashboard
    PermissionDefinition(
        key='dashboard.view',
        group='dashboard',
        label_en='View Operations Dashboard',
        label_ar='عرض لوحة العمليات الرئيسية',
        description='Access hospital operations summary, beds occupancy, and live telemetry.',
        is_sensitive=False
    ),

    # Patients
    PermissionDefinition(
        key='patients.view',
        group='patients',
        label_en='View Patients Directory',
        label_ar='استعراض دليل المرضى',
        description='View patient registry and basic demographic records.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='patients.view_all',
        group='patients',
        label_en='View All Patients (Hospital-Wide)',
        label_ar='عرض جميع مرضى المستشفى',
        description='View patient records across all hospital departments beyond own assignments.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='patients.view_clinical',
        group='patients',
        label_en='View Sensitive Clinical Details',
        label_ar='الاطلاع على البيانات السريرية الحساسة',
        description='Access detailed vital signs, clinical conditions, notes, and medical diagnoses.',
        is_sensitive=True
    ),
    PermissionDefinition(
        key='patients.create',
        group='patients',
        label_en='Register New Patient',
        label_ar='تسجيل مريض جديد',
        description='Create and register new patient files in the clinic registry.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='patients.update',
        group='patients',
        label_en='Update Patient Information',
        label_ar='تعديل بيانات المريض',
        description='Edit patient demographic details and contact preferences.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='patients.delete',
        group='patients',
        label_en='Delete Patient Records',
        label_ar='حذف سجلات المرضى',
        description='Permanently remove patient files and medical entries.',
        is_sensitive=True
    ),

    # Doctors
    PermissionDefinition(
        key='doctors.view',
        group='doctors',
        label_en='View Physicians Directory',
        label_ar='استعراض الأطباء والعيادات',
        description='View doctor profiles, specializations, and working hours.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='doctors.manage',
        group='doctors',
        label_en='Manage Doctors & Quotas',
        label_ar='إدارة الأطباء وساعات العمل والكوتا',
        description='Add, modify or deactivate doctors, shift windows, and consultation limits.',
        is_sensitive=True
    ),

    # Rooms
    PermissionDefinition(
        key='rooms.view',
        group='rooms',
        label_en='View Clinic Rooms & Theaters',
        label_ar='استعراض الغرف وغرف العمليات',
        description='View room inventory, department mappings, and statuses.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='rooms.manage',
        group='rooms',
        label_en='Manage Rooms & Facilities',
        label_ar='إدارة الغرف والمرافق',
        description='Add, modify or decommission clinic rooms, surgery suites, and beds capacity.',
        is_sensitive=True
    ),

    # Departments
    PermissionDefinition(
        key='departments.view',
        group='departments',
        label_en='View Departments',
        label_ar='استعراض الأقسام الطبية',
        description='View department list and capacity metrics.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='departments.manage',
        group='departments',
        label_en='Manage Departments',
        label_ar='إدارة الأقسام والخدمات',
        description='Create or update hospital departments and operational descriptions.',
        is_sensitive=True
    ),

    # Inpatient Beds
    PermissionDefinition(
        key='beds.view',
        group='beds',
        label_en='View Bed Matrix',
        label_ar='استعراض مصفوفة الأسرّة',
        description='View ward beds, room allocation, and occupancy states.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='beds.manage',
        group='beds',
        label_en='Manage Bed Infrastructure',
        label_ar='إدارة بنية الأسرّة',
        description='Add, edit or retire inpatient bed assets across wards.',
        is_sensitive=True
    ),
    PermissionDefinition(
        key='beds.admit_discharge',
        group='beds',
        label_en='Admit & Discharge Patients',
        label_ar='تسكين وإخراج المرضى من الأسرّة',
        description='Execute patient bed admissions, transfers, and sanitization discharges.',
        is_sensitive=False
    ),

    # Equipment
    PermissionDefinition(
        key='equipment.view',
        group='equipment',
        label_en='View Medical Equipment Inventory',
        label_ar='استعراض الأجهزة الطبية',
        description='View ventilators, scanners, and monitoring devices.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='equipment.manage',
        group='equipment',
        label_en='Manage Equipment Fleet',
        label_ar='إدارة أسطول الأجهزة والصيانة',
        description='Register devices, assign to rooms, and update maintenance states.',
        is_sensitive=True
    ),

    # Appointments
    PermissionDefinition(
        key='appointments.view',
        group='appointments',
        label_en='View Appointments',
        label_ar='استعراض المواعيد والجدول',
        description='Access appointments schedule and timeline.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='appointments.view_all',
        group='appointments',
        label_en='View All Physicians Appointments',
        label_ar='استعراض مواعيد كافة الأطباء',
        description='View schedules across all hospital doctors beyond own appointments.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='appointments.update_status',
        group='appointments',
        label_en='Update Appointment Status',
        label_ar='تحديث حالة الموعد',
        description='Progress consultation states (in_progress, completed, cancelled, no_show).',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='appointments.edit_clinical_notes',
        group='appointments',
        label_en='Edit Clinical Notes & Prescriptions',
        label_ar='تحرير الملاحظات الطبية والروشتات',
        description='Record medical diagnosis notes and pharmacy prescriptions for visits.',
        is_sensitive=True
    ),
    PermissionDefinition(
        key='appointments.cancel',
        group='appointments',
        label_en='Cancel Consultations',
        label_ar='إلغاء المواعيد المجدولة',
        description='Cancel scheduled appointments with automatic room freeing.',
        is_sensitive=False
    ),

    # AI Optimization
    PermissionDefinition(
        key='optimization.run',
        group='optimization',
        label_en='Execute AI Optimization',
        label_ar='تشغيل خوارزميات الجدولة الذكية',
        description='Trigger Mixed-Integer LP and Hybrid optimization scheduling runs.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='optimization.history.view',
        group='optimization',
        label_en='View Optimization Run History',
        label_ar='عرض سجل وتيليمتري المحسن',
        description='Review mathematical solver telemetry, logs, and historical convergence.',
        is_sensitive=False
    ),

    # Crisis Simulation
    PermissionDefinition(
        key='simulation.run',
        group='simulation',
        label_en='Execute Crisis Stress Simulator',
        label_ar='تشغيل محاكي الأزمات والضغط',
        description='Simulate epidemic surges, doctor outages, and decontamination stress.',
        is_sensitive=False
    ),

    # Emergency Code Red
    PermissionDefinition(
        key='emergency.trigger',
        group='emergency',
        label_en='Trigger Code Red Emergency Preemption',
        label_ar='تفعيل طوارئ كود رد واستباق المواعيد',
        description='Admit critical acute walk-in patients with automated slot preemption.',
        is_sensitive=True
    ),

    # Analytics & Telemetry
    PermissionDefinition(
        key='analytics.view',
        group='analytics',
        label_en='View Clinical Analytics',
        label_ar='استعراض التحليلات ومؤشرات الأداء',
        description='Analyze capacity utilization, throughput, and triage breakdowns.',
        is_sensitive=False
    ),

    # Public Displays
    PermissionDefinition(
        key='queue_display.view',
        group='queue_display',
        label_en='Access Waiting Hall Display',
        label_ar='عرض شاشة صالة الانتظار العامة',
        description='Open full-screen clinic patient calling monitor.',
        is_sensitive=False
    ),

    # Data Export
    PermissionDefinition(
        key='export.csv',
        group='export',
        label_en='Export Hospital Data (CSV)',
        label_ar='تصدير البيانات وتقارير CSV',
        description='Export sanitized patient schedules and clinical records to CSV.',
        is_sensitive=True
    ),

    # Security & Audit
    PermissionDefinition(
        key='audit.view',
        group='audit',
        label_en='View Audit Logs',
        label_ar='الاطلاع على سجلات التدقيق الأمني',
        description='Inspect immutable activity history, access trails, and authentication events.',
        is_sensitive=True
    ),

    # User Accounts
    PermissionDefinition(
        key='users.view',
        group='users',
        label_en='View Users & Staff Accounts',
        label_ar='استعراض حسابات الكادر والمستخدمين',
        description='List administrative and medical staff accounts.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='users.manage',
        group='users',
        label_en='Manage User Accounts & Overrides',
        label_ar='إدارة الحسابات والاستثناءات الشخصية',
        description='Create, deactivate, assign roles, and configure per-user permission overrides.',
        is_sensitive=True
    ),

    # Roles & Permissions (Dynamic RBAC)
    PermissionDefinition(
        key='roles.view',
        group='roles',
        label_en='View Roles & Access Matrices',
        label_ar='استعراض الأدوار ومصفوفة الصلاحيات',
        description='View configured roles and active permission mappings.',
        is_sensitive=False
    ),
    PermissionDefinition(
        key='roles.manage',
        group='roles',
        label_en='Manage Roles & Edit Permissions',
        label_ar='إدارة الأدوار وتعديل الصلاحيات',
        description='Create custom roles, edit role-permission mappings, and configure access policies.',
        is_sensitive=True
    ),

    # Settings
    PermissionDefinition(
        key='settings.manage',
        group='settings',
        label_en='Manage System Configuration',
        label_ar='إدارة إعدادات النظام',
        description='Configure hospital operational buffers, timezone, and global settings.',
        is_sensitive=True
    )
]

# Lookup dictionary by key
PERMISSION_MAP: Dict[str, PermissionDefinition] = {p.key: p for p in PERMISSION_CATALOG}

# Default system role permission allocations
DEFAULT_ROLE_PERMISSIONS: Dict[str, List[str]] = {
    'admin': [p.key for p in PERMISSION_CATALOG],
    'manager': [
        'dashboard.view',
        'patients.view', 'patients.view_all', 'patients.create', 'patients.update',
        'doctors.view', 'doctors.manage',
        'rooms.view', 'rooms.manage',
        'departments.view', 'departments.manage',
        'beds.view', 'beds.manage', 'beds.admit_discharge',
        'equipment.view', 'equipment.manage',
        'appointments.view', 'appointments.view_all', 'appointments.update_status', 'appointments.cancel',
        'optimization.run', 'optimization.history.view',
        'simulation.run',
        'emergency.trigger',
        'analytics.view',
        'queue_display.view',
        'export.csv',
        'audit.view',
        'users.view',
        'roles.view'
    ],
    'doctor': [
        'dashboard.view',
        'patients.view', 'patients.view_clinical', 'patients.create', 'patients.update',
        'doctors.view',
        'rooms.view',
        'departments.view',
        'beds.view', 'beds.admit_discharge',
        'equipment.view',
        'appointments.view', 'appointments.update_status', 'appointments.edit_clinical_notes',
        'emergency.trigger',
        'analytics.view',
        'queue_display.view'
    ],
    'receptionist': [
        'dashboard.view',
        'patients.view', 'patients.view_all', 'patients.create', 'patients.update',
        'doctors.view',
        'rooms.view',
        'departments.view',
        'beds.view',
        'appointments.view', 'appointments.view_all', 'appointments.cancel', 'appointments.update_status',
        'emergency.trigger',
        'queue_display.view'
    ],
    'demo_viewer': [
        'dashboard.view',
        'patients.view', 'patients.view_all',
        'doctors.view',
        'rooms.view',
        'departments.view',
        'beds.view',
        'equipment.view',
        'appointments.view', 'appointments.view_all',
        'optimization.history.view',
        'analytics.view',
        'queue_display.view'
    ]
}


def get_permission(key: str) -> Optional[PermissionDefinition]:
    """Retrieve permission definition by key."""
    return PERMISSION_MAP.get(key)


def get_all_permissions() -> List[PermissionDefinition]:
    """Retrieve full permission catalog."""
    return list(PERMISSION_CATALOG)


def get_permissions_by_group() -> Dict[str, List[PermissionDefinition]]:
    """Group permissions by functional resource area."""
    grouped: Dict[str, List[PermissionDefinition]] = {}
    for p in PERMISSION_CATALOG:
        grouped.setdefault(p.group, []).append(p)
    return grouped

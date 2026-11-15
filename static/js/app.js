/* ============================================================
   app.js - Enhanced JavaScript Utilities & Localization
   MediOptim Pro - Smart Hospital Resource Optimization System
   ============================================================ */

// ── Toast Notifications ──────────────────────────────────────
const ToastManager = {
  container: null,

  init() {
    this.container = document.getElementById('toast-container');
    if (!this.container) {
      this.container = document.createElement('div');
      this.container.className = 'toast-container';
      this.container.id = 'toast-container';
      document.body.appendChild(this.container);
    }
  },

  show(message, type = 'info', duration = 3500) {
    const icons = { success: '✅', error: '❌', warning: '⚠️', info: 'ℹ️' };
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<span>${icons[type] || 'ℹ️'}</span><span>${message}</span>`;
    this.container.appendChild(toast);
    setTimeout(() => {
      toast.style.animation = 'none';
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(30px)';
      toast.style.transition = 'all 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, duration);
  }
};

// ── Spinner ───────────────────────────────────────────────────
const Spinner = {
  show(msg = 'Processing...') {
    let el = document.getElementById('spinner-overlay');
    if (!el) {
      el = document.createElement('div');
      el.id = 'spinner-overlay';
      el.className = 'spinner-overlay';
      el.innerHTML = `<div class="spinner"></div><div class="spinner-text">${msg}</div>`;
      document.body.appendChild(el);
    } else {
      el.querySelector('.spinner-text').textContent = msg;
    }
    el.classList.add('active');
  },
  hide() {
    const el = document.getElementById('spinner-overlay');
    if (el) el.classList.remove('active');
  }
};

// ── CSRF Token Helper ─────────────────────────────────────────
function getCsrfToken() {
  const match = document.cookie.match(/csrf_token=([^;]+)/);
  if (match) return decodeURIComponent(match[1]);
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute('content') : '';
}

// ── API Helper ────────────────────────────────────────────────
const API = {
  getHeaders() {
    const headers = { 'Content-Type': 'application/json' };
    const csrf = getCsrfToken();
    if (csrf) headers['X-CSRF-Token'] = csrf;
    return headers;
  },
  async get(url) {
    const res = await fetch(url);
    if (!res.ok) {
      if (res.status === 401 && !url.includes('/api/auth/me')) {
        window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
      }
      throw new Error(`GET ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async post(url, data) {
    const res = await fetch(url, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify(data)
    });
    if (!res.ok) {
      if (res.status === 401 && !url.includes('/api/auth/login')) {
        window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
      }
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || err.message || `POST ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async put(url, data) {
    const res = await fetch(url, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify(data)
    });
    if (!res.ok) {
      if (res.status === 401) {
        window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
      }
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `PUT ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async delete(url) {
    const res = await fetch(url, {
      method: 'DELETE',
      headers: this.getHeaders()
    });
    if (!res.ok) {
      if (res.status === 401) {
        window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
      }
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `DELETE ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async patch(url, data) {
    const res = await fetch(url, {
      method: 'PATCH',
      headers: this.getHeaders(),
      body: JSON.stringify(data)
    });
    if (!res.ok) {
      if (res.status === 401) {
        window.location.href = '/login?next=' + encodeURIComponent(window.location.pathname);
      }
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `PATCH ${url} failed: ${res.status}`);
    }
    return res.json();
  }
};

// ── Modal Helper ──────────────────────────────────────────────
const Modal = {
  open(id) {
    const el = document.getElementById(id);
    if (el) {
      el.classList.add('active');
      initPasswordToggles();
    }
  },
  close(id) {
    const el = document.getElementById(id);
    if (el) el.classList.remove('active');
  },
  closeAll() {
    document.querySelectorAll('.modal-overlay.active').forEach(m => m.classList.remove('active'));
  }
};

// ── Time & Date Helpers ───────────────────────────────────────
function timeToMinutes(t) {
  if (!t) return 0;
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}

function minutesToTime(m) {
  const h = Math.floor(m / 60);
  const min = m % 60;
  return `${h.toString().padStart(2, '0')}:${min.toString().padStart(2, '0')}`;
}

function todayISO() {
  return new Date().toISOString().split('T')[0];
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatTime(t) {
  if (!t) return '—';
  const [h, m] = t.split(':');
  const hour = parseInt(h);
  return `${hour > 12 ? hour - 12 : (hour === 0 ? 12 : hour)}:${m} ${hour >= 12 ? 'PM' : 'AM'}`;
}

// ── Badge Helpers ─────────────────────────────────────────────
function priorityBadge(priority) {
  const map = { critical: '🔴 Critical', urgent: '🟠 Urgent', normal: '🟢 Normal', low: '⚪ Low' };
  return `<span class="badge badge-${priority}">${map[priority] || priority}</span>`;
}

function statusBadge(status) {
  const map = {
    scheduled: '📅 Scheduled',
    in_progress: '⚡ In Progress',
    completed: '✅ Completed',
    cancelled: '❌ Cancelled',
    no_show: '⚠️ No-Show',
    success: '✅ Success',
    partial: '⚠️ Partial',
    failed: '❌ Failed'
  };
  return `<span class="badge badge-${status}">${map[status] || status}</span>`;
}

function algoBadge(algo) {
  const map = { lp: '🔢 Linear Programming', greedy: '⚡ Greedy', hybrid: '🔀 Hybrid' };
  return `<span class="badge badge-${algo}">${map[algo] || algo}</span>`;
}

// ── Active Navigation ─────────────────────────────────────────
function setActiveSidebarLink() {
  const path = window.location.pathname;
  document.querySelectorAll('.nav-item').forEach(item => {
    item.classList.remove('active');
    const href = item.getAttribute('href');
    if (href && (path === href || (href !== '/' && path.startsWith(href)))) {
      item.classList.add('active');
    }
  });
  if (path === '/') {
    const dash = document.querySelector('.nav-item[href="/"]');
    if (dash) dash.classList.add('active');
  }
}

// ── Emergency Code Red Modal & Handler ────────────────────────
function openEmergencyModal() {
  Modal.open('emergency-modal');
}

async function submitEmergencyWalkin(e) {
  e.preventDefault();
  const btn = document.getElementById('em-submit-btn');
  btn.disabled = true;
  btn.textContent = '⚡ Admitting Code Red...';

  const payload = {
    name: document.getElementById('em-name').value,
    age: document.getElementById('em-age').value,
    gender: document.getElementById('em-gender').value,
    required_specialization: document.getElementById('em-spec').value,
    condition_description: document.getElementById('em-condition').value,
    blood_pressure: document.getElementById('em-bp').value,
    heart_rate: document.getElementById('em-hr').value,
    spo2: document.getElementById('em-spo2').value,
    temperature: document.getElementById('em-temp').value
  };

  try {
    const res = await API.post('/api/emergency/walkin', payload);
    Modal.close('emergency-modal');
    ToastManager.show(`🚨 Code Red Admitted: Assigned to Dr. ${res.emergency_appointment.doctor_name} in Room ${res.emergency_appointment.room_number}`, 'success', 5000);
    if (res.bumped_notice) {
      setTimeout(() => {
        ToastManager.show(`⚠️ ${res.bumped_notice}`, 'warning', 6000);
      }, 1200);
    }
    // Refresh table or page if function exists
    if (typeof loadAppts === 'function') loadAppts();
    if (typeof loadDashboard === 'function') loadDashboard();
  } catch(err) {
    ToastManager.show(err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = '⚡ Execute Emergency Admission';
  }
}

// ── Auth Status Check & Dynamic Permission Gating ─────────────
window.currentUser = null;
window.currentUserPermissions = new Set();

window.can = function(permissionKey) {
  if (!window.currentUserPermissions) return false;
  return window.currentUserPermissions.has(permissionKey);
};

function applyPermissionGating() {
  document.querySelectorAll('[data-perm]').forEach(el => {
    const requiredPerm = el.getAttribute('data-perm');
    if (requiredPerm && !window.can(requiredPerm)) {
      el.style.display = 'none';
      if (el.tagName === 'BUTTON' || el.tagName === 'INPUT') {
        el.disabled = true;
      }
    }
  });
}

async function checkAuthStatus() {
  const container = document.getElementById('auth-status-container');

  try {
    const res = await API.get('/api/auth/me');
    if (res.authenticated && res.user) {
      const u = res.user;
      window.currentUser = u;
      window.currentUserPermissions = new Set(res.permissions || []);
      applyPermissionGating();

      if (container) {
        container.innerHTML = `
          <div style="display:flex;align-items:center;gap:6px;background:#f1f5f9;border:1px solid #e2e8f0;padding:3px 8px 3px 12px;border-radius:20px;font-size:12px">
            <a href="/profile" style="display:flex;align-items:center;gap:6px;text-decoration:none;color:inherit;" title="Profile Settings & Account">
              <span>👤</span>
              <span style="font-weight:600;color:var(--text-primary)">${u.full_name}</span>
              <span class="badge" style="background:#0284c7;color:#fff;font-size:10px;padding:2px 6px">${u.role.toUpperCase()}</span>
            </a>
            <a href="/profile" style="color:#64748b;text-decoration:none;font-size:13px;padding:2px 4px" title="Profile Settings">⚙️</a>
            <button onclick="logoutUser()" style="background:none;border:none;color:#ef4444;cursor:pointer;font-size:13px;padding:2px 4px;line-height:1;" title="Sign Out">✕</button>
          </div>
        `;
      }
    } else {
      window.currentUser = null;
      window.currentUserPermissions = new Set();
      applyPermissionGating();
      if (container) {
        container.innerHTML = `
          <a href="/login" class="btn btn-outline btn-sm" style="font-size:11px;padding:4px 10px">
            🔑 Sign In
          </a>
        `;
      }
    }
  } catch(e) {
    console.error('Auth check error', e);
  }
}

async function logoutUser() {
  try {
    await API.post('/api/auth/logout', {});
    ToastManager.show('Logged out successfully', 'info');
    setTimeout(() => { window.location.href = '/login'; }, 400);
  } catch(err) {
    console.error(err);
  }
}

// ── Bilingual Localization Dictionary (English / Arabic RTL) ─
const TRANSLATIONS = {
  en: {
    app_sub: 'Smart Hospital System',
    nav_overview: 'Overview',
    nav_dashboard: 'Dashboard',
    nav_analytics: 'Analytics',
    nav_resources: 'Resources',
    nav_patients: 'Patients',
    nav_doctors: 'Doctors',
    nav_rooms: 'Rooms',
    nav_beds: 'Inpatient Beds',
    nav_equipment: 'Equipment',
    nav_departments: 'Departments',
    nav_scheduling: 'Scheduling & AI',
    nav_appointments: 'Appointments & Timeline',
    nav_optimize: 'AI Optimization',
    nav_simulator: 'Crisis Simulator',
    nav_history: 'Run History',
    nav_access_control: 'Access Control',
    nav_roles: 'Roles & Permissions',
    nav_users: 'Staff & Users',
    nav_display: 'Waiting Hall Monitor',
    nav_account: 'Account & Settings',
    nav_profile: 'Profile Settings',
    profile_title: 'Profile Settings',
    profile_subtitle: 'Manage your personal information, credentials, and review assigned permissions',
    save_changes: 'Save Profile Changes',
    btn_emergency: 'Code Red Walk-In',
    emergency_modal_title: 'Emergency Code Red Walk-In',
    patient_name: 'Patient Name *',
    patient_age: 'Age *',
    patient_gender: 'Gender *',
    specialization: 'Required Specialization *',
    emergency_condition: 'Emergency Condition / Symptoms *',
    export_csv: 'Export CSV'
  },
  ar: {
    app_sub: 'نظام إدارة المستشفيات الذكي',
    nav_overview: 'نظرة عامة',
    nav_dashboard: 'لوحة التحكم الرئيسية',
    nav_analytics: 'التحليلات والمؤشرات',
    nav_resources: 'الموارد الطبية',
    nav_patients: 'دليل المرضى',
    nav_doctors: 'الأطباء والعيادات',
    nav_rooms: 'الغرف والعمليات',
    nav_beds: 'أسرّة التنويم',
    nav_equipment: 'الأجهزة الطبية',
    nav_departments: 'الأقسام التخصصية',
    nav_scheduling: 'الجدولة والذكاء الاصطناعي',
    nav_appointments: 'المواعيد والمخطط الزمني',
    nav_optimize: 'خوارزميات التحسين',
    nav_simulator: 'محاكي الأزمات',
    nav_history: 'سجل العمليات',
    nav_access_control: 'الأدوار والصلاحيات',
    nav_roles: 'الأدوار ومصفوفة الصلاحيات',
    nav_users: 'الكادر والمستخدمين',
    nav_display: 'شاشة صالة الانتظار',
    nav_account: 'الحساب والإعدادات',
    nav_profile: 'إعدادات البروفايل',
    profile_title: 'إعدادات الملف الشخصي',
    profile_subtitle: 'إدارة البيانات الشخصية وتحديث كلمة المرور واستعراض الصلاحيات',
    save_changes: 'حفظ التعديلات',
    btn_emergency: 'طوارئ كود أحمر',
    emergency_modal_title: 'تسجيل حالة طوارئ حرجة (كود أحمر)',
    patient_name: 'اسم المريض *',
    patient_age: 'العمر *',
    patient_gender: 'الجنس *',
    specialization: 'التخصص المطلوب *',
    emergency_condition: 'الأعراض والحالة الطارئة *',
    export_csv: 'تصدير كملف CSV'
  }
};

let currentLang = localStorage.getItem('preferred_lang') || 'en';

function applyLanguage(lang) {
  currentLang = lang;
  localStorage.setItem('preferred_lang', lang);

  const dict = TRANSLATIONS[lang] || TRANSLATIONS.en;
  if (lang === 'ar') {
    document.body.classList.add('rtl');
    document.documentElement.setAttribute('dir', 'rtl');
    document.documentElement.setAttribute('lang', 'ar');
    const label = document.getElementById('lang-label');
    if (label) label.textContent = 'English';
  } else {
    document.body.classList.remove('rtl');
    document.documentElement.setAttribute('dir', 'ltr');
    document.documentElement.setAttribute('lang', 'en');
    const label = document.getElementById('lang-label');
    if (label) label.textContent = 'عربي';
  }

  // Translate all matching data-i18n elements
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (dict[key]) el.textContent = dict[key];
  });
}

function toggleLanguage() {
  const next = currentLang === 'en' ? 'ar' : 'en';
  applyLanguage(next);
}

// ── Mobile Responsive Sidebar Drawer ─────────────────────────
function toggleMobileSidebar() {
  const sidebar = document.getElementById('sidebar');
  const backdrop = document.getElementById('sidebar-backdrop');
  if (!sidebar) return;
  const isOpen = sidebar.classList.toggle('mobile-open');
  if (backdrop) {
    if (isOpen) backdrop.classList.add('active');
    else backdrop.classList.remove('active');
  }
}

// ── Official Clinical Light Theme (Exclusively Enforced) ──────
// Dark mode has been eliminated in favor of official Hospital Clinical Light
function toggleTheme() {
  // Maintained as graceful no-op if invoked
}

function initTheme() {
  localStorage.removeItem('preferred_theme');
}

// ── Password Visibility Toggle Helper ──────────────────────────
const PasswordToggleIcons = {
  eye: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"></path><circle cx="12" cy="12" r="3"></circle></svg>`,
  eyeOff: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"></path><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"></path><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"></path><line x1="2" x2="22" y1="2" y2="22"></line></svg>`
};

function togglePasswordVisibility(inputOrId, btn) {
  const input = typeof inputOrId === 'string' ? document.getElementById(inputOrId) : inputOrId;
  if (!input) return;
  const isNowText = input.type === 'password';
  input.type = isNowText ? 'text' : 'password';
  if (btn) {
    btn.innerHTML = isNowText ? PasswordToggleIcons.eyeOff : PasswordToggleIcons.eye;
    const isArabic = document.documentElement.getAttribute('dir') === 'rtl' || (typeof currentLang !== 'undefined' && currentLang === 'ar');
    const label = isNowText ? (isArabic ? 'إخفاء كلمة المرور' : 'Hide password') : (isArabic ? 'إظهار كلمة المرور' : 'Show password');
    btn.setAttribute('aria-label', label);
    btn.setAttribute('title', label);
  }
}

function initPasswordToggles() {
  document.querySelectorAll('.password-toggle-btn').forEach(btn => {
    if (btn._hasPasswordToggle) return;
    btn._hasPasswordToggle = true;

    // Set initial icon if not populated
    if (!btn.innerHTML.trim()) {
      btn.innerHTML = PasswordToggleIcons.eye;
    }

    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const targetId = btn.getAttribute('data-target');
      const input = targetId ? document.getElementById(targetId) : btn.parentElement.querySelector('input');
      if (input) {
        togglePasswordVisibility(input, btn);
      }
    });
  });
}

// ── DOM Ready Initialization ──────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  ToastManager.init();
  setActiveSidebarLink();
  initTheme();
  checkAuthStatus();
  applyLanguage(currentLang);
  initPasswordToggles();

  // Close mobile sidebar upon clicking navigation items
  document.querySelectorAll('.sidebar .nav-item').forEach(link => {
    link.addEventListener('click', () => {
      if (window.innerWidth <= 992) {
        const sidebar = document.getElementById('sidebar');
        const backdrop = document.getElementById('sidebar-backdrop');
        if (sidebar) sidebar.classList.remove('mobile-open');
        if (backdrop) backdrop.classList.remove('active');
      }
    });
  });

  const dateEl = document.getElementById('current-date');
  if (dateEl) {
    dateEl.textContent = new Date().toLocaleDateString('en-US', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    });
  }

  document.querySelectorAll('.modal-overlay').forEach(overlay => {
    overlay.addEventListener('click', e => {
      if (e.target === overlay) overlay.classList.remove('active');
    });
  });
});

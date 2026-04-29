/* ============================================================
   app.js - Core JavaScript Utilities
   Smart Hospital Resource Optimization System
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

// ── API Helper ────────────────────────────────────────────────
const API = {
  async get(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`GET ${url} failed: ${res.status}`);
    return res.json();
  },
  async post(url, data) {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `POST ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async put(url, data) {
    const res = await fetch(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `PUT ${url} failed: ${res.status}`);
    }
    return res.json();
  },
  async delete(url) {
    const res = await fetch(url, { method: 'DELETE' });
    if (!res.ok) throw new Error(`DELETE ${url} failed: ${res.status}`);
    return res.json();
  },
  async patch(url, data) {
    const res = await fetch(url, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (!res.ok) throw new Error(`PATCH ${url} failed: ${res.status}`);
    return res.json();
  }
};

// ── Modal Helper ──────────────────────────────────────────────
const Modal = {
  open(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('active');
  },
  close(id) {
    const el = document.getElementById(id);
    if (el) el.classList.remove('active');
  },
  closeAll() {
    document.querySelectorAll('.modal-overlay.active').forEach(m => m.classList.remove('active'));
  }
};

// ── Badge Helpers ─────────────────────────────────────────────
function priorityBadge(priority) {
  const map = { critical: '🔴 Critical', urgent: '🟠 Urgent', normal: '🟢 Normal', low: '⚪ Low' };
  return `<span class="badge badge-${priority}">${map[priority] || priority}</span>`;
}

function statusBadge(status) {
  const map = { scheduled: '📅 Scheduled', completed: '✅ Completed', cancelled: '❌ Cancelled',
                success: '✅ Success', partial: '⚠️ Partial', failed: '❌ Failed' };
  return `<span class="badge badge-${status}">${map[status] || status}</span>`;
}

function algoBadge(algo) {
  const map = { lp: '🔢 Linear Programming', greedy: '⚡ Greedy', hybrid: '🔀 Hybrid' };
  return `<span class="badge badge-${algo}">${map[algo] || algo}</span>`;
}

// ── Sidebar Active Link ───────────────────────────────────────
function setActiveSidebarLink() {
  const path = window.location.pathname;
  document.querySelectorAll('.nav-item').forEach(item => {
    item.classList.remove('active');
    const href = item.getAttribute('href');
    if (href && (path === href || (href !== '/' && path.startsWith(href)))) {
      item.classList.add('active');
    }
  });
  // Dashboard
  if (path === '/') {
    const dash = document.querySelector('.nav-item[href="/"]');
    if (dash) dash.classList.add('active');
  }
}

// ── Date Helpers ──────────────────────────────────────────────
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
  return `${hour > 12 ? hour - 12 : hour}:${m} ${hour >= 12 ? 'PM' : 'AM'}`;
}

// ── Confirm Dialog ────────────────────────────────────────────
function confirmAction(message, onConfirm) {
  if (confirm(message)) onConfirm();
}

// ── Number Formatter ─────────────────────────────────────────
function fmtNum(n, decimals = 0) {
  return Number(n).toFixed(decimals);
}

// ── Chart Color Palette ───────────────────────────────────────
const CHART_COLORS = {
  primary: '#1a56db',
  accent: '#06b6d4',
  success: '#10b981',
  warning: '#f59e0b',
  danger: '#ef4444',
  info: '#8b5cf6',
  muted: '#64748b'
};

const PRIORITY_COLORS = {
  critical: '#ef4444',
  urgent: '#f59e0b',
  normal: '#10b981',
  low: '#64748b'
};

// ── Init on DOM ready ─────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  ToastManager.init();
  setActiveSidebarLink();

  // Update date display
  const dateEl = document.getElementById('current-date');
  if (dateEl) {
    dateEl.textContent = new Date().toLocaleDateString('en-US', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    });
  }

  // Close modals on overlay click
  document.querySelectorAll('.modal-overlay').forEach(overlay => {
    overlay.addEventListener('click', e => {
      if (e.target === overlay) overlay.classList.remove('active');
    });
  });
});

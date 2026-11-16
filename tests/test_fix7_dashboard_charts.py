"""
test_fix7_dashboard_charts.py - Tests for Dashboard Chart Rendering, Chart.js Inclusion & CSP
"""

import pytest
from app import app
from models import db, User


def test_dashboard_chartjs_inclusion_csp_and_initialization(client):
    """
    Verify dashboard HTML properly includes Chart.js, enforces compliant CSP headers,
    and includes the chart initialization script with defined PRIORITY_COLORS.
    """
    # 1. Log in as admin
    with client.session_transaction() as sess:
        sess['user_id'] = 1
        sess['username'] = 'admin'
        sess['role'] = 'admin'
        sess['is_demo'] = False
        user = db.session.get(User, 1)
        if user:
            import hashlib
            sess['pwd_hash'] = hashlib.sha256(user.password_hash.encode('utf-8')).hexdigest()[:16]

    res = client.get('/')
    assert res.status_code == 200
    html = res.get_data(as_text=True)

    # 2. Check Chart.js CDN script inclusion in HTML
    assert 'chart.umd.min.js' in html or 'chart.js' in html
    assert 'https://cdn.jsdelivr.net' in html

    # 3. Check CSP header allows Chart.js CDN
    csp = res.headers.get('Content-Security-Policy', '')
    assert len(csp) > 0, "Content-Security-Policy header is missing"
    assert "script-src" in csp
    assert "https://cdn.jsdelivr.net" in csp, "CSP must whitelist Chart.js CDN origin https://cdn.jsdelivr.net"

    # 4. Check canvas elements exist in DOM
    assert 'id="priorityChart"' in html
    assert 'id="deptChart"' in html
    assert 'id="doctorChart"' in html

    # 5. Check initialization script and color definitions
    assert 'PRIORITY_COLORS' in html
    assert 'renderCharts' in html
    assert 'loadDashboard' in html
    assert 'Chart.getChart' in html

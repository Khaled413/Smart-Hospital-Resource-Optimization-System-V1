"""
test_fix4_timezone.py - Tests for Africa/Cairo Standard Timezone & Default Date Handling
"""

import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import pytest
from app import app
from models import db, Doctor, Appointment, today_in_app_tz, now_in_app_tz, utc_now, User


def test_today_in_app_tz_matches_africa_cairo():
    """Verify today_in_app_tz computes date string in Africa/Cairo by default."""
    cairo_now = datetime.now(ZoneInfo('Africa/Cairo'))
    expected_cairo_date = cairo_now.strftime('%Y-%m-%d')

    # Default call without arguments
    assert today_in_app_tz() == expected_cairo_date

    # Explicit call with Africa/Cairo
    assert today_in_app_tz('Africa/Cairo') == expected_cairo_date

    # Datetime helper is aware and has Africa/Cairo timezone
    cairo_dt = now_in_app_tz('Africa/Cairo')
    assert cairo_dt.tzinfo is not None
    assert str(cairo_dt.tzinfo) == 'Africa/Cairo'


def test_db_timestamps_remain_utc_aware():
    """Verify database timestamp helper utc_now() returns timezone-aware UTC datetime."""
    now_utc = utc_now()
    assert now_utc.tzinfo is not None
    assert now_utc.tzinfo == timezone.utc


def test_endpoints_default_to_today_in_app_tz(client):
    """Verify API endpoints default to today_in_app_tz() when date argument is omitted."""
    # Authenticate as admin
    with client.session_transaction() as sess:
        sess['user_id'] = 1
        sess['username'] = 'admin'
        sess['role'] = 'admin'
        sess['is_demo'] = False
        user = db.session.get(User, 1)
        if user:
            import hashlib
            sess['pwd_hash'] = hashlib.sha256(user.password_hash.encode('utf-8')).hexdigest()[:16]

    expected_today = today_in_app_tz()

    # 1. /api/analytics/utilization without date param
    res_util = client.get('/api/analytics/utilization')
    assert res_util.status_code == 200

    # 2. Emergency walkin registers for today_in_app_tz()
    res_em = client.post('/api/emergency/walkin', json={
        'name': 'TZ Test Patient',
        'required_specialization': 'Cardiology'
    })
    assert res_em.status_code in (201, 409)
    if res_em.status_code == 201:
        em_data = res_em.get_json()
        assert em_data['emergency_appointment']['date'] == expected_today

        # Clean up test emergency appointment and patient
        with app.app_context():
            appt_id = em_data['emergency_appointment']['id']
            pat_id = em_data['emergency_appointment']['patient_id']
            appt = db.session.get(Appointment, appt_id)
            if appt:
                db.session.delete(appt)
            from models import Patient
            pat = db.session.get(Patient, pat_id)
            if pat:
                db.session.delete(pat)
            db.session.commit()

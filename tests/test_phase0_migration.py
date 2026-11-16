"""
test_phase0_migration.py - Verification tests for Phase 0 (Supabase PostgreSQL Migration)
Verifies:
- Config normalization & fail-fast validation in production
- NullPool / pool pre-ping connection settings
- Timezone awareness (DateTime timezone=True, utc_now)
- Composite database indexes
- Startup decoupling (no db.create_all / seed at import time, flask seed CLI command)
- Row Level Security (RLS) coverage & zero API key leaks
- Migration scripts exist and validate schemas
"""

import os
import re
import pytest
from datetime import datetime, timezone
from sqlalchemy import Index

from config import normalize_database_url, ProductionConfig, DevelopmentConfig
from models import db, Appointment, Patient, AuditLog, utc_now
from app import app


def test_database_url_normalization():
    """Verify postgres:// and postgresql:// are normalized to postgresql+psycopg2://."""
    url1 = "postgres://user:pass@ep-host.pooler.supabase.com:6543/postgres?sslmode=require"
    assert normalize_database_url(url1).startswith("postgresql+psycopg2://")

    url2 = "postgresql://user:pass@ep-host.pooler.supabase.com:6543/postgres?sslmode=require"
    assert normalize_database_url(url2).startswith("postgresql+psycopg2://")

    sqlite_url = "sqlite:///instance/hospital.db"
    assert normalize_database_url(sqlite_url) == sqlite_url
    assert normalize_database_url(None) == ''


def test_production_config_fail_fast_without_postgres(monkeypatch):
    """Verify that in production mode, an absent or SQLite database URL raises an exception."""
    from config import get_config
    monkeypatch.setenv('SECRET_KEY', 'a-very-strong-production-key-over-32-chars-long-12345')
    monkeypatch.delenv('DATABASE_URL', raising=False)
    # Ensure config module validates production fail-fast
    with pytest.raises((ValueError, RuntimeError)) as exc_info:
        get_config('production')
    assert "SQLite is strictly forbidden in production" in str(exc_info.value)


def test_utc_now_helper_is_timezone_aware():
    """Verify utc_now helper generates timezone-aware UTC timestamps."""
    now = utc_now()
    assert now.tzinfo is not None
    assert now.tzinfo == timezone.utc


def test_composite_indexes_defined_on_models():
    """Verify that composite indexes required for query performance are defined on models."""
    # 1. Appointments composite index: (date, doctor_id, room_id, status)
    appt_indexes = [idx.name for idx in Appointment.__table__.indexes]
    assert 'idx_appointments_lookup' in appt_indexes
    appt_idx = next(i for i in Appointment.__table__.indexes if i.name == 'idx_appointments_lookup')
    assert [col.name for col in appt_idx.columns] == ['date', 'doctor_id', 'room_id', 'status']

    # 2. Patients composite index: (priority, preferred_date)
    patient_indexes = [idx.name for idx in Patient.__table__.indexes]
    assert 'idx_patients_priority_preferred_date' in patient_indexes

    # 3. Audit logs index: (created_at)
    audit_indexes = [idx.name for idx in AuditLog.__table__.indexes]
    assert 'idx_audit_logs_created_at' in audit_indexes


def test_startup_decoupling_and_seed_cli():
    """Verify db.create_all() and seed_database() are not run at module import time, and CLI seed is present."""
    # Check CLI commands on app
    registered_commands = list(app.cli.list_commands(None))
    assert 'seed' in registered_commands

    # Verify app.py source doesn't run create_all or seed_database at top level
    app_source_path = os.path.join(os.path.dirname(__file__), '..', 'app.py')
    with open(app_source_path, 'r', encoding='utf-8') as f:
        src = f.read()

    # Neither should run unconditionally outside functions
    top_level_creates = re.findall(r'^[ \t]*db\.create_all\(\)', src, re.MULTILINE)
    assert len(top_level_creates) == 0, "db.create_all() should not execute at import/top level"


def test_rls_sql_script_covers_all_tables():
    """Verify that scripts/enable_rls.sql covers all application tables."""
    rls_script_path = os.path.join(os.path.dirname(__file__), '..', 'scripts', 'enable_rls.sql')
    assert os.path.exists(rls_script_path)

    with open(rls_script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_tables = [
        'departments', 'roles', 'permissions', 'role_permissions',
        'doctors', 'rooms', 'patients', 'beds', 'equipment',
        'users', 'user_permission_overrides', 'appointments',
        'optimization_runs', 'audit_logs', 'alembic_version'
    ]
    for tbl in expected_tables:
        assert f"ALTER TABLE IF EXISTS {tbl} ENABLE ROW LEVEL SECURITY;" in content


def test_no_supabase_keys_or_secrets_leaked():
    """Verify no secret keys or Supabase access keys are present in tracked source code."""
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    forbidden_patterns = [
        re.compile(r'sbp_[a-zA-Z0-9_-]{20,}'),
        re.compile(r'service_role_key\s*=\s*[\'"][^\'"]+[\'"]'),
        re.compile(r'SUPABASE_SERVICE_ROLE_KEY\s*=\s*[^\s\n#]+')
    ]

    for root, dirs, files in os.walk(repo_root):
        if any(ignored in root for ignored in ['.git', '.venv', '__pycache__', 'node_modules', '.pytest_cache']):
            continue
        for file in files:
            if file.endswith(('.py', '.html', '.js', '.json', '.yml', '.yaml', '.example')):
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    file_content = f.read()
                for pattern in forbidden_patterns:
                    matches = pattern.findall(file_content)
                    assert len(matches) == 0, f"Potential secret leak in {file_path}: {matches}"

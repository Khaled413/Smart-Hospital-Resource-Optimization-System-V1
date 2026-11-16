#!/usr/bin/env python3
"""
enable_rls.py - Supabase Row Level Security (RLS) Enforcer & Auditor
Enables RLS with zero policies on all public tables to prevent unauthorized PostgREST API exposure.
Audits the database and returns a non-zero exit code if any public table lacks RLS.
"""

import sys
import os
from sqlalchemy import create_engine, text

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from config import migration_database_url, database_url

TARGET_URL = migration_database_url or database_url

TABLES = [
    'departments', 'roles', 'permissions', 'role_permissions',
    'doctors', 'rooms', 'patients', 'beds', 'equipment',
    'users', 'user_permission_overrides', 'appointments',
    'optimization_runs', 'audit_logs', 'alembic_version'
]


def audit_and_enable_rls(check_only=False):
    if not TARGET_URL or not TARGET_URL.startswith('postgresql'):
        print(f"[RLS-INFO] Skipping PostgreSQL RLS enforcement (Database is SQLite / Non-Postgres: {TARGET_URL[:20]}...)")
        return 0

    print(f"[RLS] Connecting to PostgreSQL to inspect and configure Row Level Security...")
    engine = create_engine(TARGET_URL)

    with engine.connect() as conn:
        if not check_only:
            print("[RLS] Applying RLS to all application tables...")
            for table in TABLES:
                try:
                    conn.execute(text(f"ALTER TABLE IF EXISTS {table} ENABLE ROW LEVEL SECURITY;"))
                except Exception as e:
                    print(f"  [WARN] Failed to enable RLS on {table}: {e}")

            # Revoke public API roles
            try:
                conn.execute(text("REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;"))
                conn.execute(text("REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;"))
                conn.execute(text("REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon, authenticated;"))
            except Exception as e:
                print(f"  [INFO] Revoke API roles (anon/auth): {e}")

            conn.commit()

        # Audit RLS status
        query = text("""
            SELECT tablename, rowsecurity
            FROM pg_tables
            WHERE schemaname = 'public'
            ORDER BY tablename;
        """)
        rows = conn.execute(query).fetchall()

        print("\n" + "=" * 50)
        print(f"{'Table Name':<30} | {'RLS Enabled':<15}")
        print("=" * 50)

        missing_rls = []
        for row in rows:
            table_name, rls_active = row[0], bool(row[1])
            status_str = "ENABLED (SECURE)" if rls_active else "DISABLED (ALERT!)"
            print(f"{table_name:<30} | {status_str:<15}")
            if not rls_active:
                missing_rls.append(table_name)

        print("=" * 50)
        if missing_rls:
            print(f"\n[ERROR] CRITICAL SECURITY ISSUE: {len(missing_rls)} table(s) lack Row Level Security!")
            print(f"Tables without RLS: {', '.join(missing_rls)}")
            return 1

        print("\n[SUCCESS] All public schema tables have Row Level Security enabled. PostgREST API access is blocked.")
        return 0


if __name__ == '__main__':
    check_mode = '--check' in sys.argv
    sys.exit(audit_and_enable_rls(check_only=check_mode))

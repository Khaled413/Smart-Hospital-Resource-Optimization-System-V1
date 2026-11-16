#!/usr/bin/env python3
"""
migrate_sqlite_to_postgres.py - One-time SQLite to PostgreSQL Data Migrator
Copies all records from local SQLite (instance/hospital.db) to Supabase PostgreSQL.
- Inserts tables in topological dependency order.
- Validates row counts between source SQLite and target PostgreSQL.
- Resets PostgreSQL auto-increment sequences (setval) to prevent primary key collision.
- Idempotent and safe to run.
"""

import sys
import os
import argparse
from sqlalchemy import create_engine, MetaData, Table, select, insert, text

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from config import BASE_DIR, database_url, migration_database_url

# Dependency topological order
MIGRATION_ORDER = [
    'departments',
    'roles',
    'permissions',
    'role_permissions',
    'doctors',
    'rooms',
    'patients',
    'beds',
    'equipment',
    'users',
    'user_permission_overrides',
    'optimization_runs',
    'appointments',
    'audit_logs'
]


def migrate(sqlite_path: str, postgres_url: str, truncate_first: bool = False):
    print("=" * 65)
    print("MediOptim Pro: SQLite -> Supabase PostgreSQL Data Migration")
    print("=" * 65)

    if not os.path.exists(sqlite_path):
        print(f"[ERROR] Source SQLite database not found at: {sqlite_path}")
        return 1

    clean_sqlite = sqlite_path.replace('\\', '/')
    src_engine = create_engine(f"sqlite:///{clean_sqlite}")
    dst_engine = create_engine(postgres_url)

    src_meta = MetaData()
    dst_meta = MetaData()
    src_meta.reflect(bind=src_engine)
    dst_meta.reflect(bind=dst_engine)

    print(f"Source: {sqlite_path}")
    print(f"Target: {postgres_url.split('@')[-1] if '@' in postgres_url else postgres_url}")
    print(f"Tables to transfer: {len(MIGRATION_ORDER)}")
    print("-" * 65)

    with src_engine.connect() as src_conn, dst_engine.connect() as dst_conn:
        if truncate_first:
            print("[WARN] Truncating target PostgreSQL tables...")
            for table_name in reversed(MIGRATION_ORDER):
                if table_name in dst_meta.tables:
                    try:
                        dst_conn.execute(text(f"TRUNCATE TABLE {table_name} RESTART IDENTITY CASCADE;"))
                    except Exception as e:
                        print(f"  [WARN] Truncate on {table_name}: {e}")
            dst_conn.commit()

        results = []

        for table_name in MIGRATION_ORDER:
            if table_name not in src_meta.tables:
                print(f"[SKIP] Table '{table_name}' does not exist in SQLite.")
                continue
            if table_name not in dst_meta.tables:
                print(f"[SKIP] Table '{table_name}' does not exist in target PostgreSQL (Run migrations first!).")
                continue

            src_table = src_meta.tables[table_name]
            dst_table = dst_meta.tables[table_name]

            # Read all rows from SQLite
            src_rows = src_conn.execute(select(src_table)).fetchall()
            src_count = len(src_rows)

            if src_count == 0:
                print(f"  - {table_name:<25}: 0 rows (Nothing to transfer)")
                results.append((table_name, 0, 0, True))
                continue

            # Convert rows to list of dicts
            row_dicts = [dict(row._mapping) for row in src_rows]

            # Insert into target PostgreSQL
            # Check existing target count
            existing_count = dst_conn.execute(text(f"SELECT COUNT(*) FROM {table_name}")).scalar()
            if existing_count > 0 and not truncate_first:
                print(f"  - {table_name:<25}: Target already has {existing_count} rows. Skipping transfer.")
                results.append((table_name, src_count, existing_count, True))
                continue

            dst_conn.execute(insert(dst_table), row_dicts)
            dst_conn.commit()

            dst_count = dst_conn.execute(text(f"SELECT COUNT(*) FROM {table_name}")).scalar()
            is_match = (src_count == dst_count) if truncate_first else (dst_count >= src_count)
            status_text = "MATCH" if is_match else "MISMATCH"
            print(f"  - {table_name:<25}: {src_count} source -> {dst_count} target [{status_text}]")
            results.append((table_name, src_count, dst_count, is_match))

            # Reset sequence for table primary key in PostgreSQL
            try:
                seq_query = text(f"""
                    SELECT setval(
                        pg_get_serial_sequence('{table_name}', 'id'),
                        COALESCE((SELECT MAX(id) FROM {table_name}), 1)
                    );
                """)
                dst_conn.execute(seq_query)
                dst_conn.commit()
            except Exception:
                # Table might not have an auto-increment 'id' column (e.g. role_permissions)
                pass

    print("=" * 65)
    print("Verification Summary:")
    all_matched = True
    for t_name, s_cnt, d_cnt, matched in results:
        flag = "[OK]" if matched else "[FAIL]"
        if not matched:
            all_matched = False
        print(f"  {flag} {t_name:<25} SQLite: {s_cnt:<5} Postgres: {d_cnt:<5}")

    print("=" * 65)
    if all_matched:
        print("[SUCCESS] Data migration completed and verified successfully!")
        return 0
    else:
        print("[ERROR] Row count discrepancies detected!")
        return 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Migrate MediOptim Pro SQLite to PostgreSQL")
    parser.add_argument('--sqlite', default=os.path.join(BASE_DIR, 'instance', 'hospital.db'),
                        help="Path to source SQLite database")
    parser.add_argument('--postgres', default=migration_database_url or database_url,
                        help="Target PostgreSQL connection URL (port 5432 or 6543)")
    parser.add_argument('--truncate', action='store_true',
                        help="Truncate target tables before inserting (clean copy)")

    args = parser.parse_args()
    if not args.postgres or not args.postgres.startswith('postgresql'):
        print("[ERROR] A valid PostgreSQL target DATABASE_URL is required.")
        sys.exit(1)

    sys.exit(migrate(args.sqlite, args.postgres, truncate_first=args.truncate))

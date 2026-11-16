#!/usr/bin/env bash
# MediOptim Pro - Supabase PostgreSQL Automated Backup Script
# Usage: ./scripts/backup_supabase.sh [backup_dir]

set -euo pipefail

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/medioptim_backup_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

if [ -z "${MIGRATION_DATABASE_URL:-}" ] && [ -z "${DATABASE_URL:-}" ]; then
  echo "[ERROR] MIGRATION_DATABASE_URL or DATABASE_URL must be defined."
  exit 1
fi

TARGET_URL="${MIGRATION_DATABASE_URL:-$DATABASE_URL}"

echo "[INFO] Starting database backup at $(date)..."
echo "[INFO] Target output: ${BACKUP_FILE}"

# Use pg_dump with custom clean format and gzip compression
pg_dump "${TARGET_URL}" \
  --no-owner \
  --no-privileges \
  --clean \
  --if-exists \
  --schema=public \
  | gzip -9 > "${BACKUP_FILE}"

FILE_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[SUCCESS] Backup completed successfully (${FILE_SIZE}): ${BACKUP_FILE}"

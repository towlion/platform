#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Usage
usage() {
  echo "Usage: $0 [--all | <app-name>]"
  echo ""
  echo "Verify that the latest backup for each database can be restored."
  echo ""
  echo "Arguments:"
  echo "  --all       Verify backups for all databases found in backup directory"
  echo "  <app-name>  Verify backup for a specific app (e.g., todo-app)"
  echo ""
  echo "Examples:"
  echo "  $0 --all"
  echo "  $0 todo-app"
  exit 1
}

if [ $# -ne 1 ]; then
  error "Expected 1 argument"
  usage
fi

# Configuration
BACKUP_DIR="/data/backups/postgres"
COMPOSE_FILE="/opt/platform/docker-compose.yml"
VERIFY_ALL=false
APP_NAME=""

if [ "$1" = "--all" ]; then
  VERIFY_ALL=true
else
  APP_NAME="$1"
fi

# Check Docker access
if ! docker ps >/dev/null 2>&1; then
  error "This script requires Docker access. Run as root or ensure your user is in the docker group."
  exit 1
fi

# Check backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
  error "Backup directory not found: $BACKUP_DIR"
  exit 1
fi

# Collect databases to verify
declare -a DATABASES=()

if [ "$VERIFY_ALL" = true ]; then
  # Find all unique database names from backup files
  for dump in "$BACKUP_DIR"/*.dump; do
    [ -f "$dump" ] || continue
    db_name=$(basename "$dump" | sed 's/_[0-9]\{8\}_[0-9]\{6\}\.dump$//')
    # Add to array if not already present
    if [[ ! " ${DATABASES[*]:-} " =~ " ${db_name} " ]]; then
      DATABASES+=("$db_name")
    fi
  done

  if [ ${#DATABASES[@]} -eq 0 ]; then
    warn "No backup files found in $BACKUP_DIR"
    exit 0
  fi
else
  # Derive database name from app name
  DATABASES+=("$(echo "$APP_NAME" | tr '-' '_')_db")
fi

info "=== Backup Verification ==="
info "Databases to verify: ${DATABASES[*]}"
echo ""

# Track results
PASSED=0
FAILED=0

# Verify each database
for db_name in "${DATABASES[@]}"; do
  info "--- Verifying: $db_name ---"

  # Find the latest backup for this database
  LATEST_BACKUP=$(find "$BACKUP_DIR" -name "${db_name}_*.dump" -type f | sort -r | head -1)

  if [ -z "$LATEST_BACKUP" ]; then
    error "No backup found for $db_name"
    ((FAILED++))
    continue
  fi

  BACKUP_SIZE=$(stat -c%s "$LATEST_BACKUP" 2>/dev/null || stat -f%z "$LATEST_BACKUP" 2>/dev/null || echo "0")
  HUMAN_SIZE=$(numfmt --to=iec-i --suffix=B "$BACKUP_SIZE" 2>/dev/null || echo "${BACKUP_SIZE}B")
  info "Latest backup: $(basename "$LATEST_BACKUP") ($HUMAN_SIZE)"

  # Create temporary verification database
  TIMESTAMP=$(date +%s)
  VERIFY_DB="${db_name}_verify_${TIMESTAMP}"
  info "Creating temp database: $VERIFY_DB"

  RESTORE_OK=false

  # Create temp database
  if ! docker compose -f "$COMPOSE_FILE" exec -T postgres \
    psql -U postgres -c "CREATE DATABASE ${VERIFY_DB}" >/dev/null 2>&1; then
    error "Failed to create temp database $VERIFY_DB"
    ((FAILED++))
    continue
  fi

  # Restore backup into temp database
  if cat "$LATEST_BACKUP" | docker compose -f "$COMPOSE_FILE" exec -T postgres \
    pg_restore -U postgres -d "$VERIFY_DB" --no-owner --no-acl 2>/dev/null; then
    info "Restore completed"
    RESTORE_OK=true
  else
    # pg_restore returns non-zero for warnings too — check if tables exist
    TABLE_COUNT=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
      psql -U postgres -d "$VERIFY_DB" -tc \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null | tr -d ' ')

    if [ "${TABLE_COUNT:-0}" -gt 0 ]; then
      info "Restore completed with warnings (${TABLE_COUNT} tables)"
      RESTORE_OK=true
    else
      error "Restore failed — no tables found in restored database"
    fi
  fi

  if [ "$RESTORE_OK" = true ]; then
    # Verify tables exist
    TABLE_COUNT=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
      psql -U postgres -d "$VERIFY_DB" -tc \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null | tr -d ' ')
    info "Tables found: ${TABLE_COUNT:-0}"

    # Check for alembic_version (indicates migration history)
    HAS_ALEMBIC=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
      psql -U postgres -d "$VERIFY_DB" -tc \
      "SELECT 1 FROM information_schema.tables WHERE table_name = 'alembic_version'" 2>/dev/null | tr -d ' ')

    if [ "${HAS_ALEMBIC}" = "1" ]; then
      ALEMBIC_REV=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U postgres -d "$VERIFY_DB" -tc \
        "SELECT version_num FROM alembic_version LIMIT 1" 2>/dev/null | tr -d ' ')
      info "Alembic version: ${ALEMBIC_REV:-unknown}"
    else
      info "No alembic_version table (app may not use migrations)"
    fi

    info "PASS: $db_name backup verified"
    ((PASSED++))
  else
    error "FAIL: $db_name backup verification failed"
    ((FAILED++))
  fi

  # Drop temp database
  info "Dropping temp database: $VERIFY_DB"
  docker compose -f "$COMPOSE_FILE" exec -T postgres \
    psql -U postgres -c "DROP DATABASE IF EXISTS ${VERIFY_DB}" >/dev/null 2>&1 || \
    warn "Failed to drop temp database $VERIFY_DB (manual cleanup needed)"

  echo ""
done

# Summary
info "=== Verification Summary ==="
info "Passed: $PASSED"
if [ "$FAILED" -gt 0 ]; then
  error "Failed: $FAILED"
fi

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

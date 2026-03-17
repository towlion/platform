#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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
    echo "Usage: $0 <backup-file> [database-name] [--yes]"
    echo ""
    echo "Arguments:"
    echo "  backup-file    Path to the .dump backup file (required)"
    echo "  database-name  Target database name (optional, extracted from filename if not provided)"
    echo "  --yes          Skip confirmation prompt"
    echo ""
    echo "Examples:"
    echo "  $0 /data/backups/postgres/todo_app_db_20260316_143000.dump"
    echo "  $0 /data/backups/postgres/todo_app_db_20260316_143000.dump todo_app_db"
    echo "  $0 /data/backups/postgres/todo_app_db_20260316_143000.dump --yes"
    exit 1
}

# Parse arguments
BACKUP_FILE=""
TARGET_DB=""
SKIP_CONFIRM=false

for arg in "$@"; do
    if [ "$arg" = "--yes" ]; then
        SKIP_CONFIRM=true
    elif [ -z "$BACKUP_FILE" ]; then
        BACKUP_FILE="$arg"
    elif [ -z "$TARGET_DB" ]; then
        TARGET_DB="$arg"
    fi
done

# Validate backup file
if [ -z "$BACKUP_FILE" ]; then
    error "Backup file not specified"
    usage
fi

if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Determine target database
if [ -z "$TARGET_DB" ]; then
    # Extract database name from filename pattern: <dbname>_YYYYMMDD_HHMMSS.dump[.enc]
    TARGET_DB=$(basename "$BACKUP_FILE" | sed 's/_[0-9]\{8\}_[0-9]\{6\}\.dump\(\.enc\)\?$//')
    info "Extracted database name from filename: $TARGET_DB"
fi

# Handle encrypted backups
RESTORE_FILE="$BACKUP_FILE"
DECRYPTED_TEMP=""
if [[ "$BACKUP_FILE" == *.dump.enc ]]; then
    ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
    if [ -z "$ENCRYPTION_KEY" ] || [ ! -f "$ENCRYPTION_KEY" ]; then
        error "Encrypted backup detected but BACKUP_ENCRYPTION_KEY is not set or file not found"
        exit 1
    fi
    DECRYPTED_TEMP=$(mktemp /tmp/restore_XXXXXXXXXX.dump)
    info "Decrypting backup..."
    if openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:${ENCRYPTION_KEY}" -in "$BACKUP_FILE" -out "$DECRYPTED_TEMP"; then
        info "Backup decrypted to temp file"
        RESTORE_FILE="$DECRYPTED_TEMP"
    else
        rm -f "$DECRYPTED_TEMP"
        error "Failed to decrypt backup"
        exit 1
    fi
    # Clean up temp file on exit
    trap 'rm -f "$DECRYPTED_TEMP"' EXIT
fi

# Confirmation
if [ "$SKIP_CONFIRM" = false ]; then
    warn "This will DROP and recreate database '$TARGET_DB'"
    echo -n "Continue? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Restore cancelled"
        exit 0
    fi
fi

# Configuration
COMPOSE_FILE="/opt/platform/docker-compose.yml"

# Drop and recreate database
info "Dropping database: $TARGET_DB"
if docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -c "DROP DATABASE IF EXISTS ${TARGET_DB}"; then
    info "  ✓ Database dropped"
else
    error "Failed to drop database"
    exit 1
fi

info "Creating database: $TARGET_DB"
if docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -c "CREATE DATABASE ${TARGET_DB}"; then
    info "  ✓ Database created"
else
    error "Failed to create database"
    exit 1
fi

# Restore backup
info "Restoring backup to $TARGET_DB..."
if cat "$RESTORE_FILE" | docker compose -f "$COMPOSE_FILE" exec -T postgres pg_restore -U postgres -d "$TARGET_DB" --no-owner --no-acl; then
    info "  ✓ Backup restored successfully"
else
    error "Failed to restore backup"
    exit 1
fi

# Re-apply credentials if matching app env file exists
info "Checking for app credentials..."

# Derive app name from database name (strip _db suffix, replace _ with -)
app_name=$(echo "$TARGET_DB" | sed 's/_db$//' | tr '_' '-')
credentials_file="/opt/platform/credentials/${app_name}.env"

if [ -f "$credentials_file" ]; then
    info "Found credentials file: $credentials_file"
    info "Re-applying database credentials..."

    # Source the credentials file
    # shellcheck disable=SC1090
    source "$credentials_file"

    # Re-apply GRANT statements for the app user
    docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres <<EOSQL
GRANT ALL PRIVILEGES ON DATABASE ${TARGET_DB} TO ${DB_USER};
REVOKE CONNECT ON DATABASE ${TARGET_DB} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${TARGET_DB} TO ${DB_USER};
GRANT ALL PRIVILEGES ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
EOSQL
    info "Database privileges re-applied for user ${DB_USER}"
else
    info "No credentials file found at $credentials_file"
    info "Skipping credential re-application"
fi

# Success
echo ""
info "=== Restore Complete ==="
info "Database: $TARGET_DB"
info "Backup file: $BACKUP_FILE"
info "Restore successful!"

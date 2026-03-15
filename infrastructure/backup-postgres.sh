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

# Configuration
BACKUP_DIR="/data/backups/postgres"
COMPOSE_FILE="/opt/platform/docker-compose.yml"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

info "Starting PostgreSQL backup..."
info "Backup directory: $BACKUP_DIR"

# List all databases except templates and postgres system database
info "Fetching database list..."
databases=$(docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -tc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres'" | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$databases" ]; then
    warn "No databases found to backup"
    exit 0
fi

# Track failures
failed_dumps=0
total_size=0
backup_count=0

# Backup each database
for db in $databases; do
    filename="${db}_$(date +%Y%m%d_%H%M%S).dump"
    filepath="$BACKUP_DIR/$filename"

    info "Backing up database: $db"

    if docker compose -f "$COMPOSE_FILE" exec -T postgres pg_dump -U postgres -Fc "$db" > "$filepath"; then
        file_size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null || echo "0")
        human_size=$(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "${file_size}B")
        info "  ✓ Backed up $db to $filename ($human_size)"
        ((total_size += file_size))
        ((backup_count++))
    else
        error "  ✗ Failed to backup $db"
        ((failed_dumps++))
        rm -f "$filepath"  # Clean up partial dump
    fi
done

# Retention: delete backups older than 7 days
info "Cleaning up old backups (older than 7 days)..."
deleted_count=$(find "$BACKUP_DIR" -name "*.dump" -mtime +7 -delete -print | wc -l | tr -d ' ')
if [ "$deleted_count" -gt 0 ]; then
    info "  Removed $deleted_count old backup(s)"
else
    info "  No old backups to remove"
fi

# Print summary
echo ""
info "=== Backup Summary ==="
info "Databases backed up: $backup_count"
if [ "$total_size" -gt 0 ]; then
    human_total=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size}B")
    info "Total backup size: $human_total"
fi
if [ "$failed_dumps" -gt 0 ]; then
    error "Failed backups: $failed_dumps"
fi
info "Backup location: $BACKUP_DIR"

# Exit with error if any dumps failed
if [ "$failed_dumps" -gt 0 ]; then
    exit 1
fi

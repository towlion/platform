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
  echo "Usage: $0 <app-name> [--type db|s3|all]"
  echo ""
  echo "Rotate credentials for an application without downtime."
  echo ""
  echo "Arguments:"
  echo "  app-name     Name of the application (e.g., todo-app)"
  echo "  --type       Type of credentials to rotate (default: all)"
  echo "               db  — PostgreSQL password only"
  echo "               s3  — MinIO password only"
  echo "               all — Both PostgreSQL and MinIO"
  echo ""
  echo "Examples:"
  echo "  $0 todo-app"
  echo "  $0 todo-app --type db"
  echo "  $0 todo-app --type s3"
  exit 1
}

# Parse arguments
if [ $# -lt 1 ]; then
  error "Expected at least 1 argument"
  usage
fi

APP_NAME="$1"
ROTATE_TYPE="all"

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift
      ROTATE_TYPE="${1:-all}"
      if [[ ! "$ROTATE_TYPE" =~ ^(db|s3|all)$ ]]; then
        error "Invalid type: $ROTATE_TYPE (must be db, s3, or all)"
        usage
      fi
      ;;
    *)
      error "Unknown argument: $1"
      usage
      ;;
  esac
  shift
done

# Configuration
PLATFORM_COMPOSE="/opt/platform/docker-compose.yml"
CREDENTIALS_FILE="/opt/platform/credentials/${APP_NAME}.env"
APP_ENV_FILE="/opt/apps/${APP_NAME}/deploy/.env"
SLOT_FILE="/opt/apps/${APP_NAME}/.deploy-slot"
APP_DB="$(echo "${APP_NAME}" | tr '-' '_')_db"
APP_USER="$(echo "${APP_NAME}" | tr '-' '_')_user"
MINIO_USER="${APP_NAME}-user"

# Check Docker access
if ! docker ps >/dev/null 2>&1; then
  error "This script requires Docker access. Run as root or ensure your user is in the docker group."
  exit 1
fi

# Check credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
  error "Credentials file not found: $CREDENTIALS_FILE"
  error "Run create-app-credentials.sh ${APP_NAME} first."
  exit 1
fi

# Source existing credentials
# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

# Source platform .env for MinIO root credentials
if [ ! -f /opt/platform/.env ]; then
  error "/opt/platform/.env not found"
  exit 1
fi
# shellcheck source=/dev/null
source /opt/platform/.env

# Determine current deployment slot
CURRENT_SLOT="blue"
if [ -f "$SLOT_FILE" ]; then
  CURRENT_SLOT=$(cat "$SLOT_FILE")
fi
COMPOSE_PROJECT="${APP_NAME}-${CURRENT_SLOT}"

info "=== Credential Rotation: ${APP_NAME} ==="
info "Type: ${ROTATE_TYPE}"
info "Active slot: ${CURRENT_SLOT}"
echo ""

# Rotate PostgreSQL credentials
if [[ "$ROTATE_TYPE" == "db" || "$ROTATE_TYPE" == "all" ]]; then
  info "--- Rotating PostgreSQL credentials ---"

  NEW_DB_PASSWORD=$(openssl rand -base64 24)

  # Update PostgreSQL user password
  if docker compose -f "$PLATFORM_COMPOSE" exec -T postgres \
    psql -U postgres -c "ALTER USER ${APP_USER} WITH PASSWORD '${NEW_DB_PASSWORD}'" >/dev/null 2>&1; then
    info "PostgreSQL password updated for user: ${APP_USER}"
  else
    error "Failed to update PostgreSQL password"
    exit 1
  fi

  # Update credentials file
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${NEW_DB_PASSWORD}|" "$CREDENTIALS_FILE"
  info "Credentials file updated: $CREDENTIALS_FILE"

  # Update app deploy/.env
  if [ -f "$APP_ENV_FILE" ]; then
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://${APP_USER}:${NEW_DB_PASSWORD}@postgres:5432/${APP_DB}|" "$APP_ENV_FILE"
    info "App .env updated: $APP_ENV_FILE"
  else
    warn "App .env not found at $APP_ENV_FILE — manual update needed"
  fi

  DB_PASSWORD="$NEW_DB_PASSWORD"
fi

# Rotate MinIO credentials
if [[ "$ROTATE_TYPE" == "s3" || "$ROTATE_TYPE" == "all" ]]; then
  info "--- Rotating MinIO credentials ---"

  NEW_S3_PASSWORD=$(openssl rand -base64 24)

  # Remove old MinIO user and re-create with new password
  docker run --rm --network towlion --entrypoint sh minio/mc -c "
    mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' >/dev/null 2>&1
    mc admin user remove local '${MINIO_USER}' 2>/dev/null || true
    mc admin user add local '${MINIO_USER}' '${NEW_S3_PASSWORD}'
    mc admin policy attach local ${APP_NAME}-policy --user '${MINIO_USER}' 2>/dev/null || true
  "
  info "MinIO password updated for user: ${MINIO_USER}"

  # Update credentials file
  sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${NEW_S3_PASSWORD}|" "$CREDENTIALS_FILE"
  info "Credentials file updated: $CREDENTIALS_FILE"

  # Update app deploy/.env
  if [ -f "$APP_ENV_FILE" ]; then
    sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${NEW_S3_PASSWORD}|" "$APP_ENV_FILE"
    info "App .env updated: $APP_ENV_FILE"
  else
    warn "App .env not found at $APP_ENV_FILE — manual update needed"
  fi

  S3_SECRET_KEY="$NEW_S3_PASSWORD"
fi

# Restart the app container to pick up new credentials
info "--- Restarting app container ---"
cd "/opt/apps/${APP_NAME}"
if docker compose -p "$COMPOSE_PROJECT" -f deploy/docker-compose.yml ps --quiet 2>/dev/null | grep -q .; then
  docker compose -p "$COMPOSE_PROJECT" -f deploy/docker-compose.yml restart
  info "App container restarted (project: ${COMPOSE_PROJECT})"
else
  # Fallback: try non-slotted project name
  if docker compose -p "$APP_NAME" -f deploy/docker-compose.yml ps --quiet 2>/dev/null | grep -q .; then
    docker compose -p "$APP_NAME" -f deploy/docker-compose.yml restart
    info "App container restarted (project: ${APP_NAME})"
  else
    warn "No running containers found for ${APP_NAME} — skip restart"
  fi
fi

# Health check
info "--- Verifying app health ---"
HEALTH_TIMEOUT=30
ELAPSED=0
HEALTH_OK=false

while [ $ELAPSED -lt $HEALTH_TIMEOUT ]; do
  CONTAINER_NAME="${COMPOSE_PROJECT}-app-1"
  HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "not_found")

  if [ "$HEALTH_STATUS" = "healthy" ]; then
    HEALTH_OK=true
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$HEALTH_OK" = true ]; then
  info "App is healthy after credential rotation"
else
  error "App health check failed after credential rotation!"
  error "Container health status: ${HEALTH_STATUS}"
  error "The app may need manual intervention."
  exit 1
fi

# Success
echo ""
info "=== Credential Rotation Complete ==="
info "App:    ${APP_NAME}"
info "Type:   ${ROTATE_TYPE}"
info "Credentials rotated and app verified healthy"

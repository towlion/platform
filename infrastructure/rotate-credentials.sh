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
  echo "Usage: $0 <app-name> [--type db|s3|jwt|all]"
  echo "       $0 --platform [--type db|s3|all] [--yes]"
  echo ""
  echo "Rotate credentials for an application or the platform itself."
  echo ""
  echo "App mode:"
  echo "  app-name     Name of the application (e.g., todo-app)"
  echo "  --type       Type of credentials to rotate (default: all)"
  echo "               db  — PostgreSQL password only"
  echo "               s3  — MinIO password only"
  echo "               jwt — JWT secret only"
  echo "               all — PostgreSQL, MinIO, and JWT"
  echo ""
  echo "Platform mode:"
  echo "  --platform   Rotate platform master credentials"
  echo "  --type       db  — PostgreSQL superuser password"
  echo "               s3  — MinIO root password"
  echo "               all — Both (default)"
  echo "  --yes        Skip confirmation prompt"
  echo ""
  echo "Examples:"
  echo "  $0 todo-app"
  echo "  $0 todo-app --type db"
  echo "  $0 --platform --type db --yes"
  exit 1
}

# Parse arguments
if [ $# -lt 1 ]; then
  error "Expected at least 1 argument"
  usage
fi

PLATFORM_MODE=false
APP_NAME=""
ROTATE_TYPE="all"
SKIP_CONFIRM=false

# Check for --platform as first arg
if [ "$1" = "--platform" ]; then
  PLATFORM_MODE=true
  shift
else
  APP_NAME="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --type)
      shift
      ROTATE_TYPE="${1:-all}"
      if [ "$PLATFORM_MODE" = true ]; then
        if [[ ! "$ROTATE_TYPE" =~ ^(db|s3|all)$ ]]; then
          error "Invalid type for platform mode: $ROTATE_TYPE (must be db, s3, or all)"
          usage
        fi
      else
        if [[ ! "$ROTATE_TYPE" =~ ^(db|s3|jwt|all)$ ]]; then
          error "Invalid type: $ROTATE_TYPE (must be db, s3, jwt, or all)"
          usage
        fi
      fi
      ;;
    --yes)
      SKIP_CONFIRM=true
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
PLATFORM_ENV="/opt/platform/.env"

# Check Docker access
if ! docker ps >/dev/null 2>&1; then
  error "This script requires Docker access. Run as root or ensure your user is in the docker group."
  exit 1
fi

# Source platform .env
if [ ! -f "$PLATFORM_ENV" ]; then
  error "/opt/platform/.env not found"
  exit 1
fi
# shellcheck source=/dev/null
source "$PLATFORM_ENV"

# ============================================================
# Platform credential rotation
# ============================================================
if [ "$PLATFORM_MODE" = true ]; then
  info "=== Platform Master Credential Rotation ==="
  info "Type: ${ROTATE_TYPE}"
  echo ""

  if [ "$SKIP_CONFIRM" = false ]; then
    warn "This will rotate platform master credentials affecting ALL services."
    echo -n "Continue? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      info "Rotation cancelled"
      exit 0
    fi
  fi

  # Rotate PostgreSQL superuser password
  if [[ "$ROTATE_TYPE" == "db" || "$ROTATE_TYPE" == "all" ]]; then
    info "--- Rotating PostgreSQL superuser password ---"

    NEW_PG_PASSWORD=$(openssl rand -base64 24)

    if docker compose -f "$PLATFORM_COMPOSE" exec -T postgres \
      psql -U postgres -c "ALTER USER postgres WITH PASSWORD '${NEW_PG_PASSWORD}'" >/dev/null 2>&1; then
      info "PostgreSQL superuser password updated"
    else
      error "Failed to update PostgreSQL superuser password"
      exit 1
    fi

    # Update platform .env
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_PG_PASSWORD}|" "$PLATFORM_ENV"
    info "Platform .env updated"

    # Restart postgres to pick up new password
    cd /opt/platform
    docker compose restart postgres
    info "PostgreSQL container restarted"

    # Wait for postgres to be ready
    sleep 3
    if docker compose -f "$PLATFORM_COMPOSE" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
      info "PostgreSQL is ready"
    else
      error "PostgreSQL failed to come back up after password rotation!"
      exit 1
    fi
  fi

  # Rotate MinIO root password
  if [[ "$ROTATE_TYPE" == "s3" || "$ROTATE_TYPE" == "all" ]]; then
    info "--- Rotating MinIO root password ---"

    NEW_MINIO_PASSWORD=$(openssl rand -base64 24)

    # Update platform .env
    sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=${NEW_MINIO_PASSWORD}|" "$PLATFORM_ENV"
    info "Platform .env updated"

    # Restart minio with new password
    cd /opt/platform
    docker compose restart minio
    info "MinIO container restarted"

    # Verify MinIO health
    sleep 3
    if docker compose -f "$PLATFORM_COMPOSE" exec -T minio curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; then
      info "MinIO is healthy"
    else
      warn "MinIO health check inconclusive — verify manually"
    fi
  fi

  # Health check all apps
  info "--- Verifying all app health ---"
  ALL_HEALTHY=true
  if [ -d /opt/platform/credentials ]; then
    for cred_file in /opt/platform/credentials/*.env; do
      [ -f "$cred_file" ] || continue
      app=$(basename "$cred_file" .env)
      slot_file="/opt/apps/${app}/.deploy-slot"
      slot="blue"
      [ -f "$slot_file" ] && slot=$(cat "$slot_file")
      container="${app}-${slot}-app-1"

      health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
      if [ "$health" = "healthy" ]; then
        info "  ${app}: healthy"
      else
        warn "  ${app}: ${health}"
        ALL_HEALTHY=false
      fi
    done
  fi

  if [ "$ALL_HEALTHY" = true ]; then
    info "All apps healthy after platform credential rotation"
  else
    warn "Some apps may need attention — check above"
  fi

  echo ""
  info "=== Platform Credential Rotation Complete ==="
  exit 0
fi

# ============================================================
# Per-app credential rotation (original behavior)
# ============================================================
if [ -z "$APP_NAME" ]; then
  error "App name required (or use --platform)"
  usage
fi

CREDENTIALS_FILE="/opt/platform/credentials/${APP_NAME}.env"
APP_ENV_FILE="/opt/apps/${APP_NAME}/deploy/.env"
SLOT_FILE="/opt/apps/${APP_NAME}/.deploy-slot"
APP_DB="$(echo "${APP_NAME}" | tr '-' '_')_db"
APP_USER="$(echo "${APP_NAME}" | tr '-' '_')_user"
MINIO_USER="${APP_NAME}-user"

# Check credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
  error "Credentials file not found: $CREDENTIALS_FILE"
  error "Run create-app-credentials.sh ${APP_NAME} first."
  exit 1
fi

# Source existing credentials
# shellcheck source=/dev/null
source "$CREDENTIALS_FILE"

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

# Rotate JWT secret
if [[ "$ROTATE_TYPE" == "jwt" || "$ROTATE_TYPE" == "all" ]]; then
  info "--- Rotating JWT secret ---"

  NEW_JWT_SECRET=$(openssl rand -base64 32)

  # Update credentials file
  grep -q '^JWT_SECRET=' "$CREDENTIALS_FILE" \
    && sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${NEW_JWT_SECRET}|" "$CREDENTIALS_FILE" \
    || echo "JWT_SECRET=${NEW_JWT_SECRET}" >> "$CREDENTIALS_FILE"
  info "Credentials file updated: $CREDENTIALS_FILE"

  # Update app deploy/.env
  if [ -f "$APP_ENV_FILE" ]; then
    grep -q '^JWT_SECRET=' "$APP_ENV_FILE" \
      && sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${NEW_JWT_SECRET}|" "$APP_ENV_FILE" \
      || echo "JWT_SECRET=${NEW_JWT_SECRET}" >> "$APP_ENV_FILE"
    info "App .env updated: $APP_ENV_FILE"
  else
    warn "App .env not found at $APP_ENV_FILE — manual update needed"
  fi
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

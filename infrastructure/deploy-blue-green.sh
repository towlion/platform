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
  echo "Usage: $0 <app-name> <app-dir> <app-domain> <caddyfile-content>"
  echo ""
  echo "Arguments:"
  echo "  app-name          Name of the application (e.g., todo-app)"
  echo "  app-dir           Path to the app repo (e.g., /opt/apps/todo-app)"
  echo "  app-domain        Domain name (e.g., app.anulectra.com)"
  echo "  caddyfile-content Caddyfile content with placeholders already resolved"
  echo ""
  echo "Blue-green deployment: runs new and old containers simultaneously,"
  echo "then atomically swaps traffic after the new container is healthy."
  exit 1
}

# Check arguments
if [ $# -ne 4 ]; then
  error "Expected 4 arguments, got $#"
  usage
fi

APP_NAME="$1"
APP_DIR="$2"
APP_DOMAIN="$3"
CADDYFILE_CONTENT="$4"

COMPOSE_FILE="deploy/docker-compose.yml"
SLOT_FILE="/opt/apps/${APP_NAME}/.deploy-slot"
PLATFORM_COMPOSE="/opt/platform/docker-compose.yml"
CREDENTIALS_FILE="/opt/platform/credentials/${APP_NAME}.env"
APP_DB="$(echo "${APP_NAME}" | tr '-' '_')_db"

# Track whether we started the new slot (for cleanup on failure)
NEW_SLOT_STARTED=false

# Determine current and next slot
if [ -f "$SLOT_FILE" ]; then
  CURRENT_SLOT=$(cat "$SLOT_FILE")
else
  CURRENT_SLOT="blue"
fi

if [ "$CURRENT_SLOT" = "blue" ]; then
  NEXT_SLOT="green"
else
  NEXT_SLOT="blue"
fi

info "=== Blue-Green Deploy: ${APP_NAME} ==="
info "Current slot: ${CURRENT_SLOT} → Next slot: ${NEXT_SLOT}"

# Cleanup function: tear down new slot on failure
cleanup_on_failure() {
  if [ "$NEW_SLOT_STARTED" = true ]; then
    error "Deployment failed — rolling back new slot (${NEXT_SLOT})"
    cd "$APP_DIR"
    docker compose -p "${APP_NAME}-${NEXT_SLOT}" -f "$COMPOSE_FILE" down 2>/dev/null || true
    info "New slot containers removed"
  fi
  exit 1
}

trap cleanup_on_failure ERR

# Step 1: Pull latest code
info "Step 1/8: Pulling latest code..."
cd "$APP_DIR"
git pull origin main

# Step 2: Verify deploy/.env exists
if [ ! -f deploy/.env ]; then
  error "deploy/.env not found. Create it from deploy/env.template first."
  exit 1
fi

# Step 3: Create app-specific database if it doesn't exist
info "Step 2/8: Ensuring database exists..."
docker compose -f "$PLATFORM_COMPOSE" exec -T postgres \
  psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${APP_DB}'" | grep -q 1 \
  || docker compose -f "$PLATFORM_COMPOSE" exec -T postgres \
  psql -U postgres -c "CREATE DATABASE ${APP_DB}"

# Step 4: Inject per-app credentials
info "Step 3/8: Configuring credentials..."
if [ -f "$CREDENTIALS_FILE" ]; then
  info "Using per-app credentials from $CREDENTIALS_FILE"
  # shellcheck source=/dev/null
  source "$CREDENTIALS_FILE"
  sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${APP_DB}|" deploy/.env

  # Ensure S3 vars exist (append if missing, substitute if present)
  if [ -n "${S3_ACCESS_KEY:-}" ]; then
    grep -q "^S3_ENDPOINT=" deploy/.env \
      && sed -i "s|^S3_ENDPOINT=.*|S3_ENDPOINT=http://minio:9000|" deploy/.env \
      || echo "S3_ENDPOINT=http://minio:9000" >> deploy/.env
    grep -q "^S3_ACCESS_KEY=" deploy/.env \
      && sed -i "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=${S3_ACCESS_KEY}|" deploy/.env \
      || echo "S3_ACCESS_KEY=${S3_ACCESS_KEY}" >> deploy/.env
    grep -q "^S3_SECRET_KEY=" deploy/.env \
      && sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${S3_SECRET_KEY}|" deploy/.env \
      || echo "S3_SECRET_KEY=${S3_SECRET_KEY}" >> deploy/.env
    grep -q "^S3_BUCKET=" deploy/.env \
      && sed -i "s|^S3_BUCKET=.*|S3_BUCKET=${APP_NAME}-uploads|" deploy/.env \
      || echo "S3_BUCKET=${APP_NAME}-uploads" >> deploy/.env
  fi
  if [ -n "${JWT_SECRET:-}" ]; then
    grep -q "^JWT_SECRET=" deploy/.env \
      && sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" deploy/.env \
      || echo "JWT_SECRET=${JWT_SECRET}" >> deploy/.env
  fi
  info "deploy/.env updated with per-app credentials"
else
  warn "Per-app credentials not found at $CREDENTIALS_FILE"
  warn "Run create-app-credentials.sh ${APP_NAME} for isolated credentials."
  warn "Falling back to existing deploy/.env credentials."
fi

# Step 5: Build new slot
info "Step 4/8: Building new slot (${NEXT_SLOT})..."
docker compose -p "${APP_NAME}-${NEXT_SLOT}" -f "$COMPOSE_FILE" build

# Step 6: Start new slot
info "Step 5/8: Starting new slot (${NEXT_SLOT})..."
docker compose -p "${APP_NAME}-${NEXT_SLOT}" -f "$COMPOSE_FILE" up -d
NEW_SLOT_STARTED=true

# Step 7: Wait for Docker healthcheck
info "Step 6/8: Waiting for container healthcheck (60s timeout)..."
CONTAINER_NAME="${APP_NAME}-${NEXT_SLOT}-app-1"
HEALTH_TIMEOUT=60
ELAPSED=0
INTERVAL=2

while [ $ELAPSED -lt $HEALTH_TIMEOUT ]; do
  HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "not_found")

  if [ "$HEALTH_STATUS" = "healthy" ]; then
    info "Container is healthy after ${ELAPSED}s"
    break
  elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
    error "Container reported unhealthy"
    cleanup_on_failure
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $HEALTH_TIMEOUT ]; then
  error "Container did not become healthy within ${HEALTH_TIMEOUT}s"
  cleanup_on_failure
fi

# Step 8: Run Alembic migrations
info "Step 7/8: Running database migrations..."
docker compose -p "${APP_NAME}-${NEXT_SLOT}" -f "$COMPOSE_FILE" exec -T app \
  alembic -c app/alembic.ini upgrade head || {
    warn "Alembic migration failed or not configured — continuing"
  }

# Step 9: Scan built image for vulnerabilities (non-blocking)
APP_IMAGE=$(docker compose -p "${APP_NAME}-${NEXT_SLOT}" -f "$COMPOSE_FILE" images app --format json 2>/dev/null \
  | python3 -c "import sys,json; imgs=json.load(sys.stdin); print(imgs[0]['Repository']+':'+imgs[0]['Tag'])" 2>/dev/null || echo "")
if command -v trivy &>/dev/null && [ -n "$APP_IMAGE" ]; then
  info "Scanning ${APP_IMAGE} for vulnerabilities..."
  trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress "${APP_IMAGE}" || true
fi

# Step 10: Write Caddyfile and reload Caddy
info "Step 8/8: Swapping traffic to new slot..."
echo "$CADDYFILE_CONTENT" > "/opt/platform/caddy-apps/${APP_NAME}.caddy"
docker compose -f "$PLATFORM_COMPOSE" exec -T caddy caddy reload --config /etc/caddy/Caddyfile

# Step 11: Verify external health
info "Verifying external health endpoint..."
VERIFY_TIMEOUT=15
VERIFY_ELAPSED=0
EXTERNAL_OK=false

while [ $VERIFY_ELAPSED -lt $VERIFY_TIMEOUT ]; do
  if curl -sf "https://${APP_DOMAIN}/health" >/dev/null 2>&1; then
    EXTERNAL_OK=true
    break
  fi
  sleep 2
  VERIFY_ELAPSED=$((VERIFY_ELAPSED + 2))
done

if [ "$EXTERNAL_OK" = false ]; then
  error "External health check failed at https://${APP_DOMAIN}/health"
  # Revert Caddyfile to point back to old slot if we have one running
  if docker ps -q --filter "name=${APP_NAME}-${CURRENT_SLOT}-app-1" 2>/dev/null | grep -q .; then
    warn "Reverting Caddyfile to previous slot (${CURRENT_SLOT})"
    # We need to regenerate the old Caddyfile — use sed to swap container names
    echo "$CADDYFILE_CONTENT" \
      | sed "s/${APP_NAME}-${NEXT_SLOT}/${APP_NAME}-${CURRENT_SLOT}/g" \
      > "/opt/platform/caddy-apps/${APP_NAME}.caddy"
    docker compose -f "$PLATFORM_COMPOSE" exec -T caddy caddy reload --config /etc/caddy/Caddyfile || true
  fi
  cleanup_on_failure
fi

info "External health check passed"

# Step 12: Stop old slot
OLD_PROJECT="${APP_NAME}-${CURRENT_SLOT}"
if docker compose -p "$OLD_PROJECT" -f "$COMPOSE_FILE" ps --quiet 2>/dev/null | grep -q .; then
  info "Stopping old slot (${CURRENT_SLOT})..."
  docker compose -p "$OLD_PROJECT" -f "$COMPOSE_FILE" down
  info "Old slot stopped"
else
  # Also check for a non-slotted project (first deploy migration)
  if docker compose -p "$APP_NAME" -f "$COMPOSE_FILE" ps --quiet 2>/dev/null | grep -q .; then
    info "Stopping legacy (non-slotted) containers..."
    docker compose -p "$APP_NAME" -f "$COMPOSE_FILE" down
    info "Legacy containers stopped"
  fi
fi

# Step 13: Record active slot
echo "$NEXT_SLOT" > "$SLOT_FILE"

# Success
echo ""
info "=== Deploy Complete ==="
info "App:    ${APP_NAME}"
info "Slot:   ${NEXT_SLOT}"
info "Domain: https://${APP_DOMAIN}"
info "Zero-downtime blue-green deploy successful"

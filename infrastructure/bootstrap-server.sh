#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

MARKER="/opt/platform/.bootstrapped"

# --- Preflight ---

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

if [[ ! -f /etc/os-release ]]; then
  error "/etc/os-release not found — cannot verify OS"
fi

# shellcheck source=/dev/null
source /etc/os-release

if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "12" ]]; then
  error "This script requires Debian 12. Detected: ${PRETTY_NAME:-unknown}"
fi

info "Debian 12 detected"

if [[ -f "$MARKER" ]]; then
  warn "Server was previously bootstrapped on $(cat "$MARKER"). Re-running is safe (idempotent)."
fi

echo

# --- System Packages ---

echo "Installing system packages..."
apt-get update -qq
apt-get install -y -qq git curl ufw > /dev/null
info "System packages installed (git, curl, ufw)"

# --- Firewall ---

if ufw status | grep -q "Status: active"; then
  info "UFW already active"
else
  ufw allow 22/tcp > /dev/null
  ufw allow 80/tcp > /dev/null
  ufw allow 443/tcp > /dev/null
  ufw --force enable > /dev/null
  info "UFW enabled (ports 22, 80, 443)"
fi

# Ensure rules exist even if UFW was already active
ufw allow 22/tcp > /dev/null 2>&1 || true
ufw allow 80/tcp > /dev/null 2>&1 || true
ufw allow 443/tcp > /dev/null 2>&1 || true

# --- Docker ---

if command -v docker &>/dev/null; then
  info "Docker already installed ($(docker --version))"
else
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  info "Docker installed"
fi

if docker compose version &>/dev/null; then
  info "Docker Compose plugin available"
else
  error "Docker Compose plugin not found. Expected 'docker compose' to work after Docker install."
fi

# --- Deploy User ---

if id "deploy" &>/dev/null; then
  info "User 'deploy' already exists"
else
  useradd -m -s /bin/bash deploy
  info "User 'deploy' created"
fi

if groups deploy | grep -q docker; then
  info "User 'deploy' already in docker group"
else
  usermod -aG docker deploy
  info "User 'deploy' added to docker group"
fi

DEPLOY_SSH_DIR="/home/deploy/.ssh"
if [[ ! -d "$DEPLOY_SSH_DIR" ]]; then
  mkdir -p "$DEPLOY_SSH_DIR"
  touch "$DEPLOY_SSH_DIR/authorized_keys"
  chmod 700 "$DEPLOY_SSH_DIR"
  chmod 600 "$DEPLOY_SSH_DIR/authorized_keys"
  chown -R deploy:deploy "$DEPLOY_SSH_DIR"
  info "SSH directory created for deploy user"
else
  info "SSH directory already exists for deploy user"
fi

# --- Directories ---

for dir in /data/postgres /data/redis /data/minio /data/caddy /opt/apps /opt/platform /opt/platform/caddy-apps; do
  mkdir -p "$dir"
done
chown -R deploy:deploy /data /opt/apps /opt/platform
info "Directory structure created (/data/*, /opt/apps, /opt/platform)"

# --- Docker Network ---

if docker network inspect towlion &>/dev/null; then
  info "Docker network 'towlion' already exists"
else
  docker network create towlion
  info "Docker network 'towlion' created"
fi

# --- Credentials ---

ENV_FILE="/opt/platform/.env"

if [[ -f "$ENV_FILE" ]]; then
  warn "Credentials file already exists at $ENV_FILE — skipping generation"
else
  POSTGRES_PASSWORD=$(openssl rand -base64 24)
  MINIO_ROOT_USER="minio-admin"
  MINIO_ROOT_PASSWORD=$(openssl rand -base64 24)

  cat > "$ENV_FILE" <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
ACME_EMAIL=admin@localhost
EOF

  chmod 600 "$ENV_FILE"
  chown deploy:deploy "$ENV_FILE"
  info "Credentials generated and written to $ENV_FILE"
fi

# --- Caddyfile ---

CADDYFILE="/opt/platform/Caddyfile"

if [[ -f "$CADDYFILE" ]]; then
  info "Caddyfile already exists"
else
  cat > "$CADDYFILE" <<'EOF'
{
    email {$ACME_EMAIL:admin@localhost}
}

import /etc/caddy/apps/*.caddy
EOF

  chown deploy:deploy "$CADDYFILE"
  info "Caddyfile created at $CADDYFILE"
fi

# --- Platform Compose File ---

COMPOSE_FILE="/opt/platform/docker-compose.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
  info "docker-compose.yml already exists"
else
  cat > "$COMPOSE_FILE" <<'EOF'
services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    env_file: .env
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - /data/postgres:/var/lib/postgresql/data
    networks:
      - towlion
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    restart: unless-stopped
    volumes:
      - /data/redis:/data
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  minio:
    image: minio/minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    env_file: .env
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - /data/minio:/data
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 10s
      timeout: 5s
      retries: 5

  caddy:
    image: caddy:2
    restart: unless-stopped
    env_file: .env
    dns:
      - 8.8.8.8
      - 1.1.1.1
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy-apps:/etc/caddy/apps:ro
      - /data/caddy/data:/data
      - /data/caddy/config:/config
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "caddy", "version"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  towlion:
    external: true
EOF

  chown deploy:deploy "$COMPOSE_FILE"
  info "docker-compose.yml created at $COMPOSE_FILE"
fi

# --- Start Services ---

echo
echo "Starting platform services..."
cd /opt/platform
docker compose up -d

# Verify each service is running
echo "Verifying services..."
ALL_HEALTHY=true
for service in postgres redis minio caddy; do
  if docker compose ps --format json "$service" 2>/dev/null | grep -q '"running"'; then
    info "$service is running"
  else
    warn "$service may not be running yet — check with: docker compose -f $COMPOSE_FILE ps"
    ALL_HEALTHY=false
  fi
done

if $ALL_HEALTHY; then
  info "All platform services are running"
fi

# --- Mark as Bootstrapped ---

date -Iseconds > "$MARKER"

# --- Summary ---

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Server bootstrap complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Platform services running at /opt/platform:"
echo "  - PostgreSQL 16 (port 5432, internal)"
echo "  - Redis 7 (port 6379, internal)"
echo "  - MinIO (port 9000/9001, internal)"
echo "  - Caddy 2 (ports 80, 443)"
echo
echo "Credentials: $ENV_FILE"
if [[ -f "$ENV_FILE" ]]; then
  echo
  echo "  Generated credentials:"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  echo "  POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-<see $ENV_FILE>}"
  echo "  MINIO_ROOT_USER=${MINIO_ROOT_USER:-<see $ENV_FILE>}"
  echo "  MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-<see $ENV_FILE>}"
fi
echo
echo "Next steps:"
echo "  1. Add your SSH public key to /home/deploy/.ssh/authorized_keys"
echo "  2. Configure DNS — point your domain to this server's IP"
echo "  3. Update ACME_EMAIL in $ENV_FILE to a real email for TLS certificates"
echo "  4. Set GitHub Actions secrets on your app repo:"
echo "     SERVER_HOST, SERVER_USER (deploy), SERVER_SSH_KEY, APP_DOMAIN"
echo "  5. Create app dir, clone repo, create deploy/.env from template"
echo "  6. Push to main — deployment runs automatically"

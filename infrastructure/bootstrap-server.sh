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
apt-get install -y -qq git curl ufw vnstat unattended-upgrades apt-listchanges > /dev/null
info "System packages installed (git, curl, ufw, vnstat, unattended-upgrades)"

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

# --- Unattended Upgrades ---

UA_CONFIG="/etc/apt/apt.conf.d/50unattended-upgrades"
if [[ -f "$UA_CONFIG" ]]; then
  info "Unattended-upgrades config already exists"
else
  cat > "$UA_CONFIG" <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  info "Unattended-upgrades config created"
fi

AUTO_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
if [[ ! -f "$AUTO_UPGRADES" ]]; then
  cat > "$AUTO_UPGRADES" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  info "Auto-upgrades schedule configured"
fi

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

for dir in \
  /data/postgres /data/redis /data/minio /data/caddy /data/loki /data/grafana \
  /data/backups/postgres \
  /opt/apps /opt/platform /opt/platform/caddy-apps /opt/platform/credentials \
  /opt/platform/grafana/provisioning/datasources \
  /opt/platform/grafana/provisioning/dashboards \
  /opt/platform/grafana/dashboards \
  /opt/platform/infrastructure; do
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
  GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24)

  cat > "$ENV_FILE" <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
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

# --- Loki Config ---

LOKI_CONFIG="/opt/platform/loki-config.yml"
if [[ -f "$LOKI_CONFIG" ]]; then
  info "Loki config already exists"
else
  cat > "$LOKI_CONFIG" <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

limits_config:
  retention_period: 336h

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_cancel_period: 10m
EOF

  chown deploy:deploy "$LOKI_CONFIG"
  info "Loki config created at $LOKI_CONFIG"
fi

# --- Promtail Config ---

PROMTAIL_CONFIG="/opt/platform/promtail-config.yml"
if [[ -f "$PROMTAIL_CONFIG" ]]; then
  info "Promtail config already exists"
else
  cat > "$PROMTAIL_CONFIG" <<'EOF'
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_compose_project']
        target_label: 'project'
      - source_labels: ['__meta_docker_compose_service']
        target_label: 'service'
EOF

  chown deploy:deploy "$PROMTAIL_CONFIG"
  info "Promtail config created at $PROMTAIL_CONFIG"
fi

# --- Grafana Provisioning ---

GRAFANA_DS="/opt/platform/grafana/provisioning/datasources/datasources.yml"
if [[ -f "$GRAFANA_DS" ]]; then
  info "Grafana datasource config already exists"
else
  cat > "$GRAFANA_DS" <<'EOF'
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
EOF

  chown deploy:deploy "$GRAFANA_DS"
  info "Grafana datasource config created"
fi

GRAFANA_DASH_PROV="/opt/platform/grafana/provisioning/dashboards/dashboards.yml"
if [[ -f "$GRAFANA_DASH_PROV" ]]; then
  info "Grafana dashboard provisioner already exists"
else
  cat > "$GRAFANA_DASH_PROV" <<'EOF'
apiVersion: 1
providers:
  - name: Towlion
    folder: ''
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

  chown deploy:deploy "$GRAFANA_DASH_PROV"
  info "Grafana dashboard provisioner created"
fi

# --- Grafana Dashboard JSON ---

GRAFANA_DASHBOARD="/opt/platform/grafana/dashboards/platform-overview.json"
if [[ -f "$GRAFANA_DASHBOARD" ]]; then
  info "Grafana dashboard already exists"
else
  cat > "$GRAFANA_DASHBOARD" <<'DASHEOF'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "panels": [
    {
      "title": "Log Stream",
      "type": "logs",
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
      "datasource": { "type": "loki", "uid": "" },
      "targets": [
        {
          "expr": "{service=~\".+\"}",
          "refId": "A"
        }
      ],
      "options": {
        "showTime": true,
        "sortOrder": "Descending",
        "enableLogDetails": true
      }
    },
    {
      "title": "Error Rate (per service, 5m)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 10 },
      "datasource": { "type": "loki", "uid": "" },
      "targets": [
        {
          "expr": "sum by (service) (count_over_time({service=~\".+\"} |= \"ERROR\" [5m]))",
          "legendFormat": "{{service}}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "custom": {
            "drawStyle": "bars",
            "fillOpacity": 30
          }
        }
      }
    },
    {
      "title": "Container Logs by App",
      "type": "logs",
      "gridPos": { "h": 10, "w": 12, "x": 12, "y": 10 },
      "datasource": { "type": "loki", "uid": "" },
      "targets": [
        {
          "expr": "{project=~\"$app\"}",
          "refId": "A"
        }
      ],
      "options": {
        "showTime": true,
        "sortOrder": "Descending",
        "enableLogDetails": true
      }
    },
    {
      "title": "System Info",
      "type": "text",
      "gridPos": { "h": 4, "w": 24, "x": 0, "y": 20 },
      "options": {
        "mode": "markdown",
        "content": "## Towlion Platform Overview\n\nThis dashboard shows logs from all containers on the platform.\n\n- **Log Stream**: All container logs (filter by service label)\n- **Error Rate**: Count of ERROR lines per service over 5-minute windows\n- **Container Logs by App**: Select an app from the dropdown to filter logs\n\nAlerts are managed by `check-alerts.sh` (cron every 5 min) and create GitHub Issues on the `towlion/platform` repo."
      }
    }
  ],
  "schemaVersion": 39,
  "tags": ["towlion"],
  "templating": {
    "list": [
      {
        "name": "app",
        "type": "query",
        "datasource": { "type": "loki", "uid": "" },
        "query": "label_values(project)",
        "refresh": 2,
        "multi": false,
        "includeAll": true,
        "allValue": ".+"
      }
    ]
  },
  "time": { "from": "now-1h", "to": "now" },
  "title": "Platform Overview",
  "uid": "towlion-platform-overview"
}
DASHEOF

  chown deploy:deploy "$GRAFANA_DASHBOARD"
  info "Grafana dashboard created"
fi

# --- Grafana Caddy Route ---

OPS_CADDY="/opt/platform/caddy-apps/ops.caddy"
if [[ -f "$OPS_CADDY" ]]; then
  info "Grafana Caddy route already exists"
else
  cat > "$OPS_CADDY" <<'EOF'
ops.anulectra.com {
    reverse_proxy grafana:3000
}
EOF

  chown deploy:deploy "$OPS_CADDY"
  info "Grafana Caddy route created at $OPS_CADDY"
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
    deploy:
      resources:
        limits:
          cpus: '1.00'
          memory: 1G
        reservations:
          cpus: '0.50'
          memory: 512M

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
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
        reservations:
          cpus: '0.10'
          memory: 128M

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
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M

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
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 256M
        reservations:
          cpus: '0.10'
          memory: 128M

  loki:
    image: grafana/loki:3.0.0
    restart: unless-stopped
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki-config.yml:/etc/loki/loki-config.yml:ro
      - /data/loki:/loki
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--output-document=-", "http://localhost:3100/ready"]
      interval: 15s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 128M

  promtail:
    image: grafana/promtail:3.0.0
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - ./promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - towlion
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
        reservations:
          cpus: '0.10'
          memory: 64M

  grafana:
    image: grafana/grafana-oss:11.0.0
    restart: unless-stopped
    env_file: .env
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_SERVER_ROOT_URL: https://ops.anulectra.com
    volumes:
      - /data/grafana:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--output-document=-", "http://localhost:3000/api/health"]
      interval: 15s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 128M

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
for service in postgres redis minio caddy loki promtail grafana; do
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

# --- Copy Infrastructure Scripts ---

SCRIPT_DIR="/opt/platform/infrastructure"
for script in create-app-credentials.sh backup-postgres.sh restore-postgres.sh \
              check-alerts.sh update-images.sh usage-report.sh; do
  SRC_SCRIPT="$(dirname "$0")/$script"
  if [[ -f "$SRC_SCRIPT" ]]; then
    cp "$SRC_SCRIPT" "$SCRIPT_DIR/$script"
    chmod +x "$SCRIPT_DIR/$script"
  fi
done
chown -R deploy:deploy "$SCRIPT_DIR"
info "Infrastructure scripts copied to $SCRIPT_DIR"

# --- Cron Jobs ---

DEPLOY_CRON=$(crontab -u deploy -l 2>/dev/null || true)

# Daily PostgreSQL backup at 02:00
BACKUP_CRON="0 2 * * * /opt/platform/infrastructure/backup-postgres.sh >> /var/log/towlion-backup.log 2>&1"
if echo "$DEPLOY_CRON" | grep -q "backup-postgres"; then
  info "Backup cron job already exists"
else
  DEPLOY_CRON=$(echo "$DEPLOY_CRON"; echo "$BACKUP_CRON")
  info "Backup cron job added (daily at 02:00)"
fi

# Alert check every 5 minutes
ALERT_CRON="*/5 * * * * /opt/platform/infrastructure/check-alerts.sh >> /var/log/towlion-alerts.log 2>&1"
if echo "$DEPLOY_CRON" | grep -q "check-alerts"; then
  info "Alert cron job already exists"
else
  DEPLOY_CRON=$(echo "$DEPLOY_CRON"; echo "$ALERT_CRON")
  info "Alert cron job added (every 5 minutes)"
fi

# Weekly image update — Sundays at 03:00
IMAGE_CRON="0 3 * * 0 /opt/platform/infrastructure/update-images.sh >> /var/log/towlion-image-update.log 2>&1"
if echo "$DEPLOY_CRON" | grep -q "update-images"; then
  info "Image update cron job already exists"
else
  DEPLOY_CRON=$(echo "$DEPLOY_CRON"; echo "$IMAGE_CRON")
  info "Image update cron job added (weekly Sunday 03:00)"
fi

echo "$DEPLOY_CRON" | crontab -u deploy -

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
echo "  - Loki 3.0 (port 3100, internal)"
echo "  - Promtail 3.0 (log collector)"
echo "  - Grafana 11.0 (dashboard, via Caddy at ops domain)"
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
  echo "  GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-<see $ENV_FILE>}"
fi
echo
echo "Cron jobs installed for deploy user:"
echo "  - PostgreSQL backup: daily at 02:00"
echo "  - Health check alerts: every 5 minutes"
echo "  - Image updates: weekly Sunday at 03:00"
echo
echo "Next steps:"
echo "  1. Add your SSH public key to /home/deploy/.ssh/authorized_keys"
echo "  2. Configure DNS — point your domain to this server's IP"
echo "  3. Update ACME_EMAIL in $ENV_FILE to a real email for TLS certificates"
echo "  4. Set GitHub Actions secrets on your app repo:"
echo "     SERVER_HOST, SERVER_USER (deploy), SERVER_SSH_KEY, APP_DOMAIN"
echo "  5. Run create-app-credentials.sh <app-name> for per-app credentials"
echo "  6. Create app dir, clone repo, create deploy/.env from template"
echo "  7. Push to main — deployment runs automatically"
echo "  8. Set GITHUB_TOKEN in $ENV_FILE for alert issue creation (optional)"

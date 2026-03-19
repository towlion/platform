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

# Optional environment variables:
#   ACME_EMAIL      - Email for Let's Encrypt TLS certificates (required for production)
#   OPS_DOMAIN      - Domain for Grafana dashboard (e.g., ops.example.com)
#   ALERT_REPO      - GitHub repo for alert issues (e.g., youruser/platform)
#   ENABLE_METRICS  - Set to "true" to start Prometheus, cAdvisor, and node-exporter

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
apt-get install -y -qq git curl ufw vnstat unattended-upgrades apt-listchanges fail2ban cron > /dev/null
info "System packages installed (git, curl, ufw, vnstat, unattended-upgrades, fail2ban)"

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

# --- fail2ban ---

F2B_JAIL="/etc/fail2ban/jail.local"
if [[ -f "$F2B_JAIL" ]]; then
  info "fail2ban jail config already exists"
else
  cat > "$F2B_JAIL" <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 5
EOF

  systemctl enable fail2ban
  systemctl restart fail2ban
  info "fail2ban configured (SSH jail: maxretry=5, bantime=3600s, findtime=600s)"
fi

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

# --- Trivy ---

if command -v trivy &>/dev/null; then
  info "Trivy already installed"
else
  apt-get install -y -qq wget apt-transport-https gnupg > /dev/null
  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" > /etc/apt/sources.list.d/trivy.list
  apt-get update -qq
  apt-get install -y -qq trivy > /dev/null
  info "Trivy installed"
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

SUDOERS_FILE="/etc/sudoers.d/deploy"
if [[ -f "$SUDOERS_FILE" ]]; then
  info "Sudoers entry for deploy already exists"
else
  echo "deploy ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  info "Passwordless sudo granted to deploy user"
fi

DEPLOY_SSH_DIR="/home/deploy/.ssh"
if [[ ! -d "$DEPLOY_SSH_DIR" ]]; then
  mkdir -p "$DEPLOY_SSH_DIR"
  if [[ -n "${SUDO_USER:-}" ]] && [[ -f "/home/${SUDO_USER}/.ssh/authorized_keys" ]]; then
    cp "/home/${SUDO_USER}/.ssh/authorized_keys" "$DEPLOY_SSH_DIR/authorized_keys"
    info "Copied SSH keys from ${SUDO_USER} to deploy user"
  elif [[ -f /root/.ssh/authorized_keys ]]; then
    cp /root/.ssh/authorized_keys "$DEPLOY_SSH_DIR/authorized_keys"
    info "Copied SSH keys from root to deploy user"
  else
    touch "$DEPLOY_SSH_DIR/authorized_keys"
    warn "No SSH keys found to copy — add keys to /home/deploy/.ssh/authorized_keys manually"
  fi
  chmod 700 "$DEPLOY_SSH_DIR"
  chmod 600 "$DEPLOY_SSH_DIR/authorized_keys"
  chown -R deploy:deploy "$DEPLOY_SSH_DIR"
  info "SSH directory created for deploy user"
else
  info "SSH directory already exists for deploy user"
fi

# --- SSH Hardening ---

SSHD_HARDENING="/etc/ssh/sshd_config.d/99-towlion-hardening.conf"
if [[ -f "$SSHD_HARDENING" ]]; then
  info "SSH hardening config already exists"
elif [[ ! -s /home/deploy/.ssh/authorized_keys ]]; then
  warn "Skipping SSH hardening — deploy user has no SSH keys"
  warn "Add keys to /home/deploy/.ssh/authorized_keys, then re-run bootstrap to harden SSH"
else
  cat > "$SSHD_HARDENING" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
X11Forwarding no
EOF

  systemctl restart sshd
  info "SSH hardened (no root login, no password auth, MaxAuthTries=3, no X11)"
fi

# --- Directories ---

for dir in \
  /data/postgres /data/redis /data/minio /data/caddy /data/loki /data/grafana /data/prometheus \
  /data/backups/postgres \
  /opt/apps /opt/platform /opt/platform/caddy-apps /opt/platform/credentials \
  /opt/platform/grafana/provisioning/datasources \
  /opt/platform/grafana/provisioning/dashboards \
  /opt/platform/grafana/dashboards \
  /opt/platform/infrastructure; do
  mkdir -p "$dir"
done
chown -R deploy:deploy /data /opt/apps /opt/platform
# Grafana runs as UID 472, Loki as UID 10001 inside their containers
chown -R 472:472 /data/grafana
chown -R 10001:10001 /data/loki
# Prometheus runs as nobody (UID 65534) inside its container
chown -R 65534:65534 /data/prometheus
# Postgres and Redis run as UID 999 inside their containers
chown -R 999:999 /data/postgres
chown -R 999:999 /data/redis
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
ACME_EMAIL=${ACME_EMAIL:-admin@localhost}
OPS_DOMAIN=${OPS_DOMAIN:-localhost}
ALERT_REPO=${ALERT_REPO:-}
EOF

  # Conditionally enable metrics compose profile
  if [[ "${ENABLE_METRICS:-}" == "true" ]]; then
    echo "COMPOSE_PROFILES=metrics" >> "$ENV_FILE"
    info "Resource metrics enabled (COMPOSE_PROFILES=metrics)"
  fi

  chmod 600 "$ENV_FILE"
  chown deploy:deploy "$ENV_FILE"
  info "Credentials generated and written to $ENV_FILE"

  if [[ "${ACME_EMAIL:-admin@localhost}" == "admin@localhost" ]]; then
    warn "ACME_EMAIL is admin@localhost — TLS certificates will fail. Re-run with ACME_EMAIL=you@example.com"
  fi
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

(security_headers) {
    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
        -Server
    }
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
  retention_period: 2160h

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
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_cancel_period: 10m
  delete_request_store: filesystem
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

# --- Prometheus Config ---

PROMETHEUS_CONFIG="/opt/platform/prometheus.yml"
if [[ -f "$PROMETHEUS_CONFIG" ]]; then
  info "Prometheus config already exists"
else
  cat > "$PROMETHEUS_CONFIG" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF

  chown deploy:deploy "$PROMETHEUS_CONFIG"
  info "Prometheus config created at $PROMETHEUS_CONFIG"
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
    uid: towlion-loki
    isDefault: true
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    uid: towlion-prometheus
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
      "datasource": { "type": "loki", "uid": "towlion-loki" },
      "targets": [
        {
          "expr": "{container=~\".+\"}",
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
      "title": "Error Rate (per container, 5m)",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 10 },
      "datasource": { "type": "loki", "uid": "towlion-loki" },
      "targets": [
        {
          "expr": "sum by (container) (count_over_time({container=~\".+\"} |= \"ERROR\" [5m]))",
          "legendFormat": "{{container}}",
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
      "datasource": { "type": "loki", "uid": "towlion-loki" },
      "targets": [
        {
          "expr": "{container=~\"$app\"}",
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
        "content": "## Towlion Platform Overview\n\nThis dashboard shows logs from all containers on the platform.\n\n- **Log Stream**: All container logs (filter by container label)\n- **Error Rate**: Count of ERROR lines per container over 5-minute windows\n- **Container Logs by App**: Select an app from the dropdown to filter logs\n\nAlerts are managed by `check-alerts.sh` (cron every 5 min) and create GitHub Issues when ALERT_REPO is configured."
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
        "datasource": { "type": "loki", "uid": "towlion-loki" },
        "query": "label_values(container)",
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

# --- Resource Metrics Dashboard ---

METRICS_DASHBOARD="/opt/platform/grafana/dashboards/resource-metrics.json"
if [[ -f "$METRICS_DASHBOARD" ]]; then
  info "Resource metrics dashboard already exists"
else
  cat > "$METRICS_DASHBOARD" <<'METRICSDASHEOF'
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "title": "CPU Usage",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "thresholds": {
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 60 },
              { "color": "red", "value": 85 }
            ]
          }
        }
      }
    },
    {
      "title": "Memory Usage",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "thresholds": {
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 70 },
              { "color": "red", "value": 90 }
            ]
          }
        }
      }
    },
    {
      "title": "Disk Usage",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "100 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100)",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "thresholds": {
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 70 },
              { "color": "red", "value": 85 }
            ]
          }
        }
      }
    },
    {
      "title": "Uptime",
      "type": "stat",
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "node_time_seconds - node_boot_time_seconds",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "s"
        }
      }
    },
    {
      "title": "CPU Over Time",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
          "legendFormat": "CPU %",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "max": 100,
          "custom": { "fillOpacity": 20 }
        }
      }
    },
    {
      "title": "Memory Over Time",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 4 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes",
          "legendFormat": "Used",
          "refId": "A"
        },
        {
          "expr": "node_memory_MemTotal_bytes",
          "legendFormat": "Total",
          "refId": "B"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "custom": { "fillOpacity": 20 }
        }
      }
    },
    {
      "title": "Disk I/O",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "rate(node_disk_read_bytes_total[5m])",
          "legendFormat": "Read {{device}}",
          "refId": "A"
        },
        {
          "expr": "rate(node_disk_written_bytes_total[5m])",
          "legendFormat": "Write {{device}}",
          "refId": "B"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "Bps",
          "custom": { "fillOpacity": 20 }
        }
      }
    },
    {
      "title": "Network I/O",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 12 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "rate(node_network_receive_bytes_total{device!=\"lo\"}[5m])",
          "legendFormat": "RX {{device}}",
          "refId": "A"
        },
        {
          "expr": "rate(node_network_transmit_bytes_total{device!=\"lo\"}[5m])",
          "legendFormat": "TX {{device}}",
          "refId": "B"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "Bps",
          "custom": { "fillOpacity": 20 }
        }
      }
    },
    {
      "title": "Container Overview",
      "type": "table",
      "gridPos": { "h": 8, "w": 24, "x": 0, "y": 20 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "rate(container_cpu_usage_seconds_total{name!=\"\"}[5m]) * 100",
          "legendFormat": "{{name}}",
          "refId": "A",
          "format": "table",
          "instant": true
        },
        {
          "expr": "container_memory_usage_bytes{name!=\"\"}",
          "legendFormat": "{{name}}",
          "refId": "B",
          "format": "table",
          "instant": true
        },
        {
          "expr": "container_spec_memory_limit_bytes{name!=\"\"}",
          "legendFormat": "{{name}}",
          "refId": "C",
          "format": "table",
          "instant": true
        },
        {
          "expr": "rate(container_network_receive_bytes_total{name!=\"\"}[5m])",
          "legendFormat": "{{name}}",
          "refId": "D",
          "format": "table",
          "instant": true
        },
        {
          "expr": "rate(container_network_transmit_bytes_total{name!=\"\"}[5m])",
          "legendFormat": "{{name}}",
          "refId": "E",
          "format": "table",
          "instant": true
        }
      ],
      "transformations": [
        {
          "id": "merge",
          "options": {}
        }
      ]
    },
    {
      "title": "CPU per Container",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 28 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "rate(container_cpu_usage_seconds_total{name=~\"$container\"}[5m]) * 100",
          "legendFormat": "{{name}}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "custom": { "fillOpacity": 20 }
        }
      }
    },
    {
      "title": "Memory per Container",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 12, "x": 12, "y": 28 },
      "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
      "targets": [
        {
          "expr": "container_memory_usage_bytes{name=~\"$container\"}",
          "legendFormat": "{{name}}",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "custom": { "fillOpacity": 20 }
        }
      }
    }
  ],
  "schemaVersion": 39,
  "tags": ["towlion", "metrics"],
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": { "type": "prometheus", "uid": "towlion-prometheus" },
        "query": "label_values(container_cpu_usage_seconds_total{name!=\"\"}, name)",
        "refresh": 2,
        "multi": true,
        "includeAll": true,
        "allValue": ".+"
      }
    ]
  },
  "time": { "from": "now-1h", "to": "now" },
  "title": "Resource Metrics",
  "uid": "towlion-resource-metrics"
}
METRICSDASHEOF

  chown deploy:deploy "$METRICS_DASHBOARD"
  info "Resource metrics dashboard created"
fi

# --- App Dashboard ---

APP_DASHBOARD="/opt/platform/grafana/dashboards/app-dashboard.json"
if [[ -f "$APP_DASHBOARD" ]]; then
  info "App dashboard already exists"
else
  SRC_APP_DASH="$(dirname "$0")/grafana-dashboards/app-dashboard.json"
  if [[ -f "$SRC_APP_DASH" ]]; then
    cp "$SRC_APP_DASH" "$APP_DASHBOARD"
    chown deploy:deploy "$APP_DASHBOARD"
    info "App dashboard created"
  else
    warn "app-dashboard.json not found in infrastructure/grafana-dashboards/ — skipping"
  fi
fi

# --- Grafana Alerting Rules ---

ALERTING_DIR="/opt/platform/grafana/provisioning/alerting"
mkdir -p "$ALERTING_DIR"
chown deploy:deploy "$ALERTING_DIR"

ALERT_RULES="$ALERTING_DIR/rules.yml"
if [[ -f "$ALERT_RULES" ]]; then
  info "Grafana alerting rules already exist"
else
  cat > "$ALERT_RULES" <<'EOF'
apiVersion: 1
groups:
  - orgId: 1
    name: towlion-alerts
    folder: Towlion
    interval: 5m
    rules:
      - uid: error-rate-spike
        title: Error Rate Spike
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: towlion-loki
            model:
              expr: "sum(count_over_time({container=~\".+\"} | json | __error__=`` | status_code >= 500 [5m]))"
              refId: A
          - refId: C
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: __expr__
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    type: gt
                    params: [10]
              refId: C
        for: 0s
        labels:
          severity: warning
        annotations:
          summary: "More than 10 HTTP 5xx errors in the last 5 minutes"

      - uid: container-down
        title: Container Down
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: towlion-prometheus
            model:
              expr: "absent(container_last_seen{name=~\".+\"})"
              refId: A
          - refId: C
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: __expr__
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    type: gt
                    params: [0]
              refId: C
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "A container is not reporting metrics (requires metrics profile)"

      - uid: disk-usage-high
        title: Disk Usage Above 85%
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: towlion-prometheus
            model:
              expr: "100 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100)"
              refId: A
          - refId: C
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: __expr__
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    type: gt
                    params: [85]
              refId: C
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Root filesystem usage is above 85%"
EOF

  chown deploy:deploy "$ALERT_RULES"
  info "Grafana alerting rules created (3 rules)"
fi

# --- Grafana Caddy Route ---

OPS_CADDY="/opt/platform/caddy-apps/ops.caddy"
if [[ -f "$OPS_CADDY" ]]; then
  info "Grafana Caddy route already exists"
elif [[ -n "${OPS_DOMAIN:-}" ]]; then
  cat > "$OPS_CADDY" <<EOF
${OPS_DOMAIN} {
    import security_headers
    reverse_proxy grafana:3000
}
EOF

  chown deploy:deploy "$OPS_CADDY"
  info "Grafana Caddy route created at $OPS_CADDY"
else
  info "OPS_DOMAIN not set — skipping Grafana Caddy route (set OPS_DOMAIN to enable)"
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
    read_only: true
    tmpfs:
      - /tmp
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
    read_only: true
    tmpfs:
      - /tmp
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - ./promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log/docker-audit.log:/var/log/docker-audit.log:ro
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
      GF_SERVER_ROOT_URL: https://${OPS_DOMAIN:-localhost}
      GF_UNIFIED_ALERTING_ENABLED: "true"
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

  prometheus:
    image: prom/prometheus:v2.53.0
    restart: unless-stopped
    profiles:
      - metrics
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=7d'
      - '--storage.tsdb.retention.size=500MB'
    volumes:
      - /data/prometheus:/prometheus
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "-O", "/dev/null", "http://localhost:9090/-/healthy"]
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

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    restart: unless-stopped
    profiles:
      - metrics
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro
    networks:
      - towlion
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "-O", "/dev/null", "http://localhost:8080/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 128M
        reservations:
          cpus: '0.10'
          memory: 64M

  node-exporter:
    image: prom/node-exporter:v1.8.1
    restart: unless-stopped
    profiles:
      - metrics
    pid: host
    volumes:
      - /:/host:ro,rslave
    command:
      - '--path.rootfs=/host'
    networks:
      - towlion
    deploy:
      resources:
        limits:
          cpus: '0.25'
          memory: 64M
        reservations:
          cpus: '0.10'
          memory: 32M

networks:
  towlion:
    external: true
EOF

  chown deploy:deploy "$COMPOSE_FILE"
  info "docker-compose.yml created at $COMPOSE_FILE"
fi

# --- Docker Event Audit Logging ---

DOCKER_AUDIT_SERVICE="/etc/systemd/system/docker-audit.service"
if [[ -f "$DOCKER_AUDIT_SERVICE" ]]; then
  info "Docker audit service already exists"
else
  cat > "$DOCKER_AUDIT_SERVICE" <<'EOF'
[Unit]
Description=Docker Event Audit Log
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/docker events --format '{"time":"{{.Time}}","action":"{{.Action}}","type":"{{.Type}}","actor":"{{.Actor.Attributes.name}}"}'
StandardOutput=append:/var/log/docker-audit.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable docker-audit
  systemctl start docker-audit
  info "Docker event audit logging enabled (/var/log/docker-audit.log)"
fi

# Add Promtail scrape config for docker audit log if not already present
if ! grep -q "docker-audit" "$PROMTAIL_CONFIG" 2>/dev/null; then
  cat >> "$PROMTAIL_CONFIG" <<'EOF'

  - job_name: docker-audit
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker-audit
          __path__: /var/log/docker-audit.log
EOF

  chown deploy:deploy "$PROMTAIL_CONFIG"
  info "Promtail config updated with docker-audit scrape target"
fi

# --- Log Rotation ---

LOGROTATE_CONF="/etc/logrotate.d/towlion"
LOGROTATE_CONTENT='/var/log/towlion-*.log /var/log/docker-audit.log {
    daily
    rotate 90
    compress
    missingok
    notifempty
    postrotate
        systemctl restart docker-audit.service 2>/dev/null || true
    endscript
}'

if [[ -f "$LOGROTATE_CONF" ]] && echo "$LOGROTATE_CONTENT" | diff -q - "$LOGROTATE_CONF" >/dev/null 2>&1; then
  info "Logrotate config already up to date"
else
  echo "$LOGROTATE_CONTENT" > "$LOGROTATE_CONF"
  info "Logrotate config created at $LOGROTATE_CONF"
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

# Check metrics services if profile is enabled
if docker compose ps --format json prometheus 2>/dev/null | grep -q '"running"'; then
  for service in prometheus cadvisor node-exporter; do
    if docker compose ps --format json "$service" 2>/dev/null | grep -q '"running"'; then
      info "$service is running"
    else
      warn "$service may not be running yet"
      ALL_HEALTHY=false
    fi
  done
fi

if $ALL_HEALTHY; then
  info "All platform services are running"
fi

# --- Copy Infrastructure Scripts ---

SCRIPT_DIR="/opt/platform/infrastructure"
for src in "$(dirname "$0")"/*.sh; do
  [[ "$(basename "$src")" == "bootstrap-server.sh" ]] && continue
  cp "$src" "$SCRIPT_DIR/"
  chmod +x "$SCRIPT_DIR/$(basename "$src")"
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
ALERT_CRON="*/5 * * * * . /opt/platform/.env && /opt/platform/infrastructure/check-alerts.sh >> /var/log/towlion-alerts.log 2>&1"
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

# Weekly image vulnerability scan — Sundays at 04:00 (after image update at 03:00)
SCAN_CRON="0 4 * * 0 /opt/platform/infrastructure/scan-images.sh >> /var/log/towlion-scan.log 2>&1"
if echo "$DEPLOY_CRON" | grep -q "scan-images"; then
  info "Image scan cron job already exists"
else
  DEPLOY_CRON=$(echo "$DEPLOY_CRON"; echo "$SCAN_CRON")
  info "Image scan cron job added (weekly Sunday 04:00)"
fi

# Weekly backup verification — Sundays at 05:00 (after image scan at 04:00)
VERIFY_CRON="0 5 * * 0 /opt/platform/infrastructure/verify-backup.sh --all >> /var/log/towlion-verify-backup.log 2>&1"
if echo "$DEPLOY_CRON" | grep -q "verify-backup"; then
  info "Backup verification cron job already exists"
else
  DEPLOY_CRON=$(echo "$DEPLOY_CRON"; echo "$VERIFY_CRON")
  info "Backup verification cron job added (weekly Sunday 05:00)"
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
if grep -q "COMPOSE_PROFILES=metrics" "$ENV_FILE" 2>/dev/null; then
  echo "  - Prometheus v2.53 (port 9090, internal)"
  echo "  - cAdvisor v0.49 (container metrics)"
  echo "  - Node Exporter v1.8 (host metrics)"
fi
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
echo "Security hardening applied:"
echo "  - fail2ban (SSH brute-force protection)"
echo "  - SSH hardened (no root login, no password auth)"
echo "  - Security headers on all Caddy sites"
echo "  - Trivy image scanning (deploy-time + weekly cron)"
echo
echo "Cron jobs installed for deploy user:"
echo "  - PostgreSQL backup: daily at 02:00"
echo "  - Health check alerts: every 5 minutes"
echo "  - Image updates: weekly Sunday at 03:00"
echo "  - Image vulnerability scan: weekly Sunday at 04:00"
echo
echo "Next steps:"
echo "  1. Add your SSH public key to /home/deploy/.ssh/authorized_keys"
echo "  2. Configure DNS — point your domain to this server's IP"
echo "  3. Set GitHub Actions secrets on your app repo:"
echo "     SERVER_HOST, SERVER_USER (deploy), SERVER_SSH_KEY, APP_DOMAIN"
echo "  4. Run create-app-credentials.sh <app-name> for per-app credentials"
echo "  5. Clone app repo to /opt/apps/<name>, create deploy/.env from template"
echo "  6. Push to main — deployment runs automatically"

if [[ "${ACME_EMAIL:-admin@localhost}" == "admin@localhost" ]]; then
  echo
  echo -e "${YELLOW}  ACTION REQUIRED: Set ACME_EMAIL in $ENV_FILE to a real email for TLS certificates.${NC}"
  echo "  Or re-run: sudo ACME_EMAIL=you@example.com bash bootstrap-server.sh"
fi

if [[ "${OPS_DOMAIN:-localhost}" == "localhost" ]]; then
  echo
  echo -e "${YELLOW}  OPTIONAL: Set OPS_DOMAIN in $ENV_FILE for Grafana dashboard access.${NC}"
  echo "  Or re-run: sudo OPS_DOMAIN=ops.example.com bash bootstrap-server.sh"
fi

if [[ -z "${ALERT_REPO:-}" ]]; then
  echo
  echo -e "${YELLOW}  OPTIONAL: Set ALERT_REPO in $ENV_FILE (e.g., youruser/platform) for GitHub issue alerts.${NC}"
  echo "  Also set GITHUB_TOKEN for issue creation."
fi

if ! grep -q "COMPOSE_PROFILES=metrics" "$ENV_FILE" 2>/dev/null; then
  echo
  echo "  To enable resource metrics: add COMPOSE_PROFILES=metrics to $ENV_FILE"
  echo "  Or re-run: sudo ENABLE_METRICS=true bash bootstrap-server.sh"
fi

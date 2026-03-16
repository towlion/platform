#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0
FAILURES=()

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); FAILURES+=("$1"); }

# --- OS ---

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "12" ]]; then
    pass "Debian 12 detected"
  else
    fail "Expected Debian 12, got ${PRETTY_NAME:-unknown}"
  fi
else
  fail "/etc/os-release not found"
fi

# --- Docker ---

if docker info &>/dev/null; then
  pass "Docker is running"
else
  fail "Docker is not running or not accessible"
fi

if docker compose version &>/dev/null; then
  pass "Docker Compose plugin available"
else
  fail "Docker Compose plugin not found"
fi

# --- Deploy User ---

if id "deploy" &>/dev/null; then
  pass "User 'deploy' exists"
else
  fail "User 'deploy' does not exist"
fi

if id "deploy" &>/dev/null && groups deploy | grep -q docker; then
  pass "User 'deploy' in docker group"
else
  fail "User 'deploy' not in docker group"
fi

# --- Directories ---

ALL_DIRS_OK=true
for dir in /data/postgres /data/redis /data/minio /data/caddy /data/loki /data/grafana /data/prometheus /data/backups/postgres /opt/apps /opt/platform /opt/platform/credentials; do
  if [[ ! -d "$dir" ]]; then
    ALL_DIRS_OK=false
    fail "Directory missing: $dir"
  fi
done
if $ALL_DIRS_OK; then
  pass "All required directories exist"
fi

# --- Docker Network ---

if docker network inspect towlion &>/dev/null; then
  pass "Docker network 'towlion' exists"
else
  fail "Docker network 'towlion' not found"
fi

# --- Credentials ---

ENV_FILE="/opt/platform/.env"
if [[ -f "$ENV_FILE" ]]; then
  PERMS=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null)
  if [[ "$PERMS" == "600" ]]; then
    pass "Credentials file exists with correct permissions (600)"
  else
    fail "Credentials file exists but permissions are $PERMS (expected 600)"
  fi
else
  fail "Credentials file not found at $ENV_FILE"
fi

# --- Platform Services ---

COMPOSE_FILE="/opt/platform/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  fail "Platform compose file not found at $COMPOSE_FILE"
else
  for service in postgres redis minio caddy loki promtail grafana; do
    if docker compose -f "$COMPOSE_FILE" ps --format json "$service" 2>/dev/null | grep -q '"running"'; then
      pass "$service is running"
    else
      fail "$service is not running"
    fi
  done

  # Metrics services (optional — only checked if running)
  if docker compose -f "$COMPOSE_FILE" ps --format json prometheus 2>/dev/null | grep -q '"running"'; then
    for service in prometheus cadvisor node-exporter; do
      if docker compose -f "$COMPOSE_FILE" ps --format json "$service" 2>/dev/null | grep -q '"running"'; then
        pass "$service is running"
      else
        fail "$service is not running"
      fi
    done
  fi
fi

# --- Service Health ---

if docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U postgres &>/dev/null; then
  pass "PostgreSQL is accepting connections"
else
  fail "PostgreSQL is not accepting connections"
fi

if docker compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
  pass "Redis is responding to PING"
else
  fail "Redis is not responding"
fi

if docker compose -f "$COMPOSE_FILE" exec -T minio curl -sf http://localhost:9000/minio/health/live &>/dev/null; then
  pass "MinIO health endpoint is live"
else
  fail "MinIO health endpoint is not responding"
fi

if curl -sf -o /dev/null http://localhost:80; then
  pass "Caddy is responding on port 80"
else
  fail "Caddy is not responding on port 80"
fi

# --- Loki Health ---

if wget -qO- http://localhost:3100/ready 2>/dev/null | grep -q "ready"; then
  pass "Loki is ready"
else
  fail "Loki is not ready"
fi

# --- Grafana Health ---

if wget -qO- http://localhost:3000/api/health 2>/dev/null | grep -q "ok"; then
  pass "Grafana is healthy"
else
  fail "Grafana is not healthy"
fi

# --- Prometheus Health (optional) ---

if docker compose -f "$COMPOSE_FILE" ps --format json prometheus 2>/dev/null | grep -q '"running"'; then
  if wget -qO- http://localhost:9090/-/healthy 2>/dev/null | grep -q "Prometheus Server is Healthy"; then
    pass "Prometheus is healthy"
  else
    fail "Prometheus is not healthy"
  fi
fi

# --- Security Hardening ---

if systemctl is-active fail2ban &>/dev/null; then
  pass "fail2ban is running"
else
  fail "fail2ban is not running"
fi

if [[ -f /etc/ssh/sshd_config.d/99-towlion-hardening.conf ]]; then
  pass "SSH hardening config present"
else
  fail "SSH hardening config missing (/etc/ssh/sshd_config.d/99-towlion-hardening.conf)"
fi

if command -v trivy &>/dev/null; then
  pass "Trivy is installed"
else
  fail "Trivy is not installed"
fi

# --- Firewall ---

if ufw status 2>/dev/null | grep -q "Status: active"; then
  pass "UFW is active"
  UFW_OK=true
  for port in 22 80 443; do
    if ! ufw status 2>/dev/null | grep -q "${port}/tcp.*ALLOW"; then
      UFW_OK=false
      fail "UFW: port $port/tcp not allowed"
    fi
  done
  if $UFW_OK; then
    pass "UFW allows ports 22, 80, 443"
  fi
else
  fail "UFW is not active"
fi

# --- Summary ---

echo
TOTAL=$((PASS + FAIL))
echo -e "${GREEN}Passed: $PASS${NC} / $TOTAL"
if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Failed: $FAIL${NC}"
  echo
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo -e "  ${RED}-${NC} $f"
  done
  exit 1
else
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
fi

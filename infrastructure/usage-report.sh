#!/usr/bin/env bash
set -euo pipefail

echo "Towlion Platform Usage Report — $(date)"
echo "=========================================="
echo

# 1. Disk Usage
echo "=== Disk Usage ==="
df -h / /data 2>/dev/null || df -h /
echo
echo "Per-directory:"
du -sh /data/postgres /data/redis /data/minio /data/caddy /data/loki /data/backups 2>/dev/null || echo "  Data directories not found"
echo
du -sh /opt/apps/*/ 2>/dev/null || echo "  No app directories found"
echo

# 2. Memory Usage
echo "=== Memory Usage ==="
free -h
echo
echo "Per-container:"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}" 2>/dev/null || echo "  Docker stats unavailable"
echo

# 3. Database Sizes
echo "=== Database Sizes ==="
docker compose -f /opt/platform/docker-compose.yml exec -T postgres \
  psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false ORDER BY pg_database_size(datname) DESC;" 2>/dev/null \
  || echo "  PostgreSQL not accessible"
echo

# 4. Containers
echo "=== Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null | sort || echo "  Docker not accessible"
echo
echo "Total: $(docker ps -q 2>/dev/null | wc -l) running, $(docker ps -aq 2>/dev/null | wc -l) total"
echo

# 5. Network Bandwidth
echo "=== Network Bandwidth ==="
vnstat -m --oneline 2>/dev/null || echo "  vnstat not available or not yet collecting data"
echo

# 6. Backups
echo "=== Backups ==="
# shellcheck disable=SC2012
ls -lh /data/backups/postgres/*.dump 2>/dev/null | tail -5 || echo "  No backups found"
echo "Backup count: $(find /data/backups/postgres -name '*.dump' 2>/dev/null | wc -l | tr -d ' ')"

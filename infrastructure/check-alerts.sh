#!/usr/bin/env bash
set -euo pipefail

# check-alerts.sh
# Cron script (every 5 min) that checks container health, disk, memory,
# TLS certs, restart counts, backup freshness, HTTP endpoints,
# and creates GitHub Issues on failure.

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ALERTS=()

# Check if ALERT_REPO and GITHUB_TOKEN are set (required for issue creation)
if [[ -z "${ALERT_REPO:-}" ]]; then
    echo "[$TIMESTAMP] WARNING: ALERT_REPO not set — alerts will be logged but not posted to GitHub"
    CREATE_ISSUES=false
elif [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "[$TIMESTAMP] WARNING: GITHUB_TOKEN not set, alerts will only be logged (not created as issues)"
    CREATE_ISSUES=false
else
    CREATE_ISSUES=true
fi

# 1. Check unhealthy containers
echo "[$TIMESTAMP] Checking container health..."
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | cut -d' ' -f2-)

    # Check if container is not "Up" or shows "(unhealthy)"
    if ! echo "$status" | grep -q "Up" || echo "$status" | grep -q "(unhealthy)"; then
        ALERTS+=("Container $name is unhealthy or down: $status")
    fi
done < <(docker ps -a --format '{{.Names}} {{.Status}}')

# 2. Check disk usage
echo "[$TIMESTAMP] Checking disk usage..."
DISK_USAGE=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
if [[ $DISK_USAGE -gt 80 ]]; then
    ALERTS+=("Disk usage at ${DISK_USAGE}% (threshold: 80%)")
fi

# 3. Check memory usage
echo "[$TIMESTAMP] Checking memory usage..."
MEMORY_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2*100}')
if [[ $MEMORY_USAGE -gt 90 ]]; then
    ALERTS+=("Memory usage at ${MEMORY_USAGE}% (threshold: 90%)")
fi

# 4. Check TLS certificate expiry
echo "[$TIMESTAMP] Checking TLS certificates..."
for conf in /opt/platform/caddy-apps/*.caddy; do
    [ -f "$conf" ] || continue
    domain=$(awk 'NF {print $1; exit}' "$conf")
    [ -z "$domain" ] && continue
    [[ "$domain" == "localhost" ]] && continue
    expiry=$(echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -n "$expiry" ]; then
        expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
        now_epoch=$(date +%s)
        if [ -n "$expiry_epoch" ]; then
            days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            if [ "$days_left" -lt 14 ]; then
                ALERTS+=("TLS cert for $domain expires in $days_left days")
            fi
        fi
    fi
done

# 5. Check container restart counts
echo "[$TIMESTAMP] Checking container restart counts..."
for name in $(docker ps -a --format '{{.Names}}'); do
    restarts=$(docker inspect --format='{{.RestartCount}}' "$name" 2>/dev/null || echo "0")
    if [ "$restarts" -gt 3 ]; then
        ALERTS+=("Container $name has restarted $restarts times")
    fi
done

# 6. Check backup freshness
echo "[$TIMESTAMP] Checking backup freshness..."
BACKUP_DIR="/data/backups/postgres"
if [ -d "$BACKUP_DIR" ]; then
    latest_backup=$(find "$BACKUP_DIR" -name "*.sql.gz" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $1}')
    if [ -n "$latest_backup" ]; then
        age_hours=$(( ($(date +%s) - ${latest_backup%.*}) / 3600 ))
        if [ "$age_hours" -gt 36 ]; then
            ALERTS+=("Most recent PostgreSQL backup is $age_hours hours old (threshold: 36h)")
        fi
    else
        ALERTS+=("No PostgreSQL backups found in $BACKUP_DIR")
    fi
fi

# 7. Check HTTP endpoint health
echo "[$TIMESTAMP] Checking HTTP endpoints..."
for conf in /opt/platform/caddy-apps/*.caddy; do
    [ -f "$conf" ] || continue
    domain=$(awk 'NF {print $1; exit}' "$conf")
    [ -z "$domain" ] && continue
    [[ "$domain" == "localhost" ]] && continue
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$domain/health" 2>/dev/null || echo "000")
    if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
        ALERTS+=("HTTP health check failed for $domain (status: $status)")
    fi
done

# 8. Log docker stats for Promtail pickup
echo "[$TIMESTAMP] Docker container stats:"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"

# 9. Create GitHub Issues for each alert
if [[ ${#ALERTS[@]} -gt 0 ]]; then
    echo "[$TIMESTAMP] Found ${#ALERTS[@]} alert(s)"

    for alert in "${ALERTS[@]}"; do
        echo "[$TIMESTAMP] ALERT: $alert"

        if [[ "$CREATE_ISSUES" == true ]]; then
            # Check if issue already exists (dedup)
            EXISTING=$(gh issue list --repo "${ALERT_REPO}" \
                --search "Alert: $alert in:title" \
                --state open \
                --limit 1 \
                --json number \
                --jq '.[0].number // ""' 2>/dev/null || echo "")

            if [[ -n "$EXISTING" ]]; then
                echo "[$TIMESTAMP] Issue already exists: #$EXISTING, skipping..."
            else
                # Create new issue
                ISSUE_TITLE="Alert: $alert"
                ISSUE_BODY="**Alert detected at $TIMESTAMP**

$alert

**Server Details:**
- Hostname: $(hostname)
- Disk usage: ${DISK_USAGE}%
- Memory usage: ${MEMORY_USAGE}%

**Recent Docker Stats:**
\`\`\`
$(docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}")
\`\`\`

This issue was automatically created by \`infrastructure/check-alerts.sh\`."

                echo "[$TIMESTAMP] Creating issue..."
                gh issue create \
                    --repo "${ALERT_REPO}" \
                    --title "$ISSUE_TITLE" \
                    --body "$ISSUE_BODY" \
                    --label "alert" || echo "[$TIMESTAMP] Failed to create issue"
            fi
        fi
    done
else
    echo "[$TIMESTAMP] All checks passed"
fi

# Always exit 0 (cron scripts should not fail the cron daemon)
exit 0

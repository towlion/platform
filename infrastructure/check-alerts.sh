#!/usr/bin/env bash
set -euo pipefail

# check-alerts.sh
# Cron script (every 5 min) that checks container health, disk, memory,
# and creates GitHub Issues on failure.

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ALERTS=()

# Check if GITHUB_TOKEN is set (required for issue creation)
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
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

# 4. Log docker stats for Promtail pickup
echo "[$TIMESTAMP] Docker container stats:"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"

# 5. Create GitHub Issues for each alert
if [[ ${#ALERTS[@]} -gt 0 ]]; then
    echo "[$TIMESTAMP] Found ${#ALERTS[@]} alert(s)"

    for alert in "${ALERTS[@]}"; do
        echo "[$TIMESTAMP] ALERT: $alert"

        if [[ "$CREATE_ISSUES" == true ]]; then
            # Check if issue already exists (dedup)
            EXISTING=$(gh issue list --repo towlion/platform \
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
                    --repo towlion/platform \
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

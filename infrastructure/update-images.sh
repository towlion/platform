#!/usr/bin/env bash
set -euo pipefail

# update-images.sh
# Weekly cron script for Docker image updates.

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting Docker image update process..."

# Change to platform directory
cd /opt/platform

# 1. Record current image digests before pull
echo "[$TIMESTAMP] Recording current image digests..."
BEFORE=$(docker compose images --format json 2>/dev/null || echo "")

# 2. Pull latest images
echo "[$TIMESTAMP] Pulling latest images..."
docker compose pull

# 3. Record after digests
echo "[$TIMESTAMP] Recording new image digests..."
AFTER=$(docker compose images --format json 2>/dev/null || echo "")

# 4. Check what changed
if [[ "$BEFORE" != "$AFTER" ]]; then
    echo "[$TIMESTAMP] Images updated, recreating containers..."
else
    echo "[$TIMESTAMP] No image updates available"
fi

# 5. Recreate changed containers (compose will only recreate if image changed)
echo "[$TIMESTAMP] Running docker compose up -d..."
docker compose up -d

# 6. Prune old images
echo "[$TIMESTAMP] Pruning old images..."
PRUNED=$(docker image prune -f 2>&1)
echo "$PRUNED"

# 7. Print summary
echo "[$TIMESTAMP] Update complete"

if [[ "$BEFORE" != "$AFTER" ]]; then
    echo "[$TIMESTAMP] Images were updated and containers recreated"

    # Show what's currently running
    echo ""
    echo "Current running containers:"
    docker compose ps
else
    echo "[$TIMESTAMP] All images were already up to date"
fi

exit 0

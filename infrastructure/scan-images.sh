#!/usr/bin/env bash
set -uo pipefail

# Scan all running Docker container images with Trivy for HIGH/CRITICAL vulnerabilities.
# Designed for weekly cron — always exits 0 (cron-safe).

echo "=== Image Vulnerability Scan — $(date -Iseconds) ==="

if ! command -v trivy &>/dev/null; then
  echo "WARNING: Trivy is not installed. Skipping scan."
  exit 0
fi

# Get unique images from running containers
IMAGES=$(docker ps --format '{{.Image}}' | sort -u)

if [[ -z "$IMAGES" ]]; then
  echo "No running containers found."
  exit 0
fi

TOTAL=0
VULNERABLE=0

while IFS= read -r image; do
  ((TOTAL++))
  echo
  echo "--- Scanning: ${image} ---"
  if trivy image --severity HIGH,CRITICAL --no-progress "${image}" 2>&1; then
    :
  else
    echo "WARNING: Failed to scan ${image}"
  fi

  # Check if any HIGH/CRITICAL vulnerabilities were found
  VULN_COUNT=$(trivy image --severity HIGH,CRITICAL --no-progress --format json "${image}" 2>/dev/null \
    | grep -c '"VulnerabilityID"' || true)
  if [[ "$VULN_COUNT" -gt 0 ]]; then
    ((VULNERABLE++))
  fi
done <<< "$IMAGES"

echo
echo "=== Scan Complete ==="
echo "Images scanned: ${TOTAL}"
echo "Images with HIGH/CRITICAL vulnerabilities: ${VULNERABLE}"

exit 0

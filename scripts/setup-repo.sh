#!/usr/bin/env bash
set -euo pipefail

ORG="towlion"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABELS_FILE="$SCRIPT_DIR/labels.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
  echo "Usage: $(basename "$0") <repo-name>"
  echo
  echo "Configure governance settings for a towlion repository."
  echo "Applies repo settings, branch protection, and standard labels."
  echo
  echo "Examples:"
  echo "  $(basename "$0") uku-companion"
  echo "  $(basename "$0") app-template"
}

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

REPO="$1"
FULL_REPO="$ORG/$REPO"

# --- Preflight ---

if ! command -v gh &>/dev/null; then
  error "gh CLI is not installed. Install it from https://cli.github.com"
fi

if ! gh auth status &>/dev/null; then
  error "gh CLI is not authenticated. Run 'gh auth login' first."
fi

if ! gh repo view "$FULL_REPO" &>/dev/null; then
  error "Repository $FULL_REPO does not exist or is not accessible."
fi

echo "Configuring $FULL_REPO..."
echo

# --- Repo Settings ---

gh api -X PATCH "repos/$FULL_REPO" \
  -f has_wiki=false \
  -f has_projects=false \
  -f has_discussions=false \
  -f delete_branch_on_merge=true \
  -f allow_squash_merge=true \
  -f allow_merge_commit=false \
  -f allow_rebase_merge=false \
  --silent

info "Repo settings: wiki/projects/discussions disabled, squash-only merge, auto-delete branches"

# --- Branch Protection ---

# Check if main branch exists
if gh api "repos/$FULL_REPO/branches/main" --silent 2>/dev/null; then
  gh api -X PUT "repos/$FULL_REPO/branches/main/protection" \
    --input - --silent <<'PROTECTION'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
PROTECTION

  info "Branch protection: PR reviews, status checks, no force push on main"
else
  warn "Branch 'main' does not exist yet — skipping branch protection (re-run after first push)"
fi

# --- Labels ---

if [[ ! -f "$LABELS_FILE" ]]; then
  error "Labels file not found at $LABELS_FILE"
fi

label_count=0
while IFS= read -r label; do
  name=$(echo "$label" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  color=$(echo "$label" | python3 -c "import sys,json; print(json.load(sys.stdin)['color'])")
  description=$(echo "$label" | python3 -c "import sys,json; print(json.load(sys.stdin)['description'])")

  # Try to create; if it already exists (422), update instead
  if gh api -X POST "repos/$FULL_REPO/labels" \
    -f name="$name" -f color="$color" -f description="$description" \
    --silent 2>/dev/null; then
    : # created
  else
    gh api -X PATCH "repos/$FULL_REPO/labels/$name" \
      -f color="$color" -f description="$description" \
      --silent 2>/dev/null || true
  fi
  label_count=$((label_count + 1))
done < <(python3 -c "
import json, sys
with open('$LABELS_FILE') as f:
    for item in json.load(f):
        print(json.dumps(item))
")

info "Labels: $label_count standard labels created/updated"

# --- Summary ---

echo
echo -e "${GREEN}=== Setup complete for $FULL_REPO ===${NC}"
echo "  - Repo settings configured"
if gh api "repos/$FULL_REPO/branches/main" --silent 2>/dev/null; then
  echo "  - Branch protection applied to main"
else
  echo "  - Branch protection skipped (no main branch)"
fi
echo "  - $label_count labels created/updated"

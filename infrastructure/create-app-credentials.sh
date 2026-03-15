#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -ne 1 ]; then
  error "Usage: $0 <app-name>"
  exit 1
fi

APP_NAME="$1"

# Check root or docker access
if ! docker ps >/dev/null 2>&1; then
  error "This script requires Docker access. Run as root or ensure your user is in the docker group."
  exit 1
fi

info "Provisioning credentials for app: $APP_NAME"

# Derive database and user names
APP_DB="$(echo "$APP_NAME" | tr '-' '_')_db"
APP_USER="$(echo "$APP_NAME" | tr '-' '_')_user"

info "Database: $APP_DB, User: $APP_USER"

# Generate passwords
DB_PASSWORD=$(openssl rand -base64 24)
S3_PASSWORD=$(openssl rand -base64 24)

# PostgreSQL user creation (idempotent)
info "Checking PostgreSQL user..."
if docker compose -f /opt/platform/docker-compose.yml exec -T postgres psql -U postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${APP_USER}'" | grep -q 1; then
  warn "PostgreSQL user '${APP_USER}' already exists, skipping creation"
else
  info "Creating PostgreSQL user '${APP_USER}'..."
  docker compose -f /opt/platform/docker-compose.yml exec -T postgres psql -U postgres <<EOF
CREATE USER ${APP_USER} WITH PASSWORD '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON DATABASE ${APP_DB} TO ${APP_USER};
REVOKE CONNECT ON DATABASE ${APP_DB} FROM PUBLIC;
GRANT CONNECT ON DATABASE ${APP_DB} TO ${APP_USER};
ALTER USER ${APP_USER} SET search_path TO public;
EOF
  info "PostgreSQL user created successfully"
fi

# MinIO bucket and user creation (idempotent)
info "Setting up MinIO credentials..."

# Source platform .env for MinIO root credentials
if [ ! -f /opt/platform/.env ]; then
  error "/opt/platform/.env not found"
  exit 1
fi

# shellcheck source=/dev/null
source /opt/platform/.env

if [ -z "${MINIO_ROOT_USER:-}" ] || [ -z "${MINIO_ROOT_PASSWORD:-}" ]; then
  error "MINIO_ROOT_USER or MINIO_ROOT_PASSWORD not set in /opt/platform/.env"
  exit 1
fi

# Set MinIO alias
info "Configuring MinIO client..."
docker run --rm --network towlion minio/mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1

# Create bucket
info "Creating MinIO bucket: ${APP_NAME}-uploads..."
if docker run --rm --network towlion minio/mc mb "local/${APP_NAME}-uploads" --ignore-existing 2>&1 | grep -q "Bucket created successfully"; then
  info "Bucket created successfully"
else
  warn "Bucket '${APP_NAME}-uploads' may already exist"
fi

# Create MinIO user
MINIO_USER="${APP_NAME}-user"
info "Creating MinIO user: ${MINIO_USER}..."
if docker run --rm --network towlion minio/mc admin user add local "${MINIO_USER}" "${S3_PASSWORD}" 2>&1 | grep -q "Added user"; then
  info "MinIO user created successfully"
else
  warn "MinIO user '${MINIO_USER}' may already exist, password not updated"
fi

# Create scoped policy
info "Creating MinIO policy for ${APP_NAME}..."
POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${APP_NAME}-uploads/*",
        "arn:aws:s3:::${APP_NAME}-uploads"
      ]
    }
  ]
}
EOF
)

# Write policy to temp location and create it
docker run --rm --network towlion -v /tmp:/tmp minio/mc sh -c "echo '$POLICY_JSON' > /tmp/${APP_NAME}-policy.json && mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD >/dev/null 2>&1 && mc admin policy create local ${APP_NAME}-policy /tmp/${APP_NAME}-policy.json" >/dev/null 2>&1
info "MinIO policy created"

# Attach policy to user
info "Attaching policy to user..."
docker run --rm --network towlion minio/mc sh -c "mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD >/dev/null 2>&1 && mc admin policy attach local ${APP_NAME}-policy --user ${MINIO_USER}" >/dev/null 2>&1
info "Policy attached successfully"

# Write credentials file
CREDENTIALS_DIR="/opt/platform/credentials"
mkdir -p "$CREDENTIALS_DIR"

CREDENTIALS_FILE="${CREDENTIALS_DIR}/${APP_NAME}.env"
info "Writing credentials to ${CREDENTIALS_FILE}..."

cat > "$CREDENTIALS_FILE" <<EOF
DB_USER=${APP_USER}
DB_PASSWORD=${DB_PASSWORD}
S3_ACCESS_KEY=${MINIO_USER}
S3_SECRET_KEY=${S3_PASSWORD}
EOF

# Set permissions
chown deploy:deploy "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

info "Credentials file created with permissions 600 (deploy:deploy)"

# Print summary
echo ""
info "=== Credentials Provisioning Summary ==="
info "App Name:         ${APP_NAME}"
info "PostgreSQL User:  ${APP_USER}"
info "PostgreSQL DB:    ${APP_DB}"
info "MinIO User:       ${MINIO_USER}"
info "MinIO Bucket:     ${APP_NAME}-uploads"
info "Credentials File: ${CREDENTIALS_FILE}"
echo ""
info "✓ All credentials provisioned successfully"

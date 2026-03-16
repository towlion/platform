# Runbook: Rotate Credentials

## When to Use

- Scheduled credential rotation
- Suspected credential compromise
- After team member access changes

## PostgreSQL Credentials

### Per-app database user

```bash
ssh deploy@YOUR_SERVER_IP

# Generate a new password
NEW_PW=$(openssl rand -base64 24)

# Update the PostgreSQL user
docker exec -i platform-postgres-1 psql -U postgres -c \
  "ALTER ROLE <app_name>_user WITH PASSWORD '${NEW_PW}';"

# Update the credentials file
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${NEW_PW}|" \
  /opt/platform/credentials/<app-name>.env

# Update the app's deploy/.env
cd /opt/apps/<app-name>
sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://<app_name>_user:${NEW_PW}@postgres:5432/<app_name>_db|" \
  deploy/.env

# Restart the app to pick up the new credentials
docker compose -p <app-name> -f deploy/docker-compose.yml restart app
```

### Platform postgres superuser

```bash
NEW_PW=$(openssl rand -base64 24)

docker exec -i platform-postgres-1 psql -U postgres -c \
  "ALTER ROLE postgres WITH PASSWORD '${NEW_PW}';"

sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_PW}|" \
  /opt/platform/.env

# Restart platform services
cd /opt/platform && docker compose up -d
```

**Important:** After rotating the platform postgres password, update `DATABASE_URL` in every app's `deploy/.env` that uses the superuser directly (apps without per-app credentials).

## MinIO Credentials

### Per-app MinIO user

```bash
NEW_KEY=$(openssl rand -base64 24)

# Update MinIO user via mc CLI
docker exec -i platform-minio-1 mc admin user update local <app-name>-user "${NEW_KEY}"

# Update the credentials file
sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${NEW_KEY}|" \
  /opt/platform/credentials/<app-name>.env

# Update the app's deploy/.env
cd /opt/apps/<app-name>
sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${NEW_KEY}|" deploy/.env

# Restart the app
docker compose -p <app-name> -f deploy/docker-compose.yml restart app
```

### Platform MinIO root credentials

```bash
NEW_KEY=$(openssl rand -base64 24)

sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=${NEW_KEY}|" \
  /opt/platform/.env

cd /opt/platform && docker compose up -d minio
```

## Grafana Admin Password

```bash
NEW_PW=$(openssl rand -base64 24)

sed -i "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=${NEW_PW}|" \
  /opt/platform/.env

cd /opt/platform && docker compose up -d grafana
```

The new password takes effect on next Grafana restart. Existing browser sessions remain valid until they expire.

## SSH Keys

### Rotate the deploy user's SSH key

1. Generate a new key pair locally:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy-new -C "deploy@towlion"
```

2. Add the new public key to the server:

```bash
ssh deploy@YOUR_SERVER_IP
echo "NEW_PUBLIC_KEY" >> ~/.ssh/authorized_keys
```

3. Test the new key:

```bash
ssh -i ~/.ssh/deploy-new deploy@YOUR_SERVER_IP echo "success"
```

4. Remove the old public key from `~/.ssh/authorized_keys` on the server.

5. Update the `SERVER_SSH_KEY` secret on **every app repository** that deploys to this server.

## Post-Rotation Verification

After rotating any credential:

1. Check the app health endpoint: `curl https://<app-domain>/health`
2. Run a deploy to confirm the workflow still works
3. Check container logs for authentication errors:
   ```bash
   docker compose -p <app-name> -f deploy/docker-compose.yml logs --tail 20 app
   ```

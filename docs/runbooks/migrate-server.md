# Runbook: Migrate to a New Server

## When to Use

- Server hardware failure or end-of-life
- Cloud provider migration
- Upgrading to a larger instance

## Prerequisites

- SSH access to both old and new servers as the `deploy` user
- DNS control for all app domains and the ops domain
- Backup encryption key (if encrypted backups are enabled)
- GitHub deploy key or SSH key for repo access on the new server

## Steps

### 1. Inventory the old server

SSH into the old server and record what is running:

```bash
ssh deploy@<old-server-ip>
```

List running apps and their deploy slots:

```bash
for dir in /opt/apps/*/; do
  app=$(basename "$dir")
  slot=$(cat "$dir/.deploy-slot" 2>/dev/null || echo "none")
  echo "$app  slot=$slot"
done
```

List app domains from the Caddyfile:

```bash
cat /opt/platform/Caddyfile
```

Record platform environment variables:

```bash
cat /opt/platform/.env
```

List per-app credential files:

```bash
ls /opt/platform/credentials/
```

List cron jobs:

```bash
crontab -l
```

### 2. Create fresh backups

Run the backup script for every app database:

```bash
bash /opt/platform/infrastructure/backup-postgres.sh
```

Verify backups were created:

```bash
ls -lh /data/backups/postgres/
```

### 3. Transfer backups and credentials to your local machine

```bash
# From your local machine:
scp -r deploy@<old-server-ip>:/data/backups/postgres/ ./migration-backups/
scp -r deploy@<old-server-ip>:/opt/platform/.env ./migration-platform.env
scp -r deploy@<old-server-ip>:/opt/platform/credentials/ ./migration-credentials/
```

If encrypted backups are enabled, also copy the encryption key:

```bash
scp deploy@<old-server-ip>:<path-to-encryption-key> ./migration-backup-key
```

### 4. Bootstrap the new server

On the new server, run the bootstrap script with the same env vars used for the old server:

```bash
sudo ACME_EMAIL=<your-email> OPS_DOMAIN=<ops.example.com> ALERT_REPO=<org/repo> \
  bash infrastructure/bootstrap-server.sh
```

Wait for all platform containers to become healthy:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### 5. Copy credentials to the new server

```bash
# From your local machine:
scp ./migration-platform.env deploy@<new-server-ip>:/opt/platform/.env
scp -r ./migration-credentials/ deploy@<new-server-ip>:/opt/platform/credentials/
```

If using backup encryption, copy the key:

```bash
scp ./migration-backup-key deploy@<new-server-ip>:<path-to-encryption-key>
```

Restart platform containers so they pick up the restored credentials:

```bash
ssh deploy@<new-server-ip>
cd /opt/platform
docker compose down && docker compose up -d
```

### 6. Restore databases

Copy backup files to the new server:

```bash
# From your local machine:
scp -r ./migration-backups/ deploy@<new-server-ip>:/data/backups/postgres/
```

On the new server, restore each app database:

```bash
ssh deploy@<new-server-ip>
bash /opt/platform/infrastructure/restore-postgres.sh --yes <backup-file>
```

Verify each restored database:

```bash
bash /opt/platform/infrastructure/verify-backup.sh <database-name>
```

### 7. Clone and configure apps

For each app, clone the repo and set up the deploy directory:

```bash
cd /opt/apps
git clone git@github.com:towlion/<app-name>.git <app-name>
cd <app-name>
```

Write the app's `deploy/.env` using credentials from `/opt/platform/credentials/<app-name>`:

```bash
cp deploy/env.template deploy/.env
# Edit deploy/.env with the correct DATABASE_URL, S3 credentials, JWT_SECRET, etc.
```

Set the initial deploy slot:

```bash
echo "blue" > .deploy-slot
```

### 8. Deploy apps

Run the blue-green deploy script for each app:

```bash
bash /opt/platform/infrastructure/deploy-blue-green.sh \
  <app-name> /opt/apps/<app-name> <app-domain> "<caddyfile-content>"
```

Alternatively, trigger deploys via GitHub Actions once GitHub secrets are updated (step 12).

### 9. Verify on the new server

Check that all platform containers are healthy:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Check health endpoints for each app (using the server IP directly, since DNS still points to the old server):

```bash
curl -sk --resolve <app-domain>:443:<new-server-ip> https://<app-domain>/health
```

Verify Grafana is accessible:

```bash
curl -sk --resolve <ops-domain>:443:<new-server-ip> https://<ops-domain>/
```

Verify cron jobs are in place:

```bash
crontab -l
```

### 10. Switch DNS

Update A records for all domains to point to the new server IP:

- Each app domain (e.g., `app.example.com`, `app2.example.com`)
- The ops domain (e.g., `ops.example.com`)
- Preview wildcard record (e.g., `*.preview.example.com`)

DNS propagation typically takes minutes but can take up to 48 hours depending on TTL. Consider lowering TTL values a day before the migration.

### 11. Verify TLS

After DNS propagates, Caddy will automatically provision TLS certificates. Monitor the Caddy logs:

```bash
docker logs -f platform-caddy-1
```

Test HTTPS on all domains:

```bash
curl -s https://<app-domain>/health
curl -s https://<ops-domain>/
```

Verify certificates are valid:

```bash
echo | openssl s_client -connect <app-domain>:443 -servername <app-domain> 2>/dev/null | openssl x509 -noout -dates
```

### 12. Update GitHub secrets

In each app repository, update the following secrets to point to the new server:

- `SERVER_HOST` — new server IP
- `SERVER_SSH_KEY` — SSH private key for the new server's `deploy` user

```bash
# Using the GitHub CLI:
gh secret set SERVER_HOST --repo towlion/<app-name> --body "<new-server-ip>"
gh secret set SERVER_SSH_KEY --repo towlion/<app-name> < ~/.ssh/<new-server-key>
```

Trigger a test deploy on one app to confirm the pipeline works end-to-end.

### 13. Decommission the old server

Keep the old server running for 48-72 hours as a safety net. During this period:

- Monitor the new server for errors
- Confirm all deploys go to the new server
- Verify backups run successfully on the new server

Once satisfied, tear down the old server:

```bash
ssh deploy@<old-server-ip>
# Stop all containers
cd /opt/platform && docker compose down
for dir in /opt/apps/*/; do
  app=$(basename "$dir")
  docker compose -p "$app" -f "$dir/deploy/docker-compose.yml" down
done
```

Then delete or destroy the old server instance through your cloud provider.

## Rollback

If issues arise after the DNS switch:

- **Revert DNS** — Point A records back to the old server IP. The old server remains fully functional until explicitly decommissioned.
- **Investigate** — SSH into the new server and check logs, health endpoints, and container status.

## Verification Checklist

- [ ] All platform containers healthy (`docker ps`)
- [ ] All app health endpoints return 200
- [ ] Grafana accessible at ops domain
- [ ] Backup cron running (`crontab -l`)
- [ ] GitHub Actions deploys targeting new server
- [ ] TLS certificates provisioned for all domains
- [ ] Preview environment DNS (wildcard record) updated

## Notes

- Plan the migration during a low-traffic window to minimize impact.
- If you lower DNS TTL before migration, remember to restore it afterward.
- The old server's backups remain available as an additional safety net during the transition period.

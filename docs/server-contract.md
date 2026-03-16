# Server Contract

This document defines the contract between the platform infrastructure (bootstrapped by `bootstrap-server.sh`) and the app deployment workflows (`deploy.yml`, `preview.yml`). It explains the directory layout, lifecycle, and assumptions that connect them.

## Server Directory Layout

```
/opt/platform/                          # Platform root (created by bootstrap-server.sh)
  docker-compose.yml                    # Platform services (7 core + 3 optional metrics)
  .env                                  # Platform credentials (POSTGRES_PASSWORD, MINIO_ROOT_*, GRAFANA_ADMIN_PASSWORD, ACME_EMAIL, OPS_DOMAIN, ALERT_REPO, COMPOSE_PROFILES)
  .bootstrapped                         # Timestamp marker from last bootstrap run
  Caddyfile                             # Global Caddyfile — imports /etc/caddy/apps/*.caddy
  caddy-apps/                           # Per-app Caddyfile fragments (written by deploy/preview workflows)
    <app-name>.caddy                    #   Production route for an app
    <app-name>-pr-<N>.caddy             #   Preview route for a PR
    ops.caddy                           #   Grafana route (created by bootstrap)
  credentials/                          # Per-app credential files (created by create-app-credentials.sh)
    <app-name>.env                      #   DB_USER, DB_PASSWORD, S3_ACCESS_KEY, S3_SECRET_KEY
  infrastructure/                       # Ops scripts (copied from platform repo by bootstrap)
    backup-postgres.sh
    restore-postgres.sh
    check-alerts.sh
    update-images.sh
    create-app-credentials.sh
    usage-report.sh
  loki-config.yml                       # Loki configuration
  promtail-config.yml                   # Promtail configuration
  prometheus.yml                        # Prometheus scrape config (always created)
  grafana/                              # Grafana provisioning files and dashboards
    provisioning/datasources/
    provisioning/dashboards/
    dashboards/

/opt/apps/                              # Application root (created by bootstrap-server.sh)
  <app-name>/                           # Cloned app repo (created manually by admin)
    deploy/
      .env                              # App runtime config (created manually from env.template)
      docker-compose.yml                # App services (joins towlion network)
  <app-name>-pr-<N>/                    # Preview clone (created/destroyed by preview.yml)

/data/                                  # Persistent data volumes (created by bootstrap-server.sh)
  postgres/                             # PostgreSQL data directory
  redis/                                # Redis data directory
  minio/                                # MinIO object storage
  caddy/data/                           # Caddy TLS certificates
  caddy/config/                         # Caddy config state
  loki/                                 # Loki log storage
  grafana/                              # Grafana state
  prometheus/                           # Prometheus data (created always, used when metrics enabled)
  backups/postgres/                     # pg_dump backup files (7-day retention)
```

## Bootstrap to Deploy Lifecycle

1. **Bootstrap the server** — Run `sudo bash infrastructure/bootstrap-server.sh` on a fresh Debian machine. This creates the directory layout above, installs Docker, creates the `deploy` user, generates platform credentials, starts the 7 core platform services (plus 3 optional metrics services if enabled), copies infrastructure scripts, and installs cron jobs.

2. **Configure DNS** — Point app domains and `*.preview.<domain>` to the server IP.

3. **Clone the app repo** — SSH in as `deploy` and clone the app to `/opt/apps/<name>/`.

4. **Create `deploy/.env`** — Copy `deploy/env.template` and fill in values (DATABASE_URL, S3 credentials, etc.).

5. **Provision per-app credentials (optional)** — Run `create-app-credentials.sh <name>` to create an isolated PostgreSQL user and MinIO bucket. Credentials are written to `/opt/platform/credentials/<name>.env`.

6. **Configure GitHub secrets** — Set `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, and `APP_DOMAIN` on the app repo. Add `PREVIEW_DOMAIN` for preview environments.

7. **Push to main** — Triggers `deploy.yml`:
   - SSHes into the server as `deploy`
   - `cd /opt/apps/<name> && git pull origin main`
   - Creates the app database if it doesn't exist (via platform postgres)
   - Sources per-app credentials from `/opt/platform/credentials/<name>.env` (if present) and updates `deploy/.env` with isolated DB/S3 values
   - `docker compose -p <name> -f deploy/docker-compose.yml up -d --build`
   - Runs Alembic migrations inside the app container
   - Writes a Caddyfile to `/opt/platform/caddy-apps/<name>.caddy`
   - Reloads Caddy to pick up the new route

## App Workflow Server Assumptions

The `deploy.yml` and `preview.yml` workflows SSH into the server and depend on the following structure being in place:

| Path / Resource | Purpose | Created By |
|---|---|---|
| `/opt/platform/docker-compose.yml` | Platform services (postgres, redis, caddy, etc.) | `bootstrap-server.sh` |
| `/opt/platform/.env` | `POSTGRES_PASSWORD` for database operations | `bootstrap-server.sh` |
| `/opt/platform/caddy-apps/` | Writable directory for per-app Caddyfile fragments | `bootstrap-server.sh` |
| `/opt/platform/credentials/<name>.env` | Per-app DB/S3 credentials (optional) | `create-app-credentials.sh` |
| `/opt/apps/<name>/` | Cloned app repo with `deploy/.env` configured | Admin (manual) |
| `towlion` Docker network | Shared network connecting platform services and app containers | `bootstrap-server.sh` |
| `deploy` user | SSH user with Docker group membership | `bootstrap-server.sh` |

If any of these are missing, the workflow will fail. The bootstrap script is idempotent and can be re-run to restore missing structure.

## Infrastructure Scripts Reference

All scripts live in the platform repo under `infrastructure/` and are copied to `/opt/platform/infrastructure/` during bootstrap.

| Script | Purpose | Invocation |
|---|---|---|
| `bootstrap-server.sh` | Transform fresh Debian into running platform | Manual (`sudo bash`) |
| `verify-server.sh` | Read-only health check of server state | Manual (`bash`) |
| `create-app-credentials.sh` | Provision per-app PostgreSQL user + MinIO bucket | Manual (`bash <script> <app-name>`) |
| `backup-postgres.sh` | Per-database `pg_dump` with 7-day retention | Cron: daily at 02:00 |
| `restore-postgres.sh` | Restore a database from backup | Manual (`bash <script>`) |
| `check-alerts.sh` | Check container health, disk, memory; create GitHub Issues | Cron: every 5 minutes |
| `update-images.sh` | Pull latest Docker images and recreate containers | Cron: weekly Sunday at 03:00 |
| `usage-report.sh` | Generate 6-section resource usage report | Manual (`bash`) |
| `scan-images.sh` | Scan running container images for vulnerabilities (Trivy) | Cron: weekly Sunday at 04:00 |

## Server Hardening

The bootstrap script applies several security measures automatically. Self-hosters get these out of the box; no manual hardening steps are needed beyond running the bootstrap.

**Firewall** — UFW is configured to deny all incoming traffic except ports 22 (SSH), 80 (HTTP), and 443 (HTTPS). All other ports, including PostgreSQL (5432), Redis (6379), and MinIO (9000), are only reachable via the internal Docker network.

**Automatic security updates** — `unattended-upgrades` is installed and configured for the Debian security channel. Security patches are applied automatically without manual intervention.

**Non-root deployment** — A `deploy` user with Docker group membership handles all deployments. Workflows SSH in as `deploy`, never as root. The deploy user cannot modify system packages or firewall rules.

**Credential isolation** — The platform `.env` file is mode 600 (readable only by its owner). Per-app credentials are generated by `create-app-credentials.sh` and stored in separate files under `/opt/platform/credentials/`, each also mode 600.

**Container resource limits** — Every platform service and every app container has explicit CPU and memory limits in its Docker Compose file. This prevents any single container from exhausting server resources. The 7 core services use ~2.66G / 3.25 CPU. The 3 optional metrics services add 448M / 1.00 CPU when enabled.

**Brute-force protection** — fail2ban is installed with an SSH jail (systemd backend, since Debian 12 uses journald). Configuration: maxretry=5, bantime=3600s. IPs that exceed the retry limit are banned for one hour.

**SSH hardening** — A drop-in config at `/etc/ssh/sshd_config.d/99-towlion-hardening.conf` enforces: `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3`, `X11Forwarding no`. Only key-based authentication as the `deploy` user is permitted.

**Security headers** — The platform Caddyfile includes a `(security_headers)` snippet that sets: `Strict-Transport-Security` (HSTS, max-age=31536000, includeSubDomains), `X-Content-Type-Options nosniff`, `X-Frame-Options DENY`, `Referrer-Policy strict-origin-when-cross-origin`, `Permissions-Policy` (camera, microphone, and geolocation denied), and strips the `Server` header. All app and ops Caddy routes import this snippet.

**Image vulnerability scanning** — Trivy is installed via the Aqua Security apt repository. Every deploy runs a non-blocking `trivy image` scan of the newly built app image (HIGH/CRITICAL severity). A weekly cron job (`scan-images.sh`, Sunday 04:00) scans all running container images.

**Mandatory Access Control (AppArmor)** — Debian 12 ships with AppArmor enabled by default. Docker automatically applies the `docker-default` AppArmor profile to all containers, which restricts capabilities like writing to `/proc` and `/sys`, mounting filesystems, and accessing raw sockets. No configuration is needed — this works out of the box.

SELinux is **not** used. While SELinux is the standard MAC system on RHEL/Fedora, it is not well-suited for Debian:

- AppArmor is Debian's native MAC system, maintained by the Debian security team
- SELinux policies on Debian are incomplete and poorly maintained — the `selinux-policy-default` package lags far behind RHEL equivalents
- Docker + SELinux on Debian causes bind-mount labeling issues (`:z`/`:Z` volume flags) with no community support for troubleshooting
- Enabling SELinux on Debian requires switching from AppArmor, losing Docker's automatic profile enforcement

Since AppArmor is already active and Docker integrates with it automatically, the platform's MAC requirements are met without any additional configuration.

## Caddyfile Generation

The platform Caddyfile at `/opt/platform/Caddyfile` contains a security headers snippet and an import directive:

```
{
    email {$ACME_EMAIL:admin@localhost}
}

(security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
        -Server
    }
}

import /etc/caddy/apps/*.caddy
```

The `caddy-apps/` directory is bind-mounted into the Caddy container at `/etc/caddy/apps/`. App workflows write per-app `.caddy` files into this directory.

**Production** (`deploy.yml`) writes `/opt/platform/caddy-apps/<name>.caddy`:

```
app.example.com {
    import security_headers
    reverse_proxy <name>-app-1:8000
}
```

**Preview** (`preview.yml`) writes `/opt/platform/caddy-apps/<name>-pr-<N>.caddy`:

```
pr-<N>.preview.example.com {
    import security_headers
    reverse_proxy <name>-pr-<N>-app-1:8000
}
```

After writing the file, both workflows reload Caddy:

```bash
docker compose -f /opt/platform/docker-compose.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile
```

Preview cleanup removes the `.caddy` file and reloads Caddy again.

## Per-App Credentials

By default, apps connect to PostgreSQL as the `postgres` superuser (credentials from `deploy/.env`). For credential isolation, run:

```bash
bash /opt/platform/infrastructure/create-app-credentials.sh <app-name>
```

This creates:

- **PostgreSQL**: A dedicated user (`<app_name>_user`) with access restricted to `<app_name>_db`
- **MinIO**: A dedicated user (`<app-name>-user`) with a scoped policy limiting access to the `<app-name>-uploads` bucket
- **Credentials file**: `/opt/platform/credentials/<app-name>.env` containing `DB_USER`, `DB_PASSWORD`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` (mode 600, owned by `deploy`)

On subsequent deploys, `deploy.yml` checks for this credentials file and, if found, updates `deploy/.env` with the per-app values via `sed`:

```bash
CREDENTIALS_FILE="/opt/platform/credentials/${APP_NAME}.env"
if [ -f "$CREDENTIALS_FILE" ]; then
    source "$CREDENTIALS_FILE"
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${APP_DB}|" deploy/.env
    sed -i "s|^S3_ACCESS_KEY=.*|S3_ACCESS_KEY=${S3_ACCESS_KEY}|" deploy/.env
    sed -i "s|^S3_SECRET_KEY=.*|S3_SECRET_KEY=${S3_SECRET_KEY}|" deploy/.env
    sed -i "s|^S3_BUCKET=.*|S3_BUCKET=${APP_NAME}-uploads|" deploy/.env
fi
```

If no credentials file exists, the workflow falls back to whatever is already in `deploy/.env` and logs a warning.

## Resource Metrics (Optional)

Three additional services provide real-time resource visibility in Grafana. They are **off by default** and use Docker Compose profiles to control startup.

| Service | Image | Memory Limit | CPU Limit | Purpose |
|---|---|---|---|---|
| prometheus | prom/prometheus:v2.53.0 | 256M | 0.50 | Metrics storage and queries |
| cadvisor | gcr.io/cadvisor/cadvisor:v0.49.1 | 128M | 0.25 | Container metrics |
| node-exporter | prom/node-exporter:v1.8.1 | 64M | 0.25 | Host metrics |

**To enable** — add `COMPOSE_PROFILES=metrics` to `/opt/platform/.env`, then run `docker compose up -d` in `/opt/platform/`. Or bootstrap with `sudo ENABLE_METRICS=true bash bootstrap-server.sh`.

**To disable** — remove the `COMPOSE_PROFILES=metrics` line from `.env`, then stop the metrics services with `docker compose --profile metrics down`.

The Prometheus config (`/opt/platform/prometheus.yml`), Grafana datasource, and dashboard JSON are always created during bootstrap — they are harmless without running services and avoid needing to re-bootstrap to enable metrics later. Only the service startup is conditional.

The "Resource Metrics" dashboard in Grafana includes:

- **Host overview**: CPU %, memory %, disk %, uptime (stat panels)
- **Host time series**: CPU, memory, disk I/O, network I/O over time
- **Container overview**: table of all containers with CPU, memory, network
- **Per-container detail**: filterable CPU and memory time series per container

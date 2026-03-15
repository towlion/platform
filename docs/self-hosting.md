# Self-Hosting

## Fork-Based Deployment Model

Every application in the Towlion ecosystem is designed to be **forkable and self-deployable**. Instead of multi-tenant SaaS, the platform uses repository forks as the isolation boundary.

```
User forks repository
      ↓
Configure deployment secrets
      ↓
Push code
      ↓
GitHub Actions deploys app
      ↓
Application runs on user's server
```

Each fork runs independently — there is no shared tenancy or centralized hosting.

```
original repo
     │
     ├─ fork by Alice → alice.example.com
     ├─ fork by Bob   → bob.example.com
     └─ fork by Carol → carol.example.com
```

Benefits:

- Strong isolation between deployments
- Simple architecture (no tenant management)
- Full control for each operator

## Server Requirements

| Resource | Minimum |
|---|---|
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | 50 GB |
| Data disk | Mounted at `/data` |

Required ports:

| Port | Purpose |
|---|---|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |

## Required Secrets

Fork users must configure these GitHub Actions secrets:

| Secret | Purpose |
|---|---|
| `SERVER_HOST` | Server IP address |
| `SERVER_USER` | SSH user |
| `SERVER_SSH_KEY` | SSH private key for deployment |
| `APP_DOMAIN` | Application domain name |
| `DATABASE_PASSWORD` | PostgreSQL password |
| `MINIO_ROOT_USER` | MinIO admin username |
| `MINIO_ROOT_PASSWORD` | MinIO admin password |
| `EMAIL_API_KEY` | Transactional email API key |

Optional secrets:

| Secret | Purpose |
|---|---|
| `SENTRY_DSN` | Error tracking |
| `REDIS_PASSWORD` | Redis authentication |

## Bootstrap Process

To deploy an application from a fork:

1. **Fork the repository** on GitHub
2. **Create a server** (Debian 12, meeting the minimum requirements)
3. **Run the bootstrap script** to install Docker and dependencies
4. **Configure DNS** — point your domain to the server IP
5. **Configure GitHub secrets** — add the required secrets to your fork
6. **Push code** — deployment runs automatically via GitHub Actions

### Bootstrap Script

The repository includes a single bootstrap script that transforms a fresh Debian 12 server into a ready-to-deploy platform:

```bash
sudo bash infrastructure/bootstrap-server.sh
```

The script is idempotent — safe to re-run on an already-bootstrapped server. It performs:

- System packages (git, curl, ufw)
- Firewall configuration (ports 22, 80, 443)
- Docker and Compose plugin installation
- `deploy` user creation with SSH directory
- Directory structure (`/data/postgres`, `/data/redis`, `/data/minio`, `/data/caddy`, `/opt/apps`, `/opt/platform`)
- Docker network (`towlion`) for cross-container communication
- Credential generation (PostgreSQL and MinIO passwords in `/opt/platform/.env`)
- Platform Caddyfile with per-app import pattern
- Platform `docker-compose.yml` (PostgreSQL 16, Redis 7, MinIO, Caddy 2)
- Service startup and verification

## DNS Configuration

Point your domain (or subdomain) to your server's IP address:

```
A record: app.example.com → SERVER_IP
```

For multiple applications, use subdomains:

```
uku.example.com   → SERVER_IP
timer.example.com → SERVER_IP
```

Caddy handles TLS certificate provisioning automatically once DNS is configured.

## What You Get

After deployment, your server runs:

- Your application (FastAPI backend + Next.js frontend)
- PostgreSQL database
- Redis cache and queue
- MinIO object storage
- Caddy reverse proxy with automatic TLS
- Celery background workers

All managed through GitHub — push code to deploy updates.

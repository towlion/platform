# Architecture

## Overview

The Towlion platform runs on a single Debian server. Applications run as Docker containers and share a set of core infrastructure services.

```
                Internet
                    │
                    ▼
                  DNS
                    │
                    ▼
              Reverse Proxy
                 (Caddy)
            /       |       \
           ▼        ▼        ▼
       App 1     App 2     App 3
           │
           ▼
      Shared Services
           │
  ┌────────┼─────────┬─────────┐
  ▼        ▼         ▼         ▼
PostgreSQL Redis   MinIO    Workers
```

## Technology Stack

### Infrastructure

- **Debian** — host operating system
- **Docker** — container runtime
- **Docker Compose** — service orchestration

### Networking

- **Caddy** — reverse proxy with automatic TLS via Let's Encrypt

### Application

- **FastAPI** — Python backend framework
- **SQLAlchemy** — ORM
- **Pydantic** — data validation
- **Alembic** — database migrations

### Frontend

- **Next.js** — React framework
- **TypeScript** — type-safe frontend code

### Data

- **PostgreSQL** — primary database
- **Redis** — caching and job queues
- **MinIO** — S3-compatible object storage

### Background Jobs

- **Celery** — async task processing (backed by Redis)

### CI/CD

- **GitHub Actions** — automated builds and deployments

### Optional Observability

- **Grafana** — dashboards
- **Loki** — log aggregation

## GitHub as the Control Plane

Traditional PaaS platforms use a dedicated control plane:

```
CLI → Control plane → Kubernetes → containers
```

Towlion replaces this with GitHub:

```
GitHub repo → GitHub Actions → SSH deployment → Docker runtime
```

GitHub provides:

- CI/CD (Actions)
- Configuration storage (Secrets)
- Access control (repository permissions)
- Workflow orchestration (Actions workflows)

This eliminates the need for custom deployment dashboards or orchestration systems.

## Multi-Application Hosting

A single server hosts multiple applications. Each application runs in its own container, sharing the core infrastructure services.

```
server
 ├── caddy
 ├── postgres
 ├── redis
 ├── minio
 ├── uku-app
 ├── timer-app
 └── lyrics-app
```

## Domain Routing

Each application gets its own subdomain. Caddy routes traffic to the correct container.

```
uku.towlion.com   → uku-app container
timer.towlion.com → timer-app container
lyrics.towlion.com → lyrics-app container
```

Example Caddy configuration:

```
uku.towlion.com {
    reverse_proxy uku-app:8000
}

timer.towlion.com {
    reverse_proxy timer-app:8000
}

storage.towlion.com {
    reverse_proxy minio:9000
}
```

Caddy automatically provisions TLS certificates and redirects HTTP to HTTPS.

## Database Strategy

A single PostgreSQL instance runs on the server. Each application uses a dedicated database for logical isolation:

```
uku_db
timer_db
lyrics_db
```

## Persistent Storage

All persistent data is stored under `/data` on the host, ensuring data survives container redeployments.

```
/data
 ├── postgres          # PostgreSQL data
 ├── redis             # Redis data
 ├── minio             # Object storage
 ├── caddy/            # Caddy TLS certs and config
 │   ├── data
 │   └── config
 ├── loki              # Log aggregation data
 ├── grafana           # Dashboard data
 └── backups/postgres  # Database backups
```

Docker containers mount these directories as volumes.

## Object Storage

MinIO provides S3-compatible object storage. Applications interact with it using the standard S3 API.

```
S3_ENDPOINT=https://storage.example.com
S3_BUCKET=uploads
S3_ACCESS_KEY=app_user
S3_SECRET_KEY=secret
```

Storage data lives at `/data/minio`.

## Background Jobs

Asynchronous tasks are processed by Celery workers backed by Redis.

```
Application → Redis queue → Celery Worker
```

Typical use cases:

- Sending transactional email
- Processing file uploads
- Scheduled background tasks

Workers run as separate containers.

## Transactional Email

Email is sent via external providers (e.g., Postmark, Amazon SES). The application sends email through provider APIs, with delivery handled by Celery workers.

```
EMAIL_PROVIDER=postmark
EMAIL_API_KEY=your-api-key
EMAIL_FROM=noreply@example.com
```

## Logging and Backups

**Logging:** Applications write to stdout. Container logs are captured by the Docker runtime. Optionally, logs can be aggregated with Promtail, Loki, and Grafana.

**Backups:** Daily database backups via cron:

```bash
pg_dump → /data/backups
```

Backups can be synced to remote storage using `rclone`.

## Docker Compose Services

Each application lives in its own GitHub repository under the `towlion` organization. The server runs two layers of Compose services:

### Platform Services (server-level)

Shared infrastructure managed at the server level, independent of any application repository:

```yaml
services:
  caddy:
    image: caddy:2
  postgres:
    image: postgres:16
    volumes:
      - /data/postgres:/var/lib/postgresql/data
  redis:
    image: redis
  minio:
    image: minio/minio
    volumes:
      - /data/minio:/data
```

### Application Services (per-repo)

Each application repository defines its own containers. These connect to the shared platform services via Docker networking:

```yaml
services:
  app:
    build: ./app
    env_file: .env
  frontend:
    build: ./frontend
  celery-worker:
    build: ./app
    command: celery -A app.tasks worker
```

For single-app self-hosting (fork scenario), a repository may bundle platform services in its own Compose file so it can run standalone.

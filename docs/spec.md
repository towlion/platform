# Application Specification

**Spec Version:** 1.0

This document defines the **standard contract for applications** running on the Towlion platform. Every application repository in the ecosystem should follow this specification.

## Goals

All applications must be:

- Deployable automatically
- Self-hostable via repository forks
- Compatible with the platform runtime
- Easy to maintain

## Repository Structure

Each application lives in its own GitHub repository under the `towlion` organization. Every application repository should follow this structure:

```
repo/
  app/                          # FastAPI backend
    __init__.py                 # Package marker (required)
    Dockerfile                  # Backend container image
    main.py                     # Application entry point
  frontend/                     # Next.js frontend (optional)
    Dockerfile                  # Frontend container image

  deploy/
    docker-compose.yml          # App-specific containers
    docker-compose.standalone.yml  # Full stack for self-hosted forks
    Caddyfile                   # Caddy site config for this app
    env.template

  .github/workflows/
    deploy.yml

  scripts/
    health-check.sh

  README.md
```

In the multi-app setup, `docker-compose.yml` defines only the application containers (app, frontend, workers). Shared platform services (Caddy, PostgreSQL, Redis, MinIO) are managed at the server level.

The `docker-compose.standalone.yml` file provides a complete, self-contained stack for self-hosted fork deployments. It bundles all platform services (Caddy, PostgreSQL, Redis, MinIO) alongside the application containers so the app can run on a single server without any external dependencies.

## Backend Requirements

Applications must expose an HTTP server on **port 8000**.

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The platform reverse proxy routes traffic to this port.

## Health Endpoint

Every application must provide a health check endpoint:

- **Endpoint:** `GET /health`
- **HTTP Status:** `200 OK`
- **Response:** `{"status": "ok"}`

This endpoint is used during deployments to verify the application started correctly.

## Environment Variables

Applications must support configuration via environment variables.

**Required:**

| Variable | Purpose |
|---|---|
| `APP_DOMAIN` | Application domain |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |

**Optional:**

| Variable | Purpose |
|---|---|
| `S3_ENDPOINT` | MinIO/S3 endpoint |
| `S3_BUCKET` | Storage bucket name |
| `S3_ACCESS_KEY` | Storage access key |
| `S3_SECRET_KEY` | Storage secret key |
| `JWT_SECRET` | Secret key for JWT token signing |
| `CORS_ORIGINS` | Comma-separated allowed CORS origins |
| `EMAIL_API_KEY` | Transactional email API key |
| `EMAIL_FROM` | Sender email address |

## Database

Applications should use PostgreSQL with Alembic for schema migrations.

Connection string format:

```
postgresql://user:password@postgres:5432/app_db
```

Migrations must run automatically during deployment.

## Background Workers

Applications requiring async tasks should use Celery with Redis as the queue backend.

Typical use cases:

- Sending email
- Processing uploads
- Background processing

Workers run as separate containers.

## Object Storage

File uploads should use S3-compatible object storage (MinIO).

```
S3_ENDPOINT=https://storage.example.com
S3_BUCKET=uploads
```

Applications should avoid storing large files on the container filesystem.

## Frontend

Applications may include a frontend built with Next.js, React, and TypeScript. The frontend communicates with the backend via `/api`.

## Dependencies

Python dependencies must be declared in one of:

- `requirements.txt` (default)
- `pyproject.toml` (alternative)

At minimum, dependencies must include `fastapi` and `uvicorn`.

## Docker Requirements

Each repository must include Docker configuration. The backend Dockerfile must be located at `app/Dockerfile`. If the app includes a frontend, its Dockerfile must be at `frontend/Dockerfile`.

The container must:

- Start automatically
- Expose port 8000
- Read configuration from environment variables

Example `app/Dockerfile`:

```dockerfile
FROM python:3.11
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Persistent Storage

Applications should not rely on container storage. Persistent data belongs in:

- Database (PostgreSQL)
- Object storage (MinIO)
- External services

## Logging

Applications should write logs to stdout. Container logs are captured by the platform runtime.

## Security

Applications should follow basic security practices:

- No hard-coded secrets
- Use environment variables for configuration
- Validate input data
- Enforce authentication where required

## Authentication

Applications that require user authentication should use:

- **JWT tokens** (HS256) for session management
- **bcrypt** for password hashing
- **HTTPBearer** scheme for token transport

The app-template provides this infrastructure out of the box. See the [app-template README](https://github.com/towlion/app-template#authentication) for usage.

## Compatibility Checklist

To remain compatible with the Towlion platform, applications must:

**Structure:**
- [ ] Include `app/` directory with `Dockerfile` and `main.py`
- [ ] Include `deploy/` directory with `docker-compose.yml`, `docker-compose.standalone.yml`, `Caddyfile`, and `env.template`
- [ ] Include `.github/workflows/deploy.yml`
- [ ] Include `scripts/health-check.sh`
- [ ] Include `README.md`

**Content:**
- [ ] `deploy/docker-compose.yml` is valid YAML, references port 8000, and includes a healthcheck
- [ ] `deploy/env.template` contains `APP_DOMAIN`, `DATABASE_URL`, and `REDIS_URL`
- [ ] `deploy/Caddyfile` contains `reverse_proxy` directive targeting port 8000
- [ ] `app/main.py` uses FastAPI
- [ ] Python dependencies (`requirements.txt` or `pyproject.toml`) include `fastapi` and `uvicorn`
- [ ] No hardcoded secrets in source code
- [ ] `deploy/env.template` contains `JWT_SECRET` (if using authentication)

**Runtime:**
- [ ] Expose HTTP service on port 8000
- [ ] `GET /health` returns HTTP 200 with `{"status": "ok"}`
- [ ] Containers build and start successfully

## Validation

Use the [Towlion Spec Validator](../validator/README.md) to automatically check conformance.

**Local usage:**

```bash
# Clone the platform repo and run against your app
python validator/validate.py --tier 2 --dir /path/to/your/app
```

**CI usage (GitHub Actions):**

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: towlion/platform/.github/actions/validate@main
    with:
      tier: '2'
```

# Application Specification

This document defines the **standard contract for applications** running on the Towlion platform. Every application repository in the ecosystem should follow this specification.

## Goals

All applications must be:

- Deployable automatically
- Self-hostable via repository forks
- Compatible with the platform runtime
- Easy to maintain

## Repository Structure

Every application repository should follow this structure:

```
repo/
  app/                          # FastAPI backend
  frontend/                     # Next.js frontend

  deploy/
    docker-compose.yml
    Caddyfile
    env.template

  .github/workflows/
    deploy.yml

  scripts/
    health-check.sh

  README.md
```

## Backend Requirements

Applications must expose an HTTP server on **port 8000**.

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The platform reverse proxy routes traffic to this port.

## Health Endpoint

Every application must provide a health check endpoint:

- **Endpoint:** `GET /health`
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

## Docker Requirements

Each repository must include Docker configuration. The container must:

- Start automatically
- Expose port 8000
- Read configuration from environment variables

Example Dockerfile:

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

## Compatibility Checklist

To remain compatible with the Towlion platform, applications must:

- [ ] Expose HTTP service on port 8000
- [ ] Provide `GET /health` endpoint
- [ ] Support environment-based configuration
- [ ] Support automated deployment via GitHub Actions
- [ ] Use PostgreSQL for database
- [ ] Include Docker configuration

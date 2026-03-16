# Deployment

## Deployment Pipeline

Applications are deployed automatically through GitHub Actions. The full pipeline:

```
Developer Push
       │
       ▼
GitHub Actions
       │
       ├── Run Tests
       ├── Build Docker Image
       ├── SSH into Server
       ├── Deploy Containers
       ├── Run Database Migrations (inside container)
       ├── Health Check
       └── Enable Traffic
```

## GitHub Actions Workflow

Every repository includes a deployment workflow at `.github/workflows/deploy.yml`.

Typical steps:

1. Checkout repository
2. Run tests
3. Build Docker image
4. SSH into server
5. Pull latest code
6. Restart containers
7. Run health checks

Deployment command:

```bash
docker compose up -d --build
```

## Deploy Behavior

The platform rebuilds and restarts containers on each deploy. There is a brief gap where the application is unavailable.

```
Stop current container
        │
        ▼
Rebuild image from source
        │
        ▼
Start new container
        │
        ▼
Health check passes
        │
        ▼
Caddy routes traffic
```

During the rebuild and restart, Caddy returns 502 for requests to the application. This gap is typically a few seconds. For the target use case — small apps with low traffic — this is acceptable. See [Scope and Design Boundaries](scope.md) for when to consider alternatives.

### Docker Health Check Configuration

```yaml
services:
  app:
    build: ./app
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
```

If the health check fails, Docker will restart the container according to the `restart: always` policy.

## Database Migrations

Migrations run automatically as part of the deployment pipeline, **after the application container starts, by executing alembic inside the running container**.

```
Deploy started
      │
      ▼
Start containers
      │
      ▼
Run migrations (inside container)
      │
      ▼
Health check
```

Migration command:

```bash
docker compose exec app alembic -c app/alembic.ini upgrade head
```

### Safe Migration Rules

To avoid downtime during schema changes:

1. **Add** columns before removing columns
2. Avoid destructive migrations
3. Use multi-step schema evolution

Example safe pattern:

```
Deploy 1: Add new column
Deploy 2: Start using new column
Deploy 3: Remove old column
```

## Health Checks

Every application must provide a health endpoint:

```
GET /health → {"status": "ok"}
```

After deployment, the workflow verifies the application is healthy:

```bash
curl https://app.example.com/health
```

## Environment Promotion

The platform has two environments:

```
Pull Request → Preview environment
Merge to main → Production deployment
```

| Branch | Environment |
|---|---|
| PR branch | Preview |
| `main` | Production |

Preview environments are created automatically for pull requests and cleaned up when the PR is closed. See [Preview Environments](preview-environments.md) for details.

## Platform Capabilities Summary

| Feature | Implementation |
|---|---|
| CI/CD | GitHub Actions |
| Deploy pipeline | Rebuild and restart on push to main |
| Database migrations | Alembic |
| Preview environments | PR deployments |
| Object storage | MinIO |
| Queue system | Redis + Celery |
| Reverse proxy | Caddy |
| TLS | Automatic via Let's Encrypt |
| Persistent storage | `/data` volume |
| Transactional email | External provider |

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
       ├── Run Database Migrations
       ├── Deploy Containers
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

## Zero-Downtime Deployments

The platform uses rolling updates to keep applications available during deployments.

```
Current version (v1) running
        │
        ▼
Start new container (v2)
        │
Health check passes
        │
        ▼
Switch traffic to v2
        │
        ▼
Stop v1
```

Docker Compose starts the new container before removing the old one. The reverse proxy (Caddy) only forwards traffic to healthy services.

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

If the health check fails, traffic stays on the previous version.

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

The platform supports promotion through environments:

```
Pull Request → Preview environment
Merge to develop → Staging deployment
Merge to main → Production deployment
```

| Branch | Environment |
|---|---|
| PR branch | Preview |
| `develop` | Staging |
| `main` | Production |

## Platform Capabilities Summary

| Feature | Implementation |
|---|---|
| CI/CD | GitHub Actions |
| Zero-downtime deploys | Rolling container updates |
| Database migrations | Alembic |
| Preview environments | PR deployments |
| Object storage | MinIO |
| Queue system | Redis + Celery |
| Reverse proxy | Caddy |
| TLS | Automatic via Let's Encrypt |
| Persistent storage | `/data` volume |
| Transactional email | External provider |

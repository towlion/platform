---
user-invocable: false
description: Use when discussing app structure, deployment, or spec compliance
---

# Towlion Spec Context (v1.0)

Key rules from the Towlion platform specification:

## Required Structure
- `app/` — FastAPI backend with `Dockerfile` and `main.py`
- `deploy/` — `docker-compose.yml`, `docker-compose.standalone.yml`, `Caddyfile`, `env.template`
- `.github/workflows/deploy.yml`
- `scripts/health-check.sh`
- `README.md`
- `frontend/` — optional (Next.js)

## Backend
- HTTP server on **port 8000**: `uvicorn app.main:app --host 0.0.0.0 --port 8000`
- Health endpoint: `GET /health` returns `200` with `{"status": "ok"}`

## Environment Variables
- **Required**: `APP_DOMAIN`, `DATABASE_URL`, `REDIS_URL`
- **Optional**: `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `EMAIL_API_KEY`, `EMAIL_FROM`

## Dependencies
- `requirements.txt` (at repo root) or `pyproject.toml`
- Must include `fastapi` and `uvicorn`

## Docker
- `app/Dockerfile` is required, `frontend/Dockerfile` if frontend exists
- Container must expose port 8000 and read config from env vars

## Compose Files
- `docker-compose.yml` — app containers only (multi-app setup, no infra)
- `docker-compose.standalone.yml` — full stack with postgres/redis/minio/caddy (for self-hosted forks)

## Validation Tiers
- **Tier 1**: Structure — required files and directories exist
- **Tier 2**: Content — YAML valid, port 8000 referenced, env vars present, FastAPI used, no hardcoded secrets
- **Tier 3**: Runtime — containers build, compose validates, health endpoint responds

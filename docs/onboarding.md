# Onboarding

Getting started as a contributor or operator of the Towlion platform.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Git | 2.x+ | Version control |
| Docker | 24+ | Container runtime |
| Docker Compose | v2+ | Service orchestration |
| Python | 3.11+ | Backend development, validator |
| Node.js | 20+ | Frontend development |
| GitHub CLI (`gh`) | 2.x+ | Repository management |

## New Contributor Checklist

### 1. Understand the platform

- [ ] Read the [Architecture Overview](architecture.md) — how the platform works
- [ ] Read the [App Specification](spec.md) — the contract apps must follow
- [ ] Read the [Scope and Design Boundaries](scope.md) — what the platform does and doesn't do

### 2. Set up a development environment

- [ ] Fork or clone the [app-template](https://github.com/towlion/app-template) repository
- [ ] Install Python dependencies: `pip install -r requirements.txt`
- [ ] Run the app locally: `uvicorn app.main:app --reload --port 8000`
- [ ] Verify the health endpoint: `curl http://localhost:8000/health`

### 3. Run the spec validator

The platform repo includes a validator that checks apps against the spec:

```bash
git clone https://github.com/towlion/platform.git
cd platform
python validator/validate.py /path/to/your-app
```

All three tiers should pass before deploying.

### 4. Deploy to a server

- [ ] Bootstrap a server ([Self-Hosting Guide](self-hosting.md)) or get access to the test server
- [ ] Configure GitHub secrets: `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, `APP_DOMAIN`
- [ ] Push to `main` and verify the deploy workflow succeeds
- [ ] Check the app at `https://<your-domain>/health`

### 5. Review operational docs

- [ ] [Server Contract](server-contract.md) — directory layout, lifecycle, security
- [ ] [Governance](governance.md) — commit conventions, branch protection, PR process
- [ ] [Troubleshooting](troubleshooting.md) — common issues and fixes
- [ ] [Runbooks](runbooks/) — step-by-step operational procedures

## Key Concepts

| Concept | Description |
|---|---|
| GitHub as control plane | No custom dashboard — repos, Actions, and secrets manage everything |
| Fork-based self-hosting | Fork a repo, configure secrets, push to deploy on your own server |
| Shared infrastructure | PostgreSQL, Redis, MinIO, Caddy run once and serve all apps |
| Per-app isolation | Each app gets its own database, storage bucket, and container |
| Spec conformance | All apps follow the same contract (ports, endpoints, env vars) |

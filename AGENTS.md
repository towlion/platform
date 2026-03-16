# AGENTS.md

## Project Overview

This is the **Towlion Platform** repository — a spec-and-infrastructure repo that defines the architecture, specifications, infrastructure scripts, and guides for a self-hosted GitHub-native micro-PaaS. There is no runnable application code in this repository; it contains documentation, a spec validator, and server automation scripts.

## Repository Structure

```
docs/                  # All documentation (Markdown)
  index.md             # Landing page
  architecture.md      # Platform design, tech stack, diagrams
  spec.md              # Application contract (ports, endpoints, env vars)
  deployment.md        # CI/CD pipeline, zero-downtime deploys, migrations
  self-hosting.md      # Fork model, server requirements, bootstrap
  preview-environments.md  # PR previews, DNS, cleanup
  ecosystem.md         # Org structure, app template, multi-app hosting
  governance.md        # Repository governance policies
  roadmap.md           # Phased development plan
  tutorial.md          # Step-by-step deployment walkthrough
  server-contract.md   # Platform-to-workflow interface contract
infrastructure/        # Server bootstrap and ops scripts
  bootstrap-server.sh  # Debian -> running platform (idempotent)
  verify-server.sh     # Read-only server health check
  create-app-credentials.sh  # Per-app DB/S3 credential provisioning
  check-alerts.sh      # Cron health checker -> GitHub Issues
  backup-postgres.sh   # Daily per-database pg_dump
  restore-postgres.sh  # Restore from backup
  update-images.sh     # Weekly Docker image pull + recreate
  usage-report.sh      # Resource usage report
validator/
  validate.py          # Spec conformance validator (tiers 1-3)
scripts/
  setup-repo.sh        # GitHub repo governance setup script
  labels.json          # Standard labels for app repos (used by setup-repo.sh)
mkdocs.yml             # MkDocs Material site configuration
.github/workflows/
  docs.yml             # GitHub Pages deployment workflow
```

## What This Platform Defines

Towlion is a single-server micro-PaaS where GitHub acts as the control plane. Key concepts:

- **Tech stack**: Debian, Docker, Caddy, FastAPI, Next.js, PostgreSQL, Redis, MinIO, Celery
- **Deployment model**: GitHub Actions SSH into a server and run `docker compose up -d --build`
- **Self-hosting**: Users fork a repo, configure GitHub secrets, push, and the app deploys
- **Multi-app**: One server hosts multiple apps via subdomain routing through Caddy
- **App contract**: Backend on port 8000, `GET /health` endpoint, env-var configuration, PostgreSQL + Alembic migrations
- **Infrastructure automation**: Idempotent server bootstrap, per-app credential provisioning, backups, alerting, and image updates
- **Self-hosting env vars**: `ACME_EMAIL` (TLS certs), `OPS_DOMAIN` (Grafana route), `ALERT_REPO` (GitHub issue alerts) — all optional with sensible defaults

## Working With This Repo

### Documentation and Infrastructure

Documentation is in `docs/`, infrastructure scripts are in `infrastructure/`, and the spec validator is in `validator/`. There is no application code to run. Changes to docs should focus on clarity, accuracy, and consistency across documents.

### Local Preview

```bash
pip install mkdocs-material
mkdocs serve
```

Site serves at `http://127.0.0.1:8000` with auto-reload.

### Conventions

- Use standard Markdown with MkDocs Material extensions (admonitions, code highlighting, tabbed content)
- Use code fences with language tags for all code/config examples
- Keep language clear and concise — prefer short paragraphs and bullet points
- ASCII diagrams are used for architecture illustrations

### Branch Strategy

- `main` is the primary branch
- PRs should branch from `main` with descriptive names (e.g., `docs/add-monitoring-guide`)

## Key Relationships Between Documents

- `spec.md` defines the contract that all application repos must follow
- `architecture.md` describes the runtime environment those apps deploy into
- `deployment.md` explains the CI/CD pipeline that connects GitHub repos to the server
- `self-hosting.md` describes how forks configure and deploy independently
- `ecosystem.md` ties everything together — the org structure, template repo, and multi-app model
- `roadmap.md` tracks the phased plan from foundation through ecosystem growth

## Common Tasks

- **Adding a new documentation page**: Create a `.md` file in `docs/`, then add it to the `nav` section in `mkdocs.yml`
- **Updating the spec**: Edit `docs/spec.md` — ensure changes are consistent with `architecture.md` and `deployment.md`
- **Modifying site config**: Edit `mkdocs.yml` for theme, navigation, or extension changes
- **Running the spec validator**: `python validator/validate.py <path-to-app-repo>` — checks conformance at tiers 1-3
- **Modifying infrastructure scripts**: Edit files in `infrastructure/` — all scripts must pass `shellcheck` with zero warnings

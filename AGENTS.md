# AGENTS.md

## Project Overview

This is the **Towlion Platform** repository — a documentation-only repo that defines the architecture, specifications, and guides for a self-hosted GitHub-native micro-PaaS. There is no runnable application code in this repository; it contains only Markdown documentation and MkDocs configuration.

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
  roadmap.md           # Phased development plan
mkdocs.yml             # MkDocs Material site configuration
.github/workflows/
  docs.yml             # GitHub Pages deployment workflow
```

## What This Platform Defines

Towlion is a single-server micro-PaaS where GitHub acts as the control plane. Key concepts:

- **Tech stack**: Debian 12, Docker, Caddy, FastAPI, Next.js, PostgreSQL, Redis, MinIO, Celery
- **Deployment model**: GitHub Actions SSH into a server and run `docker compose up -d --build`
- **Self-hosting**: Users fork a repo, configure GitHub secrets, push, and the app deploys
- **Multi-app**: One server hosts multiple apps via subdomain routing through Caddy
- **App contract**: Backend on port 8000, `GET /health` endpoint, env-var configuration, PostgreSQL + Alembic migrations

## Working With This Repo

### Documentation Only

All content is Markdown in `docs/`. There are no tests, no build steps, and no application code to run. Changes should focus on clarity, accuracy, and consistency across documents.

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

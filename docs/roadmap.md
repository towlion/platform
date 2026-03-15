# Roadmap

This roadmap outlines the evolution of the Towlion platform toward a fully automated GitHub-driven deployment ecosystem. Each phase includes concrete deliverables and acceptance criteria.

## Phase 1 — Platform Foundation

Establish the core runtime environment.

- Define architecture and documentation
- Create application template repository
- Set up Docker runtime, Caddy, PostgreSQL, Redis, MinIO
- Server bootstrap automation (`infrastructure/bootstrap-server.sh` that installs Docker, Caddy, and platform services on a fresh Debian 12 server)

**Done when:** A fresh Debian 12 server can be bootstrapped to a running platform state by executing a single script. All platform services (PostgreSQL, Redis, MinIO, Caddy) are running and accessible.

**Status:** Complete.

## Phase 2 — Application Template

Create a reusable template for bootstrapping new applications.

- FastAPI backend scaffold
- Next.js frontend scaffold
- Docker configuration
- Deployment workflow
- Database migration setup

**Done when:** A new repo created from `app-template` passes Tier 2 spec validation with zero failures, and can be deployed to the platform server with no template modifications.

**Status:** Complete. Template passes 28/28 Tier 2 checks. Proven via todo-app deployment.

## Phase 3 — Automated Deployments

Automate the deploy-on-push pipeline.

- GitHub Actions deployment workflows (SSH to server, pull image, restart container)
- Health check verification after deployment (`/health` endpoint returns 200 within 60 seconds)
- Container rebuilds triggered by push to `main` branch (the only trigger — no scheduled or webhook-based rebuilds)
- Database migration automation (Alembic upgrade runs inside the app container after `docker compose up`)

**Done when:** Pushing to `main` on any app repo triggers a GitHub Actions workflow that deploys and verifies the app is healthy, with no manual SSH required. Tested with at least 2 different application repos.

**Status:** Complete. Tested with hello-world and todo-app deployed on the same server via the multi-app workflow. Deploy workflow auto-creates per-app databases, generates Caddyfiles with project-prefixed container names, and guards on `.env` existence.

## Phase 4 — Preview Environments

Enable preview deployments for pull requests. This is a significant feature requiring multiple subsystems.

- Wildcard DNS configuration (`*.preview.example.com` pointing to the platform server)
- PR-numbered container naming and Caddy route generation (e.g., `pr-42.preview.example.com`)
- Database isolation strategy: each preview gets a temporary PostgreSQL schema, created by running Alembic migrations against a PR-specific schema name, dropped on cleanup
- GitHub Actions workflow that deploys on PR open/update and cleans up (stop container, drop schema, remove Caddy route) on PR close via webhook

**Done when:** Opening a PR creates an accessible preview environment with its own database state. Closing the PR fully removes all preview resources. Tested with at least 2 concurrent previews.

**Status:** Complete. Wildcard DNS (`*.preview.anulectra.com`) configured. Preview workflow (`preview.yml`) added to app-template: deploys on PR open/sync, cleans up on PR close. Each PR gets an isolated PostgreSQL schema and a per-PR Caddyfile. Preview/production race condition fixed — each preview now gets its own clone directory (`/opt/apps/{APP_NAME}-pr-{N}`) instead of sharing the production directory.

## Phase 5 — Multi-App Platform

Support running many applications on a single server.

- Automatic subdomain routing via Caddy (each app gets `appname.example.com`)
- Shared platform services (PostgreSQL, Redis, MinIO) with per-app credentials and database isolation
- Per-app resource limits (Docker memory and CPU constraints to prevent a single app from starving others)

**Done when:** At least 3 apps run simultaneously on one server with independent subdomains, isolated databases, and no resource contention under normal load. Resource limits are enforced per container.

**Status:** Partially addressed. Two apps (todo-app at app.anulectra.com, hello-world at app2.anulectra.com) run simultaneously with isolated databases and independent Caddy routes. Per-app resource limits and credential isolation remain to be implemented.

## Phase 5.5 — Observability and Operations

Add the operational foundation required before opening the platform to self-hosters.

- Monitoring: container health dashboard (Caddy metrics, Docker stats)
- Logging: centralized log collection from all app containers
- Backups: automated PostgreSQL backups with retention policy
- Security: automated OS and Docker image security updates
- Cost visibility: disk, memory, and bandwidth usage tracking

**Done when:** Platform operator can view health of all running apps, restore from a backup, and receive alerts when a container is unhealthy or disk is >80% full.

**Status:** Not started. No monitoring, backup, or alerting exists.

## Phase 6 — Self-Hosting Ecosystem

Enable self-hosting through repository forks.

- Fork-based deployment model
- Documented deployment secrets
- Portable infrastructure
- Server bootstrap script (from Phase 1) is the critical dependency — without it, self-hosters must manually configure a server

**Done when:** A person who has never seen the project can fork an app repo, configure 4-5 secrets, run the bootstrap script on a fresh server, push to `main`, and have a working deployment. Tested by someone other than the author.

**Status:** Model is conceptually sound but impractical without bootstrap automation.

## Phase 7 — Application Development

Build applications on the platform. This is an app development effort, separate from platform engineering.

- Music tools (uku-companion, fretboard-trainer, chord-transposer, practice-timer)
- Developer utilities
- Small SaaS products

**Done when:** At least 2 non-trivial applications are deployed and publicly accessible on the platform.

**Status:** Todo-app (proof-of-concept) is live at app.anulectra.com. No non-trivial application repos exist yet.

## Long-Term Vision

A **GitHub-driven ecosystem of deployable applications**. Developers can build, publish, deploy, and self-host applications — all with minimal infrastructure.

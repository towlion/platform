# Towlion Platform

**Self-hosted GitHub-native micro-PaaS for deploying small web applications.**

Deploy full web applications to your own server directly from GitHub. No custom dashboards, no complex control planes — just GitHub repositories, Actions, and a single server.

## What is Towlion?

Most platforms require a central control plane:

```
CLI → platform API → Kubernetes → application containers
```

Towlion takes a different approach. **GitHub becomes the control plane.**

```
GitHub repository → GitHub Actions → SSH deploy → server runtime
```

Each repository contains everything required to deploy itself. Push code, and your application is live.

## Key Features

- **GitHub-native deployment** — no custom CLI or dashboard needed
- **Self-hosted infrastructure** — runs on your own Debian server
- **Multiple applications on one server** — shared PostgreSQL, Redis, MinIO
- **Automatic TLS certificates** — via Caddy and Let's Encrypt
- **Background workers** — Celery + Redis for async tasks
- **Object storage** — S3-compatible via MinIO
- **Preview environments** — temporary deployments for pull requests
- **Fork-based self-hosting** — anyone can fork and deploy

## Who Is It For?

Towlion is built for **indie developers, small SaaS products, personal tools, hobby projects, and AI-generated applications**. If your app serves a handful of users, runs comfortably on a single server, and you want to own your infrastructure without managing Kubernetes, Towlion is a good fit.

The platform has intentional constraints — single server only, opinionated stack, brief downtime during deploys. These are design boundaries, not missing features. They keep the platform simple and predictable. See [Scope and Design Boundaries](https://towlion.github.io/platform/scope/) for the full list.

## Quick Start

1. **Fork** the [app-template](https://github.com/towlion/app-template) repository (or use "Use this template" for a clean history)
2. **Bootstrap your server** — SSH into a Debian server and run the bootstrap script:
   ```bash
   ssh root@YOUR_SERVER_IP
   git clone https://github.com/towlion/platform.git /tmp/platform
   sudo ACME_EMAIL=you@example.com bash /tmp/platform/infrastructure/bootstrap-server.sh
   ```
3. **Configure GitHub secrets** — set these 4 repository secrets:
   | Secret | Value |
   |---|---|
   | `SERVER_HOST` | Your server IP |
   | `SERVER_USER` | `deploy` |
   | `SERVER_SSH_KEY` | SSH private key for the deploy user |
   | `APP_DOMAIN` | Your app's domain (e.g. `app.example.com`) |
4. **Push to main** — the deploy workflow builds, deploys, and provisions a database automatically

For the full walkthrough, see the [Deployment Tutorial](https://towlion.github.io/platform/tutorial/).

## Platform Stack

| Layer | Technology | Purpose |
|---|---|---|
| OS | Debian | Host operating system |
| Containers | Docker + Compose | Runtime and orchestration |
| Reverse proxy | Caddy | TLS + routing |
| Backend | FastAPI (Python) | Application API |
| Frontend | Next.js (React, TypeScript) | Web interface |
| Database | PostgreSQL | Persistent data |
| Cache / Queue | Redis | Caching + job queues |
| Object storage | MinIO | S3-compatible storage |
| Background jobs | Celery | Async processing |
| CI/CD | GitHub Actions | Automated deployments |

## Documentation

Full documentation is available at **[towlion.github.io/platform](https://towlion.github.io/platform)**.

- [Tutorial](https://towlion.github.io/platform/tutorial/) — step-by-step deployment walkthrough
- [Architecture](https://towlion.github.io/platform/architecture/) — platform design and diagrams
- [App Specification](https://towlion.github.io/platform/spec/) — application contract (ports, endpoints, env vars)
- [Self-Hosting](https://towlion.github.io/platform/self-hosting/) — fork model, server requirements, bootstrap
- [Troubleshooting](https://towlion.github.io/platform/troubleshooting/) — symptom-based debugging guide
- [Onboarding](https://towlion.github.io/platform/onboarding/) — new contributor checklist
- [Runbooks](https://towlion.github.io/platform/runbooks/restart-app/) — operational procedures
- [Architecture Decisions](https://towlion.github.io/platform/decisions/001-github-as-control-plane/) — ADRs

## License

MIT License

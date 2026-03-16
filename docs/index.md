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

## Why Towlion?

Most cloud platforms are designed for large-scale applications. Towlion focuses on a different use case: **small, deployable applications**.

The goal is to make it easy to:

- Build small web tools
- Deploy them quickly
- Self-host them on your own server
- Share them with others through GitHub

## Project Status

Early development. The platform is evolving toward a fully automated GitHub-driven deployment ecosystem.

## License

MIT License

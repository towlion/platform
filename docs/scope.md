# Scope and Design Boundaries

## What Towlion Is

- A **single-server micro-PaaS** for deploying small web applications
- **GitHub as the control plane** — no custom dashboard, CLI, or API
- **Docker Compose** for container orchestration, **Caddy** for reverse proxy and automatic TLS
- **Fork-to-deploy** model — fork a template repo, configure secrets, push to deploy
- **Opinionated stack** — FastAPI, PostgreSQL, Redis, MinIO, Celery

## Design Boundaries

These are intentional constraints, not missing features. They keep the platform simple and predictable.

### Infrastructure

| Boundary | Detail |
|---|---|
| Single server only | No clustering, no multi-server, no load balancing. Your server is a single point of failure by design. |
| Debian Linux only | The bootstrap script targets Debian 12. Other distributions are untested. |
| No automated server provisioning | You create and manage your own server. The bootstrap script configures it, but you are responsible for procurement and access. |
| Fixed resource limits | Static CPU and memory limits per container. No auto-scaling. |

### Deployment

| Boundary | Detail |
|---|---|
| Brief downtime during deploys | `docker compose up -d --build` rebuilds and restarts containers. Caddy returns 502 during the gap. This is typically a few seconds. |
| No built-in test pipeline | The deploy workflow builds and deploys. It does not run your test suite — add that step yourself if needed. |
| Push-to-main deploys | No staging environment, no approval gates, no canary or blue-green deploys. Merging to `main` deploys to production. |

### Operations

| Boundary | Detail |
|---|---|
| No high availability | Single PostgreSQL, Redis, and MinIO instances. No replication or automatic failover. |
| 5-minute alert granularity | Health checks run via cron every 5 minutes. This is not real-time monitoring. |
| 7-day backup retention | Daily `pg_dump` with 7-day retention. Recovery is manual. There is no disaster recovery plan beyond these backups. |
| No multi-tenant management | Each fork is independent. There is no shared admin panel or centralized management across apps. |

### Technology

| Boundary | Detail |
|---|---|
| Not Kubernetes | Docker Compose only. If you need pods, services, ingress controllers, or declarative infrastructure, use Kubernetes. |
| Opinionated stack | FastAPI + PostgreSQL + Redis + MinIO + Caddy. Other frameworks and databases are outside the supported path. |
| No container registry | Images are built on the server from source code. There is no registry push/pull step. |

## When to Use Something Else

| If you need... | Consider instead |
|---|---|
| Multi-server / high availability | Kubernetes, Docker Swarm, Nomad |
| Auto-scaling | AWS ECS, Cloud Run, Fly.io |
| Managed databases | AWS RDS, DigitalOcean Managed DB |
| Zero-downtime deploys | Kubernetes rolling updates, blue-green deploy tooling |
| Large-scale traffic | Cloud-native platforms with load balancers |
| Non-Python backends | Dokku, Coolify, CapRover |

## Sweet Spot

Towlion is built for indie developers, small SaaS products, personal tools, hobby projects, and AI-generated applications. If your app serves a handful of users, runs comfortably on a single server, and you want to own your infrastructure without managing Kubernetes, Towlion is a good fit.

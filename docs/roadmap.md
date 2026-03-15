# Roadmap

This roadmap outlines the evolution of the Towlion platform toward a fully automated GitHub-driven deployment ecosystem.

## Phase 1 — Platform Foundation

Establish the core runtime environment.

- Define architecture and documentation
- Build server bootstrap scripts
- Create application template repository
- Set up Docker runtime, Caddy, PostgreSQL, Redis, MinIO

**Result:** A working single-server runtime environment.

## Phase 2 — Application Template

Create a reusable template for bootstrapping new applications.

- FastAPI backend scaffold
- Next.js frontend scaffold
- Docker configuration
- Deployment workflow
- Database migration setup

**Result:** New applications can be created from the template in minutes.

## Phase 3 — Automated Deployments

Improve CI/CD automation.

- GitHub Actions deployment workflows
- Health checks after deployment
- Automatic container rebuilds
- Database migration automation

**Result:** Every repository can deploy itself on push.

## Phase 4 — Preview Environments

Enable preview deployments for pull requests.

- Temporary containers per PR
- Isolated database schemas
- Preview URLs (e.g., `pr-42.preview.example.com`)
- Automatic cleanup when PR closes

**Result:** Developers can preview changes before merging.

## Phase 5 — Multi-App Platform

Support running many applications on a single server.

- Automatic subdomain routing
- Shared platform services
- Per-app database isolation

**Result:** Run dozens of small apps on one server.

## Phase 6 — Self-Hosting Ecosystem

Enable self-hosting through repository forks.

- Fork-based deployment model
- Documented deployment secrets
- Portable infrastructure

**Result:** Anyone can self-host applications by forking.

## Phase 7 — Ecosystem Growth

Grow the Towlion application ecosystem.

- Music tools (uku-companion, fretboard-trainer)
- Developer utilities
- Small SaaS products
- AI-generated apps

**Result:** The GitHub organization becomes a catalog of deployable applications.

## Long-Term Vision

A **GitHub-driven ecosystem of deployable applications**. Developers can build, publish, deploy, and self-host applications — all with minimal infrastructure.

## Future Possibilities

- Automated server provisioning
- Centralized deployment controller
- Application registry
- CLI tools
- Automated DNS configuration

# Ecosystem

## GitHub Organization as Application Catalog

The Towlion GitHub organization serves as a catalog of deployable applications. Each repository is a standalone, self-hostable application.

```
towlion/
  .github              # Organization profile and community health files
  platform             # Architecture docs and platform tools (github.com/towlion/platform)
  app-template         # Template for bootstrapping new apps (github.com/towlion/app-template)
  uku-companion        # Music practice companion
  fretboard-trainer    # Guitar fretboard learning tool
  chord-transposer     # Chord transposition utility
  practice-timer       # Practice session timer
```

## Repository Types

### Organization Profile ([`towlion/.github`](https://github.com/towlion/.github))

The special `.github` repository provides the organization-level profile README displayed on [github.com/towlion](https://github.com/towlion). Contains:

- `profile/README.md` — marketing content shown on the org landing page

### Platform Repository (`towlion/platform`)

The meta repository for the ecosystem. Contains:

- Architecture documentation
- Platform specification
- Deployment guides
- Roadmap

### Application Template ([`towlion/app-template`](https://github.com/towlion/app-template))

A [GitHub Template Repository](https://github.com/towlion/app-template) for creating new applications. Includes:

- FastAPI backend scaffold
- Next.js frontend scaffold
- Docker configuration
- GitHub Actions deployment workflow
- Database migration setup

New apps are created by:

1. Click ["Use this template"](https://github.com/towlion/app-template/generate) to create a new repo
2. Customize the application code
3. Push — deploys automatically

### Application Repositories

Each application is a **separate GitHub repository** under the `towlion` organization. Each one:

- Is a standalone web application in its own repo
- Contains its own Docker configuration and deployment workflow
- Can be forked and self-hosted independently
- Follows the [application specification](spec.md)
- Follows the platform's [governance policies](governance.md), including branch protection, PR requirements, and commit conventions

## Multi-Application Runtime

The platform supports running many applications on a single server. All applications share core infrastructure:

```
Server
 ├── Caddy (reverse proxy)
 ├── PostgreSQL
 ├── Redis
 ├── MinIO
 ├── App 1 container
 ├── App 2 container
 └── App 3 container
```

Each application gets:

- Its own subdomain (e.g., `uku.towlion.com`)
- Its own database (e.g., `uku_db`)
- Its own storage bucket
- Its own container(s)

## Core Philosophy

### 1. Repository-Driven Deployment

Each repository deploys itself — no central deployment platform needed.

```
repository → GitHub Actions → deployed application
```

### 2. Forkable Infrastructure

Anyone can deploy by forking:

```
fork → configure secrets → push → running application
```

### 3. Single-Server SaaS

Optimized for indie developers, small SaaS apps, AI-generated tools, and personal product ecosystems.

## Target Use Cases

The ecosystem is designed for:

- Small SaaS applications
- Open-source developer tools
- Web utilities
- AI-generated applications
- Self-hosted services

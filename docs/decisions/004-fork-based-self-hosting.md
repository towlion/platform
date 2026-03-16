# ADR 004: Fork-Based Self-Hosting

**Date:** 2025-12-01
**Status:** Accepted

## Context

Self-hosted software typically uses one of these distribution models:

1. **Installer script** — download and run a setup script (e.g., `curl | bash`)
2. **Docker image** — pull a pre-built image from a registry
3. **Helm chart / Terraform module** — declarative infrastructure definition
4. **Fork** — fork the repository and deploy from your own copy

Each model has different trade-offs for isolation, customization, and update management.

## Decision

Use the fork model for self-hosting. Each operator forks the application repository, configures their own GitHub Secrets, and deploys from their fork.

```
Original repo -> fork by Alice -> alice.example.com
                -> fork by Bob   -> bob.example.com
                -> fork by Carol -> carol.example.com
```

## Consequences

**Benefits:**

- **Strong isolation** — each fork is completely independent; no shared tenancy
- **Full customization** — operators can modify any code, workflow, or configuration
- **No installer to maintain** — the repository is the installer
- **GitHub handles updates** — operators can sync upstream changes via GitHub's fork sync
- **Built-in CI/CD** — GitHub Actions workflows come with the fork
- **Transparent** — all deployment logic is visible in the repository

**Trade-offs:**

- Operators must manage their own GitHub Secrets and server
- Upstream updates require manual sync (GitHub's "Sync fork" button)
- No centralized management across forks — each is fully independent
- Requires GitHub account and understanding of fork workflows
- Private forks require a GitHub paid plan

# ADR 001: GitHub as the Control Plane

**Date:** 2025-12-01
**Status:** Accepted

## Context

Traditional PaaS platforms (Heroku, Render, Fly.io) require a dedicated control plane — a custom API, dashboard, or CLI that manages deployments, configuration, and access control. Building and maintaining a control plane is a significant engineering effort and introduces another system to secure and operate.

Towlion targets indie developers and small projects. The overhead of a custom control plane would outweigh its benefits for this audience.

## Decision

Use GitHub as the control plane for all platform operations:

- **CI/CD**: GitHub Actions workflows handle building, testing, and deploying
- **Configuration**: GitHub Secrets store deployment credentials
- **Access control**: GitHub repository permissions manage who can deploy
- **Workflow orchestration**: Actions workflows coordinate multi-step deployments
- **Issue tracking**: GitHub Issues for alerts (created by `check-alerts.sh`)

No custom dashboard, API server, or CLI is needed. The deployment flow is:

```
GitHub repository -> GitHub Actions -> SSH -> Docker runtime
```

## Consequences

**Benefits:**

- Zero infrastructure to build or maintain for the control plane
- Familiar interface — developers already use GitHub daily
- Built-in audit trail via commit history and Actions logs
- Free for public repos; generous free tier for private repos
- Access control, 2FA, and SSO handled by GitHub

**Trade-offs:**

- Vendor dependency on GitHub (Actions, Secrets, API)
- Limited to what GitHub Actions can express (no custom UI for deployments)
- Secrets management is per-repository, not centralized
- No real-time deployment dashboard — must check Actions tab for status

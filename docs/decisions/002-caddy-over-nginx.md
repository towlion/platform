# ADR 002: Caddy Over Nginx for Reverse Proxy

**Date:** 2025-12-01
**Status:** Accepted

## Context

The platform needs a reverse proxy to route traffic to application containers and handle TLS certificate provisioning. The two main contenders are Nginx (with certbot/Let's Encrypt) and Caddy.

## Decision

Use Caddy as the reverse proxy.

## Consequences

**Benefits:**

- **Automatic TLS** — Caddy provisions and renews Let's Encrypt certificates with zero configuration. No certbot cron jobs, no manual renewal scripts.
- **Simple configuration** — A Caddyfile is shorter and more readable than equivalent Nginx config. Adding a new app route is a 3-line file.
- **Per-app config fragments** — The `import /etc/caddy/apps/*.caddy` pattern allows deploy workflows to write individual `.caddy` files per app without editing a monolithic config.
- **Hot reload** — `caddy reload` applies config changes without dropping connections. No `nginx -s reload` dance.
- **Single binary** — No module system, no package dependencies. The official Docker image works out of the box.

**Trade-offs:**

- Nginx has broader community knowledge and more Stack Overflow answers
- Nginx supports more advanced configurations (TCP/UDP proxying, complex rewrites)
- Caddy is less battle-tested at high scale (not a concern for single-server deployments)
- Some hosting tutorials assume Nginx, requiring translation to Caddy equivalents

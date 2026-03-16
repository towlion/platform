# Plan: Expand Alert Checks in check-alerts.sh

> **Archived** — This plan has been fully implemented and verified. Kept for reference.

**Status**: Done (2026-03-16)

## What was done

Expanded `infrastructure/check-alerts.sh` from 3 checks to 7 checks:

| # | Check | Threshold | Status |
|---|-------|-----------|--------|
| 1 | Unhealthy containers | not "Up" or "(unhealthy)" | Existing |
| 2 | Disk usage | >80% | Existing |
| 3 | Memory usage | >90% | Existing |
| 4 | TLS certificate expiry | <14 days | **New** |
| 5 | Container restart counts | >3 restarts | **New** |
| 6 | Backup freshness | >36 hours or missing | **New** |
| 7 | HTTP endpoint health | non-2xx from /health | **New** |

## Additional fixes

- Excluded `ops.caddy` from HTTP health checks (Grafana returns 302 login redirect, not an error)
- Fixed backup freshness check to look for `*.dump` files (matching `backup-postgres.sh` output format, not `*.sql.gz`)
- Removed unused celery-worker services from `hello-world` and `todo-app` (crash-looping / stuck in Created state)
- Ran backup script to populate `/data/backups/postgres/`

## Verification

All 7 checks pass with zero alerts on the test server (143.198.104.8).

## Commits

- `e0ffc9f` feat: add TLS, restart, backup, and HTTP health checks to check-alerts.sh
- `4f8250b` fix: exclude ops.caddy from HTTP health checks
- `02da290` fix: match backup file extension in freshness check
- `d627982` (hello-world) fix: remove unused celery-worker service
- `8454b5e` (todo-app) fix: remove unused celery-worker service

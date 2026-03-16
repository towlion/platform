# ADR 006: Blue-Green Deployments

**Date:** 2026-03-16
**Status:** Accepted

## Context

The platform's original deploy workflow stops the old container before confirming the new one is healthy. This creates a brief window of downtime during each deployment — typically a few seconds while the new container starts and passes its healthcheck.

For a single-server platform hosting multiple small apps, this downtime window is usually tolerable but unnecessary. Docker Compose project names provide natural container isolation, meaning two versions of the same app can coexist on the shared `towlion` network. Caddy routes by container name, so updating the Caddyfile is an atomic traffic swap.

## Decision

Implement blue-green deploys using Docker Compose project name alternation:

1. Each app alternates between `APP-blue` and `APP-green` project names
2. The active slot is tracked in `/opt/apps/<name>/.deploy-slot`
3. New containers start alongside old ones on the `towlion` network
4. Traffic switches only after the new container passes healthchecks
5. Old containers are stopped only after external health verification
6. On any failure after the new slot starts, the new slot is torn down and the old slot continues serving traffic

The deploy script (`infrastructure/deploy-blue-green.sh`) replaces the inline SSH deploy logic in the reusable workflow.

## Consequences

**Benefits:**

- Zero downtime during deploys — old container serves traffic until new one is verified
- Automatic rollback on failure — new slot is torn down, old slot keeps running
- No additional infrastructure needed — uses existing Docker Compose and Caddy
- Backward compatible — apps need zero changes, only the server-side script and workflow change
- First deploy handles migration from non-slotted project names gracefully

**Trade-offs:**

- Brief period during deploy where two containers consume resources simultaneously
- `.deploy-slot` file must be preserved across server maintenance
- Container names change from `APP-app-1` to `APP-blue-app-1` / `APP-green-app-1`, affecting Caddyfile templates
- Slightly more complex deploy logic compared to the previous inline approach

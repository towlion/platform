# ADR 003: Single-Server Architecture

**Date:** 2025-12-01
**Status:** Accepted

## Context

Modern deployment platforms typically use container orchestration (Kubernetes, Docker Swarm, Nomad) to distribute workloads across multiple servers. This provides high availability, auto-scaling, and fault tolerance — but at significant operational complexity.

Towlion targets indie developers, small SaaS products, and hobby projects. These applications typically serve a handful of users and run comfortably on a single server.

## Decision

Limit the platform to a single Debian server. All applications, databases, and infrastructure services run on one machine using Docker Compose.

## Consequences

**Benefits:**

- **Simplicity** — no cluster management, no service mesh, no distributed consensus
- **Low cost** — a single $12-24/month VPS runs the entire platform
- **Easy debugging** — everything is on one machine; `docker logs` and `docker exec` are sufficient
- **Fast deploys** — no image registry push/pull; images build locally from source
- **Predictable** — no network partitions, no node failures, no split-brain scenarios

**Trade-offs:**

- Single point of failure — if the server goes down, all apps go down
- No auto-scaling — resource limits are static
- Brief downtime during deploys (container rebuild takes a few seconds)
- Vertical scaling only — must move to a bigger server when capacity is reached
- Not suitable for high-traffic applications or strict uptime requirements

These are intentional design boundaries, not missing features. For workloads that need HA or auto-scaling, use Kubernetes, Fly.io, or a cloud-native platform instead.

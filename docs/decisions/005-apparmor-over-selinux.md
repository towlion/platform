# ADR 005: AppArmor Over SELinux

**Date:** 2026-03-01
**Status:** Accepted

## Context

Mandatory Access Control (MAC) adds a security layer beyond standard Unix permissions. The two main MAC systems on Linux are AppArmor and SELinux. The platform runs on Debian 12, which ships with AppArmor enabled by default.

## Decision

Use AppArmor (Debian's native MAC system) instead of SELinux.

Docker automatically applies the `docker-default` AppArmor profile to all containers, which restricts capabilities like writing to `/proc` and `/sys`, mounting filesystems, and accessing raw sockets. No additional configuration is needed.

## Consequences

**Benefits:**

- **Zero configuration** — AppArmor is already active on Debian 12 out of the box
- **Docker integration** — Docker applies the `docker-default` profile automatically to every container
- **Debian-native** — maintained by the Debian security team, well-tested with Debian packages
- **Simple profile model** — AppArmor profiles are path-based and easier to read than SELinux policies

**Trade-offs:**

- AppArmor is less granular than SELinux (path-based vs. label-based)
- SELinux is the standard on RHEL/Fedora ecosystems; cross-distro documentation often assumes SELinux

**Why not SELinux on Debian:**

- SELinux policies on Debian are incomplete — the `selinux-policy-default` package lags far behind RHEL equivalents
- Docker + SELinux on Debian causes bind-mount labeling issues (`:z`/`:Z` volume flags) with no community support
- Enabling SELinux requires disabling AppArmor, losing Docker's automatic profile enforcement
- The Debian security team does not maintain SELinux policies to the same standard as AppArmor

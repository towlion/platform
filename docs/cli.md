# Towlion CLI

The `towlion` CLI wraps common platform operations into a single command. It uses SSH for server operations and the GitHub CLI (`gh`) for workflow triggers.

## Installation

```bash
# From the platform repo
cp cli/towlion /usr/local/bin/towlion
chmod +x /usr/local/bin/towlion
```

## Configuration

Create `~/.towlion.conf`:

```bash
SERVER_HOST=143.198.104.8
SERVER_USER=deploy
SSH_KEY_PATH=~/.ssh/id_rsa
```

## Commands

### `towlion status`

List all apps with container state and health status.

### `towlion logs <app>`

Tail logs for an app (uses `docker compose logs -f`).

### `towlion health [app|all]`

Check `/health` endpoints. Defaults to `all` if no app specified.

### `towlion create <app>`

Create a new app from the template:
1. Creates GitHub repo from `towlion/app-template`
2. Provisions PostgreSQL and MinIO credentials on the server
3. Clones the repo on the server
4. Creates `deploy/.env` from template

Requires `gh` CLI to be installed and authenticated.

### `towlion deploy <app>`

Trigger the deploy workflow via GitHub Actions (`gh workflow run`).

### `towlion restart <app>`

Restart app containers. Automatically detects the active blue-green slot.

### `towlion backup [app|all]`

Run a database backup. Defaults to all databases if no app specified.

### `towlion rotate <app> [--type db|s3|all]`

Rotate credentials for an app without downtime. Defaults to rotating all credentials.

### `towlion ssh`

SSH to the server as the deploy user.

### `towlion tunnel <port>`

Open an SSH tunnel. Useful for accessing internal services:

```bash
towlion tunnel 5432   # PostgreSQL
towlion tunnel 3000   # Grafana
towlion tunnel 9000   # MinIO
```

### `towlion verify`

Run `verify-server.sh` to check server health (30 checks).

### `towlion alerts`

Run `check-alerts.sh` to check for active alerts.

# Runbook: Add a New Application

## When to Use

- Deploying a new application to the server
- Setting up a new repo from the app template

## Prerequisites

- Server already bootstrapped ([Self-Hosting Guide](../self-hosting.md))
- DNS A record pointing your app domain to the server IP
- SSH access as the `deploy` user

## Steps

### 1. Create the repository

Use GitHub's "Use this template" button on [towlion/app-template](https://github.com/towlion/app-template) to create a new repo under the `towlion` organization (or your own account).

### 2. Provision per-app credentials on the server

```bash
ssh deploy@YOUR_SERVER_IP
sudo bash /opt/platform/infrastructure/create-app-credentials.sh <app-name>
```

This creates an isolated PostgreSQL user, MinIO bucket, and writes credentials to `/opt/platform/credentials/<app-name>.env`.

### 3. Clone the repo on the server

```bash
ssh deploy@YOUR_SERVER_IP
cd /opt/apps
git clone https://github.com/<org>/<app-name>.git
```

### 4. Create `deploy/.env`

```bash
cd /opt/apps/<app-name>
cp deploy/env.template deploy/.env
```

Edit `deploy/.env` with your values. If you ran `create-app-credentials.sh`, the deploy workflow will automatically fill in the database and S3 credentials on first deploy.

### 5. Configure GitHub secrets

Set these repository secrets (**Settings > Secrets and variables > Actions**):

| Secret | Value |
|---|---|
| `SERVER_HOST` | Your server IP |
| `SERVER_USER` | `deploy` |
| `SERVER_SSH_KEY` | SSH private key for the deploy user |
| `APP_DOMAIN` | Your app's domain (e.g., `app.example.com`) |

Optional:

| Secret | Value |
|---|---|
| `PREVIEW_DOMAIN` | Base domain for PR previews (e.g., `example.com`) |

### 6. Push to main

Push code to the `main` branch. The deploy workflow will:

1. SSH into the server
2. Pull the latest code
3. Create the app database (if it doesn't exist)
4. Build and start containers
5. Run Alembic migrations
6. Write a Caddyfile and reload Caddy

### 7. Verify

```bash
curl -s https://<app-domain>/health
```

Expected: `{"status": "healthy"}` with HTTP 200.

## References

- [Deployment Tutorial](../tutorial.md) — full step-by-step walkthrough
- [Deploy Prompt](../deploy-prompt.md) — reusable Claude Code session prompt for deployments
- [Server Contract](../server-contract.md) — directory layout and lifecycle details

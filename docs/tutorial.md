# Deployment Tutorial

This tutorial walks you through deploying a Towlion application from fork to running service. By the end, you will have a live application on your own server with automatic TLS, a database, and continuous deployment from GitHub.

!!! tip "Before you start"
    This is a hands-on guide with concrete commands. For background on *why* the platform works this way, see [Self-Hosting](self-hosting.md) for the fork model and [Deployment](deployment.md) for pipeline internals.

## Prerequisites

You will need:

- A **GitHub account**
- A **Debian 12 server** (VPS from any provider — Hetzner, DigitalOcean, Linode, etc.)
- A **domain name** you control (for DNS configuration)
- A local machine with **Git** and **SSH** installed

| Resource | Minimum |
|---|---|
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | 50 GB |

## Step 1: Fork the app repository

Go to the application repository on GitHub (for example, [towlion/app-template](https://github.com/towlion/app-template)) and click **Fork**.

Then clone your fork locally:

```bash
git clone git@github.com:YOUR_USERNAME/app-template.git
cd app-template
```

!!! tip
    If you are creating a new app rather than deploying an existing one, use the **Use this template** button on [towlion/app-template](https://github.com/towlion/app-template) instead of forking. This gives you a clean commit history.

## Step 2: Provision a server

Create a Debian 12 server from your preferred provider. Make sure:

- Ports **22**, **80**, and **443** are open in the firewall
- You can SSH in as a non-root user with sudo access

Verify access:

```bash
ssh deploy@YOUR_SERVER_IP
```

You should see a shell prompt. If this works, you are ready to bootstrap.

## Step 3: Bootstrap the server

SSH into your server and install Docker:

```bash
ssh deploy@YOUR_SERVER_IP
```

Install Docker using the official convenience script:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

!!! warning
    Log out and back in after adding yourself to the `docker` group, or the next commands will fail with a permission error.

```bash
exit
ssh deploy@YOUR_SERVER_IP
```

Verify Docker is working:

```bash
docker run --rm hello-world
```

You should see `Hello from Docker!` in the output.

Create the data directory structure:

```bash
sudo mkdir -p /data/{postgres,redis,minio,caddy}
sudo chown -R $USER:$USER /data
```

This is where persistent data lives across deployments. The directory layout:

```
/data/
  postgres/    # Database files
  redis/       # Cache and queue data
  minio/       # Object storage
  caddy/       # TLS certificates and config
```

## Step 4: Configure DNS

Go to your domain registrar or DNS provider and add an **A record** pointing to your server:

```
Type: A
Name: app          (or your chosen subdomain)
Value: YOUR_SERVER_IP
TTL: 300
```

For example, if your domain is `example.com` and your server IP is `203.0.113.42`:

```
A record: app.example.com -> 203.0.113.42
```

Verify DNS propagation:

```bash
dig +short app.example.com
```

Expected output:

```
203.0.113.42
```

!!! tip
    DNS propagation can take a few minutes to a few hours. Wait until `dig` returns your server IP before proceeding.

## Step 5: Configure GitHub secrets

In your forked repository on GitHub, go to **Settings > Secrets and variables > Actions** and add the following repository secrets:

| Secret | Example value | Description |
|---|---|---|
| `SERVER_HOST` | `203.0.113.42` | Your server's IP address |
| `SERVER_USER` | `deploy` | SSH username on the server |
| `SERVER_SSH_KEY` | *(private key contents)* | SSH private key for deployment |
| `APP_DOMAIN` | `app.example.com` | Domain pointing to your server |
| `DATABASE_PASSWORD` | *(strong password)* | PostgreSQL password |
| `MINIO_ROOT_USER` | `minio-admin` | MinIO admin username |
| `MINIO_ROOT_PASSWORD` | *(strong password)* | MinIO admin password |

### Generate a deploy SSH key

Create a dedicated key pair for deployment:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N ""
```

Add the **public** key to your server:

```bash
ssh-copy-id -i ~/.ssh/deploy_key.pub deploy@YOUR_SERVER_IP
```

Copy the **private** key contents into the `SERVER_SSH_KEY` secret:

```bash
cat ~/.ssh/deploy_key
```

Paste the full output (including the `-----BEGIN` and `-----END` lines) into the secret value field on GitHub.

## Step 6: Deploy

Push a commit to the `main` branch to trigger deployment:

```bash
git push origin main
```

GitHub Actions picks this up automatically. Go to the **Actions** tab in your repository to watch the workflow run.

```
Push to main
     |
     v
GitHub Actions
     |
     +-- Run tests
     +-- SSH into server
     +-- Pull latest code
     +-- Build containers
     +-- Start services
     +-- Run database migrations (inside container)
     +-- Health check
```

The workflow typically completes in 2-5 minutes.

!!! tip
    If the workflow does not appear, check that the `.github/workflows/deploy.yml` file exists in your repository. Repositories created from the app template include this file by default.

## Step 7: Verify

Once the workflow succeeds, check your application is running.

Test the health endpoint:

```bash
curl https://app.example.com/health
```

Expected response:

```json
{"status": "ok"}
```

Open `https://app.example.com` in your browser. You should see your application with a valid TLS certificate (Caddy provisions this automatically via Let's Encrypt).

Your application is now live.

## Updating your app

To deploy changes, commit and push to `main`:

```bash
git add .
git commit -m "feat: add new feature"
git push origin main
```

GitHub Actions runs the deployment pipeline automatically. The platform uses [rolling updates](deployment.md#zero-downtime-deployments) so your application stays available during deploys.

To pull upstream changes from the original repository:

```bash
git remote add upstream https://github.com/towlion/app-template.git
git fetch upstream
git merge upstream/main
git push origin main
```

## Troubleshooting

### DNS not resolving

**Symptom**: `dig +short app.example.com` returns nothing.

**Fix**: Wait for DNS propagation (up to 48 hours in rare cases). Verify the A record is set correctly in your DNS provider's dashboard. Try flushing your local DNS cache:

```bash
# macOS
sudo dscacheutil -flushcache

# Linux
sudo systemd-resolve --flush-caches
```

### SSH key rejected

**Symptom**: GitHub Actions workflow fails with `Permission denied (publickey)`.

**Fix**: Verify the `SERVER_SSH_KEY` secret contains the full private key including header and footer lines. Ensure the corresponding public key is in `~/.ssh/authorized_keys` on the server. Check that the key format is correct:

```bash
# The secret should start with:
-----BEGIN OPENSSH PRIVATE KEY-----

# And end with:
-----END OPENSSH PRIVATE KEY-----
```

### Health check fails

**Symptom**: Deployment completes but `curl https://app.example.com/health` returns an error.

**Fix**: SSH into the server and check container status:

```bash
ssh deploy@YOUR_SERVER_IP
docker compose ps
```

All services should show `Up` status. Check application logs:

```bash
docker compose logs app --tail 50
```

Common causes:

- Database migration failed — run `docker compose exec app alembic -c app/alembic.ini upgrade head` to retry migrations, and check `docker compose logs app` for errors
- Missing environment variable — verify all secrets are set in GitHub
- Port conflict — ensure no other service is using ports 80 or 443

### Containers not starting

**Symptom**: `docker compose ps` shows containers in `Restarting` or `Exit` state.

**Fix**: Check the logs for the failing container:

```bash
docker compose logs postgres --tail 50
docker compose logs app --tail 50
```

If PostgreSQL fails to start, verify the `/data/postgres` directory exists and has correct permissions:

```bash
ls -la /data/postgres
```

### TLS certificate not provisioning

**Symptom**: Browser shows a certificate warning when visiting your domain.

**Fix**: Caddy provisions TLS certificates automatically, but requires:

1. DNS is correctly pointing to your server
2. Ports 80 and 443 are open and reachable from the internet
3. The domain is set correctly in your app configuration

Check Caddy logs:

```bash
docker compose logs caddy --tail 50
```

---

For more details on the deployment pipeline, see [Deployment](deployment.md). For the full list of application requirements, see the [App Specification](spec.md).

# Self-Hosted GitHub Actions Runners

## Overview

By default, Towlion deploys applications using **GitHub-hosted runners** that SSH into your server. An alternative approach is to run a **self-hosted GitHub Actions runner** directly on your server. This eliminates the SSH dependency entirely — the runner executes deploy commands locally instead of over a network connection.

## Comparison

| | GitHub-Hosted (default) | Self-Hosted Runner |
|---|---|---|
| **Required secrets** | 4 (`SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`, `APP_DOMAIN`) | 1 (`APP_DOMAIN`) |
| **Network dependency** | SSH from GitHub to your server | Runner polls GitHub for jobs |
| **Deploy speed** | Slower (SSH overhead, file transfer) | Faster (commands run locally) |
| **Maintenance** | None — GitHub manages the runner | You maintain the runner binary and keep it updated |
| **Security model** | SSH key grants deploy access | Runner process has local access; compromise = server compromise |
| **Firewall** | Port 22 must be open | No inbound ports required (runner uses outbound HTTPS) |

## When to Use Self-Hosted Runners

Consider self-hosted runners if:

- You want to **reduce secrets** from 4 to 1
- You want **faster deploys** without SSH overhead
- You prefer **no inbound SSH** on your server (tighter firewall)
- You're comfortable maintaining the runner software

Stick with GitHub-hosted runners (the default) if:

- You prefer **zero maintenance** on the runner side
- You want the **simplest setup** with no extra software
- You don't want to manage runner updates or monitor runner health

## Setup

### 1. Install the Runner

On your server, as the `deploy` user:

```bash
# Create a directory for the runner
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download the latest runner (check https://github.com/actions/runner/releases for current version)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz

tar xzf actions-runner-linux-x64.tar.gz
```

### 2. Register the Runner

Go to your fork's **Settings > Actions > Runners > New self-hosted runner** and copy the registration token. Then:

```bash
./config.sh --url https://github.com/YOUR_USER/YOUR_REPO --token YOUR_TOKEN
```

Accept the defaults or customize the runner name and labels.

### 3. Install as a Service

```bash
sudo ./svc.sh install deploy
sudo ./svc.sh start
```

This creates a systemd service that starts the runner on boot and keeps it running.

### 4. Verify

Check that the runner appears as "Idle" in your fork's **Settings > Actions > Runners**.

## Workflow Changes

With a self-hosted runner, your deploy workflow no longer needs SSH. Here's what to change:

### deploy.yml

Replace:

```yaml
runs-on: ubuntu-latest
```

With:

```yaml
runs-on: self-hosted
```

Remove the SSH action and replace remote commands with local commands. For example, instead of:

```yaml
- name: Deploy via SSH
  uses: appleboy/ssh-action@v1
  with:
    host: ${{ secrets.SERVER_HOST }}
    username: ${{ secrets.SERVER_USER }}
    key: ${{ secrets.SERVER_SSH_KEY }}
    script: |
      cd /opt/apps/$APP_NAME
      docker compose -f deploy/docker-compose.yml pull
      docker compose -f deploy/docker-compose.yml up -d
```

Use:

```yaml
- name: Deploy
  run: |
    cd /opt/apps/$APP_NAME
    git pull origin main
    docker compose -f deploy/docker-compose.yml pull
    docker compose -f deploy/docker-compose.yml up -d
```

The same pattern applies to `preview.yml` — replace `runs-on` and convert SSH commands to local commands.

### Secrets

With self-hosted runners, you only need:

| Secret | Purpose |
|---|---|
| `APP_DOMAIN` | Application domain name |

The other 3 secrets (`SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY`) are no longer needed since commands run directly on the server.

## Security Considerations

- **Runner compromise = server compromise.** The runner process can execute arbitrary commands as the `deploy` user. Protect your repository — anyone with push access can run code on your server via workflow files.
- **Keep the runner updated.** GitHub periodically releases security patches. The runner auto-updates by default, but verify this is working.
- **Restrict fork PRs.** By default, workflows from fork pull requests don't run on self-hosted runners. Keep this default — allowing fork PRs to trigger workflows on your server is a significant security risk.
- **Use a dedicated user.** The runner should run as the `deploy` user (not root), which is already the case if you follow the setup above.

## Troubleshooting

### Runner shows as "Offline"

Check the service status:

```bash
sudo ./svc.sh status
```

If stopped, restart it:

```bash
sudo ./svc.sh start
```

### Jobs stay queued

Verify the runner labels match the `runs-on` value in your workflow. The default label is `self-hosted`. Check with:

```bash
./config.sh --list
```

### Runner won't update

The runner normally auto-updates. If it fails, manually download the latest release and re-extract:

```bash
cd ~/actions-runner
sudo ./svc.sh stop
curl -o actions-runner-linux-x64.tar.gz -L <latest-release-url>
tar xzf actions-runner-linux-x64.tar.gz
sudo ./svc.sh start
```

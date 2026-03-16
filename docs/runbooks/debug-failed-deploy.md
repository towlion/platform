# Runbook: Debug a Failed Deployment

## When to Use

- GitHub Actions deploy workflow fails
- App is not accessible after a deploy
- Containers are crashing after deploy

## Diagnostic Steps

### 1. Check GitHub Actions logs

Go to the repository's **Actions** tab and open the failed workflow run. Check both jobs:

- **test** — build and test failures (Dockerfile issues, missing dependencies, test failures)
- **deploy** — SSH or server-side failures

Look for the first red step. The error message usually points directly to the cause.

### 2. SSH into the server

```bash
ssh deploy@YOUR_SERVER_IP
```

### 3. Check container status

```bash
docker compose -p <app-name> -f /opt/apps/<app-name>/deploy/docker-compose.yml ps
```

Look for containers in `Restarting`, `Exited`, or `Created` (not `Up`) states.

### 4. Check container logs

```bash
docker compose -p <app-name> -f /opt/apps/<app-name>/deploy/docker-compose.yml logs --tail 100 app
```

Common error patterns:

- `ModuleNotFoundError` — missing Python dependency in `requirements.txt`
- `Connection refused` to postgres — database not reachable or wrong credentials
- `Address already in use` — port conflict with another container
- `PermissionError` — file ownership issue in mounted volumes

### 5. Check disk space and memory

```bash
df -h /
free -h
docker system df
```

If disk is above 90%, clean up:

```bash
docker system prune -f
```

### 6. Verify the Docker network

```bash
docker network inspect towlion
```

Confirm the app container and platform services (postgres, redis, caddy) are all on the `towlion` network.

### 7. Verify `deploy/.env`

```bash
cat /opt/apps/<app-name>/deploy/.env
```

Check that `DATABASE_URL`, `SECRET_KEY`, and other required variables are set. Compare against `deploy/env.template` for any missing values.

### 8. Check the Caddyfile

```bash
cat /opt/platform/caddy-apps/<app-name>.caddy
```

Verify:
- The domain matches `APP_DOMAIN`
- The upstream container name is correct (e.g., `<app-name>-app-1:8000`)
- The `security_headers` snippet is imported

Reload Caddy if you made changes:

```bash
docker compose -f /opt/platform/docker-compose.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile
```

## Common Causes

| Symptom | Likely Cause | Fix |
|---|---|---|
| SSH connection refused | Wrong `SERVER_HOST` or SSH key | Verify GitHub secret matches server IP and key |
| Docker build fails | Missing dependency or syntax error | Fix `Dockerfile` or `requirements.txt` |
| Container exits immediately | Missing env var or import error | Check `deploy/.env` and container logs |
| 502 Bad Gateway | App container not running or wrong upstream | Check `docker ps` and Caddyfile |
| Alembic migration fails | Schema conflict or missing migration | SSH in and run `alembic upgrade head` manually to see the error |
| "Network not found" | `towlion` network missing | Run `docker network create towlion` |
| Disk full | Old images/containers accumulating | `docker system prune -f` |
| Permission denied | File ownership mismatch | Check that `deploy` user owns `/opt/apps/<app-name>` |

## After Fixing

1. Re-run the deploy workflow from the GitHub Actions tab (click "Re-run all jobs")
2. Or trigger a new deploy by pushing a commit
3. Verify the health endpoint: `curl -s https://<app-domain>/health`

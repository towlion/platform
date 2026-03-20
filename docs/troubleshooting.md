# Troubleshooting

Symptom-based guide for diagnosing common platform issues.

## Container Won't Start

**Check:**

```bash
docker compose -p <app-name> -f /opt/apps/<app-name>/deploy/docker-compose.yml logs --tail 50 app
docker compose -p <app-name> -f /opt/apps/<app-name>/deploy/docker-compose.yml ps
```

**Common causes:**

| Cause | What you'll see | Fix |
|---|---|---|
| Missing env var | `KeyError` or `ValidationError` in logs | Add the variable to `deploy/.env` |
| Port conflict | `Address already in use` | Check `docker ps` for conflicting containers |
| Image build failure | Container stuck in `Created` state | Check build output in GitHub Actions logs |
| Import error | `ModuleNotFoundError` | Add the missing package to `requirements.txt` |
| Bad migration | `alembic.util.exc.CommandError` | Fix the migration and re-deploy |

## Caddy Certificate Provisioning Fails

**Check:**

```bash
docker compose -f /opt/platform/docker-compose.yml logs --tail 50 caddy
```

**Common causes:**

| Cause | What you'll see | Fix |
|---|---|---|
| DNS not pointed | `no A/AAAA records found` | Create an A record pointing the domain to the server IP |
| Rate limit hit | `too many certificates` | Wait 1 hour (Let's Encrypt rate limit resets) |
| Port 80 blocked | `connection refused` on ACME challenge | Verify UFW allows port 80: `sudo ufw status` |
| Wrong domain in Caddyfile | Certificate for wrong domain | Check `/opt/platform/caddy-apps/<app>.caddy` |

**Verify DNS:**

```bash
dig +short <app-domain>
# Should return your server IP
```

## Database Connection Refused

**Check:**

```bash
docker exec platform-postgres-1 pg_isready
docker compose -f /opt/platform/docker-compose.yml ps postgres
```

**Common causes:**

| Cause | What you'll see | Fix |
|---|---|---|
| PostgreSQL container down | `pg_isready` fails or container not `Up` | `cd /opt/platform && docker compose up -d postgres` |
| Wrong credentials | `password authentication failed` in app logs | Verify `DATABASE_URL` in `deploy/.env` matches credentials |
| Database doesn't exist | `database "<name>" does not exist` | The deploy workflow creates it automatically; re-run the deploy |
| Not on Docker network | `could not translate host name "postgres"` | Check app container is on the `towlion` network |

## App Returns 502 Bad Gateway

**Check:**

```bash
# Is the app container running?
docker ps --filter name=<app-name>

# What do the app logs say?
docker compose -p <app-name> -f /opt/apps/<app-name>/deploy/docker-compose.yml logs --tail 50 app

# What does the Caddyfile say?
cat /opt/platform/caddy-apps/<app-name>.caddy
```

**Common causes:**

| Cause | What you'll see | Fix |
|---|---|---|
| App container crashed | Container not in `docker ps` output | Check logs, fix the crash, restart |
| App still starting | 502 for a few seconds after deploy | Wait 5-10 seconds; if persistent, check logs |
| Wrong upstream in Caddyfile | Caddy can't reach the container | Verify container name matches Caddyfile (e.g., `<app-name>-app-1:8000`) |
| App listening on wrong port | Container running but not responding | Verify the app binds to `0.0.0.0:8000` |

## Preview Environment Not Accessible

**Check:**

```bash
# DNS resolves?
dig +short pr-<N>.preview.<app>.<domain>

# Caddyfile exists?
cat /opt/platform/caddy-apps/<app-name>-pr-<N>.caddy

# Container running?
docker ps --filter name=<app-name>-pr-<N>
```

**Common causes:**

| Cause | What you'll see | Fix |
|---|---|---|
| Wildcard DNS not set | `dig` returns nothing | Add `*.preview.<app>.<domain>` A record pointing to server IP |
| Preview container crashed | Container not running | Check logs: `docker logs <app-name>-pr-<N>-app-1` |
| Missing `PREVIEW_DOMAIN` secret | Workflow skips preview deployment | Set `PREVIEW_DOMAIN` in repo secrets |
| PR already closed | Cleanup removed the container | Reopen the PR or push a new commit to trigger preview |

## Disk Space Full

**Check:**

```bash
df -h /
df -h /data
docker system df
du -sh /data/*
du -sh /var/log/*
```

**Fix by priority:**

1. **Docker cleanup** — remove unused images, containers, and build cache:
   ```bash
   docker system prune -f
   docker image prune -a -f  # removes ALL unused images
   ```

2. **Old backups** — backups older than 7 days should be auto-pruned, but check:
   ```bash
   ls -lh /data/backups/postgres/
   ```

3. **Log files** — check for oversized log files:
   ```bash
   du -sh /var/log/* | sort -rh | head -10
   ```

4. **Loki data** — if log storage is consuming significant space:
   ```bash
   du -sh /data/loki/
   ```

**Prevention:** The `check-alerts.sh` cron job (every 5 minutes) creates a GitHub issue when disk usage exceeds 90%.

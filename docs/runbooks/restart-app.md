# Runbook: Restart an Application

## When to Use

- Application is unresponsive or returning errors
- After a configuration change in `deploy/.env`
- After manual database changes that require the app to reconnect

## Steps

### 1. SSH into the server

```bash
ssh deploy@YOUR_SERVER_IP
```

### 2. Navigate to the app directory

```bash
cd /opt/apps/<app-name>
```

### 3. Restart the app container

```bash
docker compose -p <app-name> -f deploy/docker-compose.yml restart app
```

To restart all containers for the app (including workers if present):

```bash
docker compose -p <app-name> -f deploy/docker-compose.yml restart
```

### 4. Verify the container is running

```bash
docker compose -p <app-name> -f deploy/docker-compose.yml ps
```

All services should show `Up` status.

### 5. Check the health endpoint

```bash
curl -s https://<app-domain>/health
```

Expected response: `{"status": "healthy"}` with HTTP 200.

### 6. Check container logs if unhealthy

```bash
docker compose -p <app-name> -f deploy/docker-compose.yml logs --tail 50 app
```

## Full Rebuild

If a restart doesn't resolve the issue, rebuild the container:

```bash
cd /opt/apps/<app-name>
docker compose -p <app-name> -f deploy/docker-compose.yml up -d --build app
```

## Notes

- Restarting an app causes brief downtime (typically a few seconds). Caddy returns 502 during this window.
- Restarting does **not** affect other applications on the server.
- Platform services (PostgreSQL, Redis, etc.) are managed separately in `/opt/platform/`.

# Preview Environments

Preview environments allow developers to see changes **before merging into main**. Each pull request gets a temporary deployment with its own URL.

## How It Works

```
Pull Request opened/updated
       |
       v
GitHub Actions (preview.yml) triggered
       |
       v
Deploy preview container + DB schema
       |
       v
pr-42.preview.todo-app.anulectra.com
```

Each preview environment gets:

- Separate application container (project name `{APP_NAME}-pr-{N}`)
- Isolated database schema (`pr_{N}` in the app's existing database)
- Independent Caddyfile route
- Automatic PR comment with preview URL

## DNS Configuration

Each app needs a per-app wildcard DNS A record pointing preview subdomains to the platform server:

```
*.preview.todo-app.anulectra.com → 143.198.104.8  (TTL 3600)
*.preview.wit.anulectra.com      → 143.198.104.8  (TTL 3600)
```

This allows any preview subdomain to resolve automatically:

```
pr-1.preview.todo-app.anulectra.com
pr-42.preview.todo-app.anulectra.com
pr-5.preview.wit.anulectra.com
```

## GitHub Secrets

Apps need one additional secret beyond the standard 4:

| Secret | Example | Purpose |
|---|---|---|
| `PREVIEW_DOMAIN` | `anulectra.com` | Base domain for preview URLs |

The preview URL is constructed as `pr-{N}.preview.{APP_NAME}.{PREVIEW_DOMAIN}`.

## Deployment Workflow

The preview workflow (`.github/workflows/preview.yml`) triggers on pull request events:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, closed]
```

### Deploy (opened/synchronize/reopened)

1. SSH to server, clone repo to `/opt/apps/{APP_NAME}-pr-{N}` (or pull if it already exists)
2. Checkout the PR branch in the dedicated preview directory
3. Create PostgreSQL schema `pr_{N}` in the app's database
4. Copy production `.env` from `/opt/apps/{APP_NAME}/deploy/.env` and generate `.env.pr-{N}` with schema-aware `DATABASE_URL`
5. Build and start containers: `docker compose -p {APP_NAME}-pr-{N} -f deploy/docker-compose.yml up -d --build`
6. Run Alembic migrations against the preview schema
7. Write Caddyfile to `/opt/platform/caddy-apps/{APP_NAME}-pr-{N}.caddy`
8. Reload Caddy
9. Post/update PR comment with preview URL

### Cleanup (closed)

1. Stop and remove containers: `docker compose -p {APP_NAME}-pr-{N} down --rmi local`
2. Drop schema: `DROP SCHEMA IF EXISTS pr_{N} CASCADE`
3. Remove Caddyfile: `rm /opt/platform/caddy-apps/{APP_NAME}-pr-{N}.caddy`
4. Reload Caddy
5. Remove the preview directory: `rm -rf /opt/apps/{APP_NAME}-pr-{N}`

## Database Schema Isolation

Preview environments use PostgreSQL schemas rather than separate databases:

- **Production**: uses `{app}_db` database, default `public` schema
- **Preview PR 42**: uses `{app}_db` database, schema `pr_42`

The schema-aware `DATABASE_URL` uses the `options` parameter:

```
postgresql://postgres:<password>@postgres:5432/todo_app_db?options=-csearch_path%3Dpr_42
```

Alembic migrations run inside the preview container against the PR schema automatically.

## Container Naming

Preview containers use the Docker Compose project name `{APP_NAME}-pr-{N}`:

```
todo-app-pr-42-app-1
todo-app-pr-42-celery-worker-1
```

## Caddy Routing

Each preview gets a Caddyfile at `/opt/platform/caddy-apps/{APP_NAME}-pr-{N}.caddy`:

```
pr-42.preview.todo-app.anulectra.com {
    reverse_proxy todo-app-pr-42-app-1:8000
}
```

This uses the existing `import /opt/platform/caddy-apps/*.caddy` pattern — no platform Caddy config changes are needed.

## Concurrent Previews

Multiple PRs can be previewed simultaneously. Each gets its own:
- Container set (unique project name)
- Database schema (unique schema name)
- Caddy route (unique Caddyfile)

There is no limit beyond server resources.

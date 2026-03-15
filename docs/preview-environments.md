# Preview Environments

Preview environments allow developers to see changes **before merging into main**. Each pull request gets a temporary deployment with its own URL.

## How It Works

```
Pull Request opened
       │
       ▼
GitHub Actions triggered
       │
       ▼
Deploy temporary environment
       │
       ▼
pr-42.preview.example.com
```

Each preview environment gets:

- Separate application container
- Isolated database schema
- Independent configuration

## DNS Configuration

Add a wildcard DNS record pointing to your server:

```
*.preview.example.com → SERVER_IP
```

This allows any preview subdomain to resolve automatically:

```
pr-1.preview.example.com
pr-42.preview.example.com
pr-99.preview.example.com
```

## Deployment Workflow

The preview workflow triggers on pull request events:

```yaml
on:
  pull_request:
```

Deployment uses a separate Compose file:

```bash
docker compose -f docker-compose.preview.yml up -d
```

## Container Naming

Preview environments use unique names based on the PR number:

```
app-pr-42
db-pr-42
redis-pr-42
```

## Automatic Cleanup

When a PR is closed or merged, GitHub Actions automatically removes the preview environment:

```bash
docker compose -p pr-42 down
```

This removes all containers and networks associated with the preview.

## Environment Promotion

Preview environments fit into a broader promotion flow:

```
Pull Request → Preview environment
       │
       ▼
Merge to develop → Staging deployment
       │
       ▼
Merge to main → Production deployment
```

| Branch | Environment |
|---|---|
| PR branch | Preview |
| `develop` | Staging |
| `main` | Production |

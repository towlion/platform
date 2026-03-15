# Deploy Prompt Template

A reusable Claude Code session prompt for spinning up a new Towlion application deployment. Copy this prompt, replace the placeholders, and paste it into a Claude Code session.

## Placeholders

| Placeholder | Description | Example |
|---|---|---|
| `<app-name>` | Repository name for the new app | `todo-app` |
| `<your-domain.com>` | Domain or subdomain for the app | `todo.example.com` |
| `<server-ip>` | IP address of the target server | `203.0.113.42` |

## Prompt

```
I want to deploy a new Towlion app called <app-name> to <your-domain.com> on server <server-ip>.

Walk me through these 5 phases:

### Phase 1: Create repository
- Create a new repo from the towlion/app-template GitHub template
- Clone it locally
- Run setup-repo.sh to configure governance (branch protection, labels)

### Phase 2: Build the app
- Implement the application logic in app/main.py
- Add any new dependencies to requirements.txt (at repo root)
- Ensure the /health endpoint returns {"status": "ok"}
- Commit with conventional commit messages (feat:, fix:, etc.)

### Phase 3: Provision server
- SSH into the server and install Docker
- Create /data/{postgres,redis,minio,caddy} directories
- Set up DNS A record: <your-domain.com> -> <server-ip>
- Generate a deploy SSH key pair

### Phase 4: Deploy
- Configure GitHub Actions secrets (SERVER_HOST, SERVER_USER, SERVER_SSH_KEY, APP_DOMAIN, DATABASE_PASSWORD, MINIO_ROOT_USER, MINIO_ROOT_PASSWORD)
- Push to main to trigger the deploy workflow
- The workflow will: build containers, start services with docker-compose.standalone.yml, run migrations inside the container, then health check
- Verify with: curl https://<your-domain.com>/health

### Phase 5: Configure CI/CD
- Confirm the deploy.yml workflow runs on push to main
- Confirm the validate.yml workflow runs on PRs
- Test by pushing a small change and watching the Actions tab

Important notes:
- The app-template already includes all deployment fixes (correct migration ordering, __init__.py, PYTHONPATH, alembic -c flag)
- Standalone mode uses docker-compose.standalone.yml which includes postgres, redis, minio, and caddy
- Migrations run AFTER containers start: docker compose exec app alembic -c app/alembic.ini upgrade head
- requirements.txt must be at repo root (not app/) for the Dockerfile build context
```

## See also

- [Tutorial](tutorial.md) — step-by-step walkthrough with detailed commands
- [Deployment](deployment.md) — pipeline internals and zero-downtime strategy
- [Self-Hosting](self-hosting.md) — fork model and infrastructure overview

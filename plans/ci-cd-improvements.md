# CI/CD Improvements — Implementation Record

**Status**: Implemented (2026-03-16)

## Changes Made

### Phase A: Quick Wins
- **`.dockerignore`** created in app-template, todo-app, hello-world, wit — excludes `.git`, `.github`, `__pycache__`, `.env`, docs, etc. WIT version also excludes `frontend/node_modules` and `frontend/.next`
- **Pip caching** added to all deploy.yml files via `cache: 'pip'` on `actions/setup-python@v5`

### Phase B: Test Reliability
- **Tests made non-optional** — replaced `pytest || echo "skip"` with `pytest --collect-only` check; if tests exist they must pass, if none exist it skips gracefully
- **Legacy backport** — todo-app and hello-world deploy.yml now include per-app credentials block (matches app-template); validate.yml updated with `continue-on-error: true` on platform checkout

### Phase C: WIT Frontend CI
- **New `ci.yml`** in wit — runs backend pytest + frontend TypeScript type-check (`tsc --noEmit`) and build (`npm run build`) on all pushes/PRs

### Phase D: Build Performance
- **BuildKit cache mounts** added to all Python Dockerfiles (`# syntax=docker/dockerfile:1`, `--mount=type=cache,target=/root/.cache/pip`)
- WIT frontend Dockerfile also gets npm cache mount (`--mount=type=cache,target=/root/.npm`)

### Phase E: Deployment Notifications
- **GitHub Deployment API** integrated in app-template deploy.yml — creates deployment before SSH, updates status to success/failure after

### Phase F: Workflow Deduplication
- **Reusable `validate.yml`** created in `towlion/.github/.github/workflows/validate.yml` (workflow_call with tier input)
- **app-template** validate.yml simplified to 8-line caller using the reusable workflow
- **deploy.yml split** into `test` and `deploy` jobs in app-template (deploy `needs: test`)

## Files Changed

| Repo | File | Action |
|------|------|--------|
| app-template | `.dockerignore` | Created |
| app-template | `.github/workflows/deploy.yml` | Modified (cache, test fix, deployment API, job split) |
| app-template | `.github/workflows/validate.yml` | Modified (reusable workflow caller) |
| app-template | `app/Dockerfile` | Modified (BuildKit cache mount) |
| todo-app | `.dockerignore` | Created |
| todo-app | `.github/workflows/deploy.yml` | Modified (cache, test fix, per-app credentials) |
| todo-app | `.github/workflows/validate.yml` | Modified (continue-on-error) |
| todo-app | `app/Dockerfile` | Modified (BuildKit cache mount) |
| hello-world | `.dockerignore` | Created |
| hello-world | `.github/workflows/deploy.yml` | Modified (cache, test fix, per-app credentials) |
| hello-world | `.github/workflows/validate.yml` | Modified (continue-on-error) |
| hello-world | `app/Dockerfile` | Modified (BuildKit cache mount) |
| wit | `.dockerignore` | Created |
| wit | `.github/workflows/deploy.yml` | Modified (cache, test fix) |
| wit | `.github/workflows/ci.yml` | Created (frontend + backend CI) |
| wit | `app/Dockerfile` | Modified (BuildKit cache mount) |
| wit | `frontend/Dockerfile` | Modified (npm cache mount) |
| .github | `.github/workflows/validate.yml` | Created (reusable workflow) |

## Verification Checklist
- [ ] Push each repo, confirm GitHub Actions pass
- [ ] Check Actions logs for "Cache restored" on second run (pip cache)
- [ ] Add a failing test in any repo → confirm deploy is blocked
- [ ] Check todo-app/hello-world Actions for "Using per-app credentials" message
- [ ] Push TypeScript error in wit/frontend → confirm ci.yml fails
- [ ] SSH to server, run `docker compose build` twice → second build faster (BuildKit cache)
- [ ] Check app-template repo Environments tab for deployment history

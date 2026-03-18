# Runbook: Rotate SSH Keys

Rotate the SSH key pair used for deployments. Recommended schedule: every 90 days.

## Prerequisites

- Local machine with `ssh-keygen` and `ssh` installed
- Current SSH access to the server as `deploy` user
- `gh` CLI authenticated with access to all towlion app repos

## Steps

### 1. Generate a new key pair locally

```bash
ssh-keygen -t ed25519 -C "deploy@towlion-$(date +%Y%m%d)" -f ~/.ssh/towlion-deploy-new
```

### 2. Add the new public key to the server

```bash
ssh deploy@<SERVER_HOST> "cat >> ~/.ssh/authorized_keys" < ~/.ssh/towlion-deploy-new.pub
```

### 3. Test SSH access with the new key

```bash
ssh -i ~/.ssh/towlion-deploy-new deploy@<SERVER_HOST> "echo 'New key works'"
```

### 4. Update GitHub Actions secrets on all app repos

```bash
NEW_KEY=$(cat ~/.ssh/towlion-deploy-new)

for repo in towlion/todo-app towlion/wit; do
  gh secret set SERVER_SSH_KEY --repo "$repo" --body "$NEW_KEY"
  echo "Updated $repo"
done
```

### 5. Verify a deployment works

Trigger a deploy on one app (e.g., push a no-op commit) and confirm it succeeds.

### 6. Remove the old public key from the server

```bash
ssh -i ~/.ssh/towlion-deploy-new deploy@<SERVER_HOST>
# On the server:
# Edit ~/.ssh/authorized_keys and remove the old key line
# The old key has a different comment/date than the new one
```

### 7. Replace the local key file

```bash
mv ~/.ssh/towlion-deploy-new ~/.ssh/towlion-deploy
mv ~/.ssh/towlion-deploy-new.pub ~/.ssh/towlion-deploy.pub
```

## Rollback

If the new key doesn't work:
- The old key is still in `authorized_keys` until step 6
- SSH in with the old key and remove the new public key
- Re-set `SERVER_SSH_KEY` secrets to the old private key

## Verification

```bash
# Confirm only one key in authorized_keys
ssh deploy@<SERVER_HOST> "wc -l ~/.ssh/authorized_keys"
# Should output: 1

# Confirm deploy works
gh workflow run deploy.yml --repo towlion/todo-app
```

# Governance

This document is the single source of truth for repository policies across the Towlion organization.

## Org-Level Rulesets

Org-level rulesets are configured manually in the GitHub UI. They apply to all repositories in the organization.

### Ruleset: `towlion-main-protection`

**Target:** All repositories, default branch (`main`)

**Rules:**

- Require a pull request before merging (1 approval minimum)
- Require status checks to pass (`validate`)
- Block force pushes on `main`
- Block deletions of `main`

### How to Configure

1. Go to the [Towlion org settings](https://github.com/organizations/towlion/settings/rules/rulesets)
2. Navigate to **Settings > Rules > Rulesets**
3. Click **New ruleset > New branch ruleset**
4. Set the name to `towlion-main-protection`
5. Under **Target branches**, select **Default branch**
6. Enable **Restrict deletions**
7. Enable **Require a pull request before merging** — set minimum approvals to `1`
8. Enable **Require status checks to pass** — add `validate` as a required check
9. Enable **Block force pushes**
10. Set enforcement status to **Active**
11. Click **Create**

## Repository Settings

These settings are applied automatically by the [setup script](../scripts/setup-repo.sh).

| Setting | Value |
|---------|-------|
| Default branch | `main` |
| Wiki | Disabled |
| Projects | Disabled |
| Discussions | Disabled |
| Auto-delete head branches | Enabled |
| Allowed merge types | Squash merge only |

## Branch Protection

Branch protection rules complement the org-level rulesets and are applied by the setup script.

Rules applied to `main`:

- Require pull request reviews (1 reviewer minimum)
- Dismiss stale reviews when new commits are pushed
- Require the `validate` status check to pass
- Require the branch to be up to date before merging
- No force pushes
- No deletions

## CODEOWNERS

Every application repository must include a `.github/CODEOWNERS` file. At minimum:

```
* @towlion/maintainers
```

See the [template CODEOWNERS](../templates/.github/CODEOWNERS) for the canonical version.

## PR Template

Every application repository must include a `.github/PULL_REQUEST_TEMPLATE.md` with the following sections:

- **Summary** — What this PR does and why
- **Changes** — List of changes made
- **Testing** — How the changes were tested
- **Checklist** — Standard checklist items

See the [template PR template](../templates/.github/PULL_REQUEST_TEMPLATE.md) for the canonical version.

## Required Labels

All application repositories must have the following labels. The setup script creates these automatically from [`templates/.github/labels.json`](../templates/.github/labels.json).

| Label | Color | Description |
|-------|-------|-------------|
| `bug` | `#d73a4a` | Something isn't working |
| `feature` | `#a2eeef` | New feature or request |
| `docs` | `#0075ca` | Documentation improvements |
| `chore` | `#e4e669` | Maintenance and housekeeping |
| `breaking` | `#b60205` | Breaking change |
| `good first issue` | `#7057ff` | Good for newcomers |

## Commit Conventions

Towlion uses simplified [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
type: description
```

- Use **lowercase**
- Use **imperative mood** ("add feature" not "added feature")
- Keep the subject under **72 characters**

### Types

| Type | Purpose |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `chore` | Maintenance and housekeeping |
| `refactor` | Code restructuring (no behavior change) |
| `test` | Adding or updating tests |
| `ci` | CI/CD changes |

### Optional Scope

```
feat(api): add health endpoint
fix(auth): handle expired tokens
```

### Breaking Changes

Append `!` after the type:

```
feat!: change response format
```

### Examples

```
feat: add user registration endpoint
fix(db): prevent duplicate migration runs
docs: update self-hosting guide
chore: upgrade dependencies
ci: add preview environment workflow
```

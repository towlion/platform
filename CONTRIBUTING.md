# Contributing to Towlion Platform

Thanks for your interest in contributing! This project is a **documentation-only** repository — it contains the specification, architecture docs, and guides for the Towlion Platform, built with [MkDocs Material](https://squidfundamentals.github.io/mkdocs-material/).

## How to Contribute

### Reporting Bugs & Suggesting Features

- Open a [GitHub issue](https://github.com/towlion/platform/issues) describing the problem or idea.
- For bugs, include steps to reproduce and what you expected to happen.
- For feature requests, explain the use case and why it would be valuable.

### Submitting Changes

1. **Fork** the repository.
2. **Create a branch** from `main` with a descriptive name (e.g. `fix/typo-in-deployment`, `docs/add-monitoring-guide`).
3. **Make your changes** — see the documentation conventions below. Follow the [commit conventions](docs/governance.md#commit-conventions) for your commit messages.
4. **Open a pull request** against `main` with a clear description of what changed and why.

All towlion repositories follow standard [governance policies](docs/governance.md) including branch protection, PR templates, and commit conventions.

### Documentation Conventions

- All documentation lives in the `docs/` directory as Markdown files.
- Site configuration is in `mkdocs.yml`.
- Use standard Markdown with the extensions enabled in `mkdocs.yml` (admonitions, code highlighting, tabbed content, etc.).
- Keep language clear and concise. Prefer short paragraphs and bullet points.
- Use code fences with language tags for all code/config examples.

## Local Development Setup

You only need Python and MkDocs Material to preview the docs locally:

```bash
pip install mkdocs-material
mkdocs serve
```

Then open [http://127.0.0.1:8000](http://127.0.0.1:8000) in your browser. The site auto-reloads on file changes.

## Spec Validator

The platform includes a validator that checks app repositories against the [application specification](docs/spec.md). Run it against any app directory:

```bash
python validator/validate.py /path/to/your-app
```

The validator checks three tiers: file structure, configuration, and runtime compliance. All tiers should pass before deploying.

## Infrastructure Scripts

Scripts in the `infrastructure/` directory follow these conventions:

- **ShellCheck clean** — all scripts pass `shellcheck` with no warnings
- **Idempotent** — every section is guarded with existence checks; safe to re-run
- **No interactive prompts** in automated scripts (cron jobs, CI steps)
- **Documented** — see `docs/server-contract.md` for the full scripts reference table

When modifying infrastructure scripts, test on a fresh Debian 12 server or verify with `infrastructure/verify-server.sh`.

## Operational Tasks

For day-to-day server operations, see the [runbooks](docs/runbooks/):

- [Restart an app](docs/runbooks/restart-app.md)
- [Add a new app](docs/runbooks/add-new-app.md)
- [Rotate credentials](docs/runbooks/rotate-credentials.md)
- [Restore a backup](docs/runbooks/restore-backup.md)
- [Debug a failed deploy](docs/runbooks/debug-failed-deploy.md)

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating, you agree to uphold its standards.

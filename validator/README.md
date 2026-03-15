# Towlion Spec Validator

Validates that an application repository conforms to the [Towlion Platform Specification](../docs/spec.md) (Spec Version 1.0).

## Tiers

The validator runs checks in three tiers:

| Tier | Name | What it checks |
|------|------|----------------|
| 1 | Structure | Required files and directories exist |
| 2 | Content | File contents match spec requirements (default) |
| 3 | Runtime | Docker builds and health endpoint works (requires Docker) |

Each tier includes all checks from lower tiers.

## Local Usage

```bash
# Run from the platform repo against an app repo
python validator/validate.py --dir /path/to/your/app

# Structure checks only
python validator/validate.py --tier 1 --dir /path/to/your/app

# Full validation including runtime (requires Docker)
python validator/validate.py --tier 3 --dir /path/to/your/app

# Strict mode: treat warnings as errors
python validator/validate.py --strict --dir /path/to/your/app
```

## CI Usage (GitHub Actions)

Add this step to your app's workflow:

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: towlion/platform/.github/actions/validate@main
    with:
      tier: '2'
      strict: 'false'
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--tier` | `2` | Validation tier (1, 2, or 3) |
| `--strict` | off | Treat warnings as errors (exit code 1) |
| `--dir` | `.` | Path to the app repo to validate |

## Exit Codes

- `0` — All checks passed (warnings are allowed unless `--strict`)
- `1` — One or more checks failed

## Dependencies

- Python 3.11+ (standard library only)
- PyYAML is used for YAML validation if installed, but is not required
- Tier 3 requires Docker

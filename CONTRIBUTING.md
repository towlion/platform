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
3. **Make your changes** — see the documentation conventions below.
4. **Open a pull request** against `main` with a clear description of what changed and why.

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

## Code of Conduct

This project follows the [Contributor Covenant v2.1](CODE_OF_CONDUCT.md). By participating, you agree to uphold its standards.

---
disable-model-invocation: true
allowed-tools: Bash
argument-hint: "<repo-name>"
description: Run the governance setup script for a towlion repository
---

# /setup-repo — Configure Repository Governance

Run the governance setup script to configure repo settings, branch protection, and standard labels for a towlion repository.

## Instructions

1. `$ARGUMENTS` must contain the repository name (e.g., `app-template`, `uku-companion`)
2. If no argument is provided, tell the user they need to specify a repo name
3. Run: `bash scripts/setup-repo.sh $ARGUMENTS`
4. Show the output to the user

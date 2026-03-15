---
disable-model-invocation: true
allowed-tools: Bash, Read
argument-hint: "[path-to-app-repo]"
description: Run the Towlion spec validator against an application repository
---

# /validate — Run Spec Validator

Run the Towlion spec conformance validator against an app repo.

## Instructions

1. Determine the target directory:
   - If `$ARGUMENTS` is provided, use it as the path
   - Otherwise, default to the current working directory
2. Run: `python validator/validate.py --tier 2 --dir <target>`
   - The validator script is at `validator/validate.py` in the platform repo
   - Use tier 2 by default (structure + content checks)
   - If the user specifies `--tier 1` or `--tier 3` in arguments, respect that
3. Show the output to the user
4. If there are failures, summarize what needs to be fixed

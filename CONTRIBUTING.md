# Contributing to deploykit

deploykit is the Volunteer Center of Santa Cruz County's IT device-deployment kit.
It is **public and secret-free** — every sensitive value lives in a git-ignored
`config.env` that each operator supplies per deployment. Contributions must keep it that way.

## Golden rules

1. **No secrets, no internal hostnames — ever.** Tokens, keys, enrollment secrets, and real
   hostnames belong only in `config.env` (git-ignored). The repo ships `config.env.example`
   with **placeholders only**. CI (`secret-scan`) fails the build if this is violated.
2. **Every new setting** goes into `config.env.example` (placeholder) **and** the README.
3. **Cross-platform parity.** A behaviour change usually needs both the macOS (`macos/`,
   `onboarding/macos-onboard.sh`) and Windows (`windows/`, `onboarding/windows-onboard.ps1`)
   side — or the PR must say why not.
4. **Commits are signed** and authored as a real maintainer. No AI/bot attribution in commit
   messages, PR bodies, or reviews.

## Workflow

```bash
git switch -c my-change              # never commit to main directly
# … make changes …
cp config.env.example config.env     # local only; never committed
make lint                            # ShellCheck (see Makefile)
git commit -S -m "area: concise summary"
git push -u origin my-change
gh pr create                         # fill in the PR template
```

`main` is protected: changes land only through a pull request with **all CI checks green**,
**signed commits**, and a **linear history** (rebase, don't merge-commit).

## CI gates (all enforced on every PR)

| Check | What it verifies |
|---|---|
| `shellcheck` | Shell scripts are free of error-level issues |
| `powershell-lint` | `*.ps1` parse cleanly (PowerShell parser) + PSScriptAnalyzer (advisory) |
| `secret-scan` | `config.env` is not tracked; no internal hosts/known tokens in scripts |
| `shell-hygiene` | Every `*.sh` has a shebang; `set -u` recommended |
| `actionlint` | GitHub Actions workflows are valid |

## Style

- **Shell:** `#!/bin/bash` (or `/usr/bin/env bash`), `set -u` (prefer `set -euo pipefail`),
  quote expansions, prefer `[[ ]]`.
- **PowerShell:** `Set-StrictMode -Version Latest` where practical; approved verbs; no aliases in scripts.
- Keep functions small and named for what they do; match the surrounding file's conventions.

## Reporting problems

- **Bugs / feature requests:** open an issue (templates provided).
- **Security issues:** see [SECURITY.md](SECURITY.md) — do **not** open a public issue.

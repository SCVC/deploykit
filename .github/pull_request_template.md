## What & why

<!-- What does this change do, and why? Link the issue it closes: Closes #NN -->

## Type

- [ ] Feature (new capability)
- [ ] Fix (bug / regression)
- [ ] Docs / chore
- [ ] CI / automation

## Platforms touched

- [ ] macOS (`macos/`, `onboarding/macos-onboard.sh`)
- [ ] Windows (`windows/`, `onboarding/windows-onboard.ps1`)
- [ ] Cross-platform / shared

> A behaviour change should usually land on **both** macOS and Windows — or the PR should say why not.

## Checklist

- [ ] **No secrets or internal hostnames** added — real values live only in the git-ignored `config.env`
- [ ] Any new setting is added to **`config.env.example`** (placeholder) **and** documented in the README
- [ ] Shell scripts have a shebang and `set -u`; PowerShell uses `Set-StrictMode` where appropriate
- [ ] Tested on the target OS, or explicitly marked untested
- [ ] **`CHANGELOG.md`** updated under `## [Unreleased]`
- [ ] Commits are **signed** and authored as a real maintainer (no AI/bot attribution)

## CI gates (all must be green before merge)

`shellcheck` · `powershell-lint` · `secret-scan` · `shell-hygiene` · `actionlint`

# Changelog

All notable changes to deploykit are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims for [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Contribution governance:** PR template, `CONTRIBUTING.md`, `SECURITY.md`, `CODEOWNERS`,
  issue templates, and this changelog.
- **CI hardening:** new `shell-hygiene` (shebang + `set -u`) and `actionlint` (workflow lint)
  jobs; branch protection on `main` requiring green checks, signed commits, and linear history.
- `.editorconfig` for consistent charset, line endings, and trailing-whitespace handling.

### Changed
- Documented the professional PR workflow and CI gates in the README.

## Prior work

### Added
- **Self-heal / drift-reconcile** (`h` menu option) for already-installed agents —
  repoints Fleet / Wazuh / RustDesk back to `config.env` when they drift or go offline
  (macOS `setup.sh` and Windows `setup.ps1`).
- **PowerShell CI:** parse every `*.ps1` with the PowerShell parser + PSScriptAnalyzer.
- **Runtime installer fetch:** Chrome, RustDesk, Wazuh, and Fleet installers download at
  run time (Fleet via `FLEET_PKG_URL` / `FLEET_MSI_URL`, optionally behind Cloudflare Access).

### Security
- Public, secret-free repository: all sensitive values externalized to a git-ignored
  `config.env`; `secret-scan` CI gate blocks tracked `config.env` and internal hosts/tokens.

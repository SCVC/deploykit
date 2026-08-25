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
- **Wazuh port-check override:** a `--force` flag on `macos/wazuh-enroll.sh` and
  `windows/wazuh-enroll.ps1` to bypass the preflight connectivity check when needed.

### Changed
- Documented the professional PR workflow and CI gates in the README.
- **Wazuh enrollment preflight is now a hard failure** (was a warning): if the manager's
  raw TCP ports 1515/1514 are unreachable the script aborts with an actionable error
  explaining the Cloudflare-proxied-hostname pitfall (use a DNS-only name → manager public
  IP, or the LAN IP), overridable with `--force`. Removed misleading `siem.*` enroll-host
  examples. Applies to macOS and Windows.
- Documented Fleet package generation (`fleetctl`) and the `FLEET_PKG_URL` / `FLEET_MSI_URL`
  flow in the README.

### Fixed
- **Silent Wazuh enrollment failures** against Cloudflare-proxied (HTTPS-only) hostnames —
  the proxy does not forward 1514/1515, so agents silently failed to enroll. The new
  preflight prevents enrolling into a host that cannot carry those ports.

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

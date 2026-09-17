# Changelog

All notable changes to deploykit are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims for [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Fleet enroll scripts** (`macos/fleet-enroll.sh`, `windows/fleet-enroll.ps1`) —
  install fleetd from `FLEET_PKG_URL` / `FLEET_MSI_URL` (or a package staged in
  `installers/`), and **skip cleanly** with `fleetctl package` build-and-host
  guidance when neither is configured. `setup.sh` / `setup.ps1` now delegate to
  them instead of installing Fleet inline.
- **`--force` / `-Force`** on the Wazuh enrollment scripts, to enroll anyway when
  the 1515/1514 preflight check fails.
- README: how to build and host the org-specific Fleet package, and what
  `WAZUH_ENROLL_HOST` has to be able to reach.
- **Contribution governance:** PR template, `CONTRIBUTING.md`, `SECURITY.md`, `CODEOWNERS`,
  issue templates, and this changelog.
- **CI hardening:** new `shell-hygiene` (shebang + `set -u`) and `actionlint` (workflow lint)
  jobs; branch protection on `main` requiring green checks, signed commits, and linear history.
- `.editorconfig` for consistent charset, line endings, and trailing-whitespace handling.

### Changed
- Documented the professional PR workflow and CI gates in the README.

### Fixed
- **Wazuh enrollment no longer fails silently** against an HTTPS-only
  (e.g. Cloudflare-proxied) hostname: the 1515/1514 preflight now **aborts** with
  an actionable error — use a DNS-only record or the manager's LAN/VPN IP —
  instead of warning and enrolling blind (#16). The macOS check also falls back to
  bash `/dev/tcp` when `nc` is missing, rather than skipping.
- Dropped the misleading `siem.example.org` enrollment-host example that
  encouraged pointing enrollment at the dashboard hostname (#16).

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

# Changelog

All notable changes to deploykit are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims for [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Fleet Enrollment Scripts**: New scripts `macos/fleet-enroll.sh` and `windows/fleet-enroll.ps1` to handle Fleet agent installation and enrollment. The scripts gracefully skip enrollment if the required environment variables (`FLEET_PKG_URL`/`FLEET_MSI_URL` and `FLEET_ENROLL_SECRET`) are not set, providing clear instructions for generating and hosting the agent packages.
- **Wazuh Port Check Override**: Added a `--force` flag to the Wazuh enrollment scripts (`macos/wazuh-enroll.sh` and `windows/wazuh-enroll.ps1`) to bypass the initial port connectivity check.

### Changed
- **Wazuh Enrollment Preflight Check**: The port check in the Wazuh enrollment scripts is now a hard failure instead of a warning. If ports 1514 and 1515 are unreachable, the script will abort with a detailed error message explaining the common Cloudflare proxy pitfall and advising the use of a direct-access hostname or IP.
- **Improved Documentation**: Updated the `README.md` to include instructions for the new Fleet enrollment process and the `config.env.example` to reflect the necessary Fleet-related variables. Removed misleading `siem.example.org`-style hostnames from Wazuh enrollment examples.

### Fixed
- **Silent Wazuh Enrollment Failures**: Corrected an issue where the Wazuh enrollment scripts would silently fail if the enrollment host was a Cloudflare-proxied (HTTPS-only) hostname. The new preflight check prevents this by enforcing direct connectivity.


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

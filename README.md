# deploykit

[![CI](https://github.com/SCVC/deploykit/actions/workflows/ci.yml/badge.svg)](https://github.com/SCVC/deploykit/actions/workflows/ci.yml)

**Volunteer Center of Santa Cruz County — IT device deployment kit.**

Cross-platform scripts to onboard, offboard, secure, and back up staff machines
(macOS + Windows). One command sets up a new device: remote support, SIEM agent,
osquery fleet, managed browser, and the standard app suite.

> **No secrets in this repo.** Tokens, keys, and hostnames live in a git-ignored
> `config.env` you supply per deployment. See [`config.env.example`](config.env.example).

---

## Quick start

### macOS
```bash
brew install scvc/tap/deploykit        # (once the tap is published)
# — or, no Homebrew:
curl -fsSL https://raw.githubusercontent.com/SCVC/deploykit/main/install.sh | bash
```

### Windows 11 (PowerShell as Administrator)
```powershell
irm https://raw.githubusercontent.com/SCVC/deploykit/main/install.ps1 | iex
```

The installer pulls the repo, helps you create `config.env`, then runs the setup
for your OS.

---

## What it does

| Area | macOS | Windows |
|---|---|---|
| Onboard a new machine (apps + prefs) | `onboarding/macos-onboard.sh` | `onboarding/windows-onboard.ps1` |
| Full setup (remote/SIEM/fleet/browser) | `macos/setup.sh` | `windows/setup.ps1` |
| Wazuh SIEM enrollment | `macos/wazuh-enroll.sh` | `windows/wazuh-enroll.ps1` |
| Backup / cleanup helpers | `scripts/*.sh` | — |

Integrates with **RustDesk** (remote support), **Wazuh** (SIEM), **FleetDM/osquery**,
and **Chrome Browser Cloud Management**.

## Healing drift

If a machine already has these agents but they've **drifted** — pointing at an old/dead
URL or gone offline — run `macos/setup.sh` and pick **`h`**. It reconciles **Fleet, Wazuh,
and RustDesk** against `config.env`: repoints + restarts whatever's stale (e.g. an agent
still aimed at a retired domain), and leaves alone whatever's already correct or not
installed. (Windows parity is next.)

## Configuration

```bash
cp config.env.example config.env     # then fill in your org's real values
```
`config.env` is git-ignored and never committed. Each setup script reads it from
the repo root (or beside the script). The Wazuh enrollment password is prompted
securely at runtime, never stored.

## Repository layout

```
deploykit/
├── install.sh / install.ps1   # bootstrap (curl|bash / irm|iex)
├── config.env.example          # copy → config.env (git-ignored)
├── macos/      windows/        # per-OS setup + Wazuh enrollment
├── onboarding/                 # new-machine app + preference bootstrap
├── scripts/                    # backup / cleanup / checklist helpers
├── docs/                       # implementation notes
└── .github/workflows/ci.yml    # shellcheck + secret-scan guard
```

## Vendor installers

Large installers (Chrome, Wazuh, Fleet, RustDesk) are **not** committed. Chrome is
downloaded from Google at runtime; org-specific agents (Fleet/Wazuh/RustDesk builds
with enrollment baked in) are provided via GitHub Releases or an internal share —
see [ROADMAP](#roadmap).

## Contributing

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full workflow, and **[SECURITY.md](SECURITY.md)**
to report vulnerabilities privately. In short:

- `main` is **protected** — changes land only via a pull request with **all CI checks green**,
  **signed commits**, and **linear history**. `make lint` runs ShellCheck locally.
- Every PR runs five gates: **`shellcheck` · `powershell-lint` · `secret-scan` · `shell-hygiene` · `actionlint`**.
- Keep `config.env.example` **placeholder-only**; document new settings there and in this README.
- Record user-facing changes in **[CHANGELOG.md](CHANGELOG.md)** under `Unreleased`.

## Roadmap

### Apps & deployment
- [ ] **Konica Minolta C258** drivers/profiles — HWCC
- [ ] **Konica Minolta C308** drivers/profiles — VCHQ (17th Ave)
- [ ] **Konica Minolta C458** drivers/profiles — MWC (Watsonville)
- [ ] **RustDesk** — unattended install + VC config (static password set at runtime)
- [ ] **RustDesk** — post-install script to pull hostname + IP and report to inventory
- [ ] **Microsoft Office** — macOS (suite `.pkg` + Volume License **Serializer** for perpetual) &
  Windows (**Office Deployment Tool** + `configuration.xml`, installed under `C:\Program Files\Microsoft Office`)
- [ ] **Zoom** — macOS
- [ ] Homebrew tap (`scvc/tap/deploykit`)
- [ ] `install.ps1` Windows bootstrap

### Maintenance & lifecycle
- [ ] **OS & software updates** — macOS (`softwareupdate`) & Windows (Windows Update / `winget upgrade`)
- [ ] Offboarding automation (account deprovision runbook + scripts)

### Done
- [x] Runtime installer fetch — macOS (Chrome/RustDesk/Wazuh auto; Fleet via `FLEET_PKG_URL`)
- [x] Windows Fleet install uses `FLEET_MSI_URL` — parity with macOS
- [x] Self-heal / drift-reconcile (Fleet/Wazuh/RustDesk) — macOS + Windows
- [x] CI hardening + contribution governance (branch protection, PR template, CONTRIBUTING/SECURITY)

## License

MIT — see [LICENSE](LICENSE).

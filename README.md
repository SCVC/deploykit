# deploykit

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

`make lint` runs ShellCheck. CI blocks any commit that reintroduces a secret or
internal hostname. Keep `config.env.example` placeholder-only.

## Roadmap

- [ ] Homebrew tap (`scvc/tap/deploykit`)
- [ ] `install.ps1` Windows bootstrap
- [ ] Runtime installer fetch (Releases) so no binaries are ever bundled
- [ ] Offboarding automation (account deprovision runbook + scripts)

## License

MIT — see [LICENSE](LICENSE).

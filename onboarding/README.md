# VCSC Machine Onboarding Automation

Centralized scripts to bootstrap new Windows 11 and macOS machines with required software and configurations.

## Quick Start

### Windows 11
1. Open PowerShell as Administrator.
2. Run:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   .\windows-onboard.ps1
   ```

### macOS
1. Open Terminal.
2. Run:
   ```bash
   chmod +x macos-onboard.sh
   ./macos-onboard.sh
   ```

## What it installs

**Common Software:**
- Google Chrome
- Visual Studio Code
- Microsoft 365 (Office)
- Slack
- 1Password (or Bitwarden)
- Zoom

**Configurations:**
- Disables some telemetry (Windows)
- Sets common preferences (macOS Dock, etc.)

## Customization

Edit the variables at the top of each script to add/remove software.

### Windows (Winget IDs)
Find IDs with: `winget search <app_name>`

### macOS (Homebrew Casks)
Find casks with: `brew search <app_name>`

## Office Deployment (Windows)

The script uses `office-deployment-config.xml` to install Office 365.
- Edit the XML to change edition (ProPlus, Business) or exclusion of apps (OneNote, Publisher, etc.).
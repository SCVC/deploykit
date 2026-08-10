# Onboarding System Documentation

## Created Files

1. **windows-onboard.ps1** — PowerShell script for Windows 11
2. **macos-onboard.sh** — Bash script for macOS
3. **office-deployment-config.xml** — Office 365 deployment configuration
4. **README.md** — Quick start guide

## Next Steps

1. **Test on a non-production machine** (either OS)
2. **Customize software lists** in each script's variables section
3. **Set up central repository** — either:
   - GitHub/GitLab repo for cloning
   - Network share at VCSC (e.g., \\SRV\onboarding\)

## Office Deployment (Windows)

For proper Office 365 installation:
1. Download [Office Deployment Tool](https://www.microsoft.com/en-us/download/details.aspx?id=49117)
2. Extract `setup.exe` into the onboarding folder
3. Set `$useOfficeODT = $true` in windows-onboard.ps1
4. Edit `office-deployment-config.xml` to match your licensing (ProPlus, Business, etc.)

## Execution

**Windows:** Right-click `windows-onboard.ps1` → Run with PowerShell (Admin)

**macOS:** `chmod +x macos-onboard.sh && ./macos-onboard.sh`

## Scaling Options

- **Git repo + curl**: `curl -sSL https://your-repo.com/windows-onboard.ps1 | powershell`
- **USB drive**: Copy entire folder to USB, run from drive
- **Network share**: Map \\server\share and run scripts directly

## Notes

- Both scripts are idempotent — safe to re-run
- Winget/Brew will skip already-installed apps
- Review XML Office config for your specific licensing needs
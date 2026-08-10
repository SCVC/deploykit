# VCSC Windows 11 Onboarding Script
# Run as Administrator

# Check for Admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You usually do not have Administrator rights. Please re-run as Administrator."
    # Note: Winget can install some apps as user, but system configs need admin.
}

# Configuration
$softwareList = @(
    "Google.Chrome",
    "Microsoft.VisualStudioCode",
    "Microsoft.Teams",
    "Slack.Slack",
    "Zoom.Zoom",
    "Bitwarden.Bitwarden",
    "7zip.7zip",
    "Notepad++.Notepad++",
    "Git.Git"
)

# Office Configuration (Optional - requires setup files)
$useOfficeODT = $false # Set to $true if you deploy ODT XML
$odtPath = ".\office-deployment-config.xml"

Write-Host "Starting VCSC Windows Onboarding..." -ForegroundColor Cyan

# 1. Update Winget (Implicitly happens on first use)
Write-Host "Checking Winget availability..." -ForegroundColor Yellow
try {
    winget --version
} catch {
    Write-Host "Winget not found. Please install App Installer from Microsoft Store." -ForegroundColor Red
    exit
}

# 2. Install Software via Winget
Write-Host "Installing software via Winget..." -ForegroundColor Yellow
foreach ($app in $softwareList) {
    Write-Host "Installing $app..." -ForegroundColor Gray
    winget install --id $app --accept-package-agreements --accept-source-agreements -e
}

# 3. Configure Office 365 (Using ODT if enabled)
if ($useOfficeODT -and (Test-Path $odtPath)) {
    Write-Host "Installing Microsoft 365 via ODT..." -ForegroundColor Yellow
    # Assumes setup.exe is in the same directory (download from Microsoft)
    # https://www.microsoft.com/en-us/download/details.aspx?id=49117
    if (Test-Path ".\setup.exe") {
        .\setup.exe /configure $odtPath
    } else {
        Write-Host "setup.exe not found. Skipping Office installation." -ForegroundColor Red
    }
} else {
    Write-Host "Trying to install Microsoft 365 via Winget (Fallback)..." -ForegroundColor Yellow
    # Note: Click-to-Run via Winget often requires license activation later
    winget install --id "Microsoft.Office" --accept-package-agreements --accept-source-agreements -e
}

# 4. Windows Configuration
Write-Host "Applying system configurations..." -ForegroundColor Yellow

# Example: Disable Consumer Experience (Start Menu suggestions)
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord

# Example: Show File Extensions
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

Write-Host "Onboarding complete. Please reboot if Office was installed." -ForegroundColor Green
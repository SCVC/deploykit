# ============================================================
# fleet-enroll.ps1 --- FleetDM (fleetd/orbit) install + enrollment, Windows
#
# Fleet's agent is org-specific: the Fleet URL and enroll secret are baked
# into a package you build yourself with fleetctl and host where machines can
# reach it. There is no generic installer to download, so when no package is
# configured this script SKIPS with build-and-host guidance instead of failing.
#
# Run from an ELEVATED PowerShell (Run as administrator):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\fleet-enroll.ps1                 # uses config.env / installers\
#   .\fleet-enroll.ps1 -MsiUrl <url>   # explicit package URL
# ============================================================

param(
    [string]$MsiUrl = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installers = Join-Path $ScriptDir "installers"
$FleetMsi   = "fleet-osquery.msi"
$SvcName    = "Fleet osquery"

function Log($msg, $color = "Gray") {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) -ForegroundColor $color
}
function Ok($msg)   { Log "[ OK ] $msg" "Green" }
function Warn($msg) { Log "[WARN] $msg" "Yellow" }
function Fail($msg) { Log "[FAIL] $msg" "Red" }

# ---------- preflight ----------------------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please re-run from an elevated PowerShell (Run as administrator)." -ForegroundColor Red
    exit 1
}

# Load config.env only when the caller hasn't already supplied the settings.
if (-not $MsiUrl -and -not $FLEET_MSI_URL -and -not $FLEET_URL) {
    $cfg = @((Join-Path $ScriptDir "config.env"), (Join-Path $ScriptDir "..\config.env")) |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($cfg) {
        Get-Content $cfg | ForEach-Object {
            if ($_ -match '^\s*([A-Z_]+)\s*=\s*"?([^"#]*)"?') {
                Set-Variable -Name $Matches[1] -Value $Matches[2].Trim() -Scope Script
            }
        }
    }
}
if ($MsiUrl) { $FLEET_MSI_URL = $MsiUrl }

# ---------- skip path ----------------------------------------

function Skip-WithGuidance {
    $url = if ($FLEET_URL) { $FLEET_URL } else { "https://fleet.example.com" }
    Write-Host ""
    Write-Host "[SKIP] Fleet is not configured on this kit - fleetd was not installed." -ForegroundColor Yellow
    Write-Host @"

  Fleet's agent is built per organization: the Fleet URL and enroll secret are
  compiled into the package, so there is no generic installer to fetch.

  To enable it:

    1. Install fleetctl and log in to your Fleet server:
         npm install -g fleetctl
         fleetctl login

    2. Build the Windows package with your enroll secret:
         fleetctl package --type=msi --fleet-desktop ``
           --fleet-url=$url ``
           --enroll-secret=<your-enroll-secret>

    3. Host the resulting .msi where machines can fetch it (GitHub Release,
       internal share, object storage - optionally behind Cloudflare Access)
       and set it in config.env:
         FLEET_MSI_URL="https://.../$FleetMsi"

       ...or copy the package to installers\$FleetMsi on the kit itself.

  Nothing on this machine was changed.

"@
    exit 0
}

# ---------- fetch the package ---------------------------------

function Get-FleetPackage {
    $cached = Join-Path $Installers $FleetMsi
    if (Test-Path $cached) { Log "Using installers\$FleetMsi"; return $cached }
    if (-not $FLEET_MSI_URL) { Skip-WithGuidance }

    $dest = $cached
    try {
        New-Item -ItemType Directory -Force -Path $Installers -ErrorAction Stop | Out-Null
    } catch {
        $dest = Join-Path $env:TEMP $FleetMsi
    }

    Log "Downloading $FleetMsi ..."
    Log "  $FLEET_MSI_URL"
    $part = "$dest.part"
    try {
        $ProgressPreference = 'SilentlyContinue'
        # Cloudflare Access service-token headers ONLY for the Access-protected host
        $hdrs = @{}
        if ($CF_ACCESS_CLIENT_ID -and $CF_ACCESS_HOST -and ($FLEET_MSI_URL -like "*$CF_ACCESS_HOST*")) {
            $hdrs['CF-Access-Client-Id']     = $CF_ACCESS_CLIENT_ID
            $hdrs['CF-Access-Client-Secret'] = $CF_ACCESS_CLIENT_SECRET
        }
        Invoke-WebRequest -Uri $FLEET_MSI_URL -OutFile $part -Headers $hdrs -UseBasicParsing -ErrorAction Stop
        Move-Item $part $dest -Force
        $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Ok "Downloaded $FleetMsi ($mb MB)"
        return $dest
    } catch {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        Fail "Download failed: $FleetMsi from $FLEET_MSI_URL"
        return $null
    }
}

# ---------- install + verify ----------------------------------

$msi = Get-FleetPackage
if (-not $msi) { exit 1 }

Log "Installing fleetd (this also enrolls the host)..."
$p = Start-Process msiexec.exe -ArgumentList "/i", "`"$msi`"", "/qn" -Wait -PassThru
if ($p.ExitCode -ne 0) { Fail "Fleet MSI failed (exit $($p.ExitCode))."; exit 1 }
Start-Sleep -Seconds 5

$svc = Get-Service $SvcName -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    Fail "'$SvcName' service is not running after install."
    exit 1
}
Ok "fleetd installed and running (enroll secret baked into the MSI)."

# Restart the service so it re-reads its config and re-enrolls
Log "Restarting '$SvcName' to pick up the new enrollment..."
Restart-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$svc = Get-Service $SvcName -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    Fail "'$SvcName' failed to restart after enrollment."
    exit 1
}
Ok "'$SvcName' service is running."

Log "Relaunching Fleet Desktop..."
Start-Process -FilePath "$env:ProgramFiles\Orbit\bin\desktop\fleet-desktop.exe" -ErrorAction SilentlyContinue

$where = if ($FLEET_URL) { $FLEET_URL } else { "your Fleet server" }
Log "MANUAL CHECK: confirm this host appears at $where" "Cyan"
exit 0

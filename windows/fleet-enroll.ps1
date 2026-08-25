# fleet-enroll.ps1 --- Fleetd enrollment for Windows

param(
    [string]$FleetMsiUrl = $env:FLEET_MSI_URL,
    [string]$FleetEnrollSecret = $env:FLEET_ENROLL_SECRET
)

$ErrorActionPreference = "Stop"

function Log($msg, $color = "Gray") {
    Write-Host "[$(Get-Date -Format "HH:mm:ss")] $msg" -ForegroundColor $color
}
function Ok($msg)   { Log "[ OK ] $msg" "Green" }
function Warn($msg) { Log "[WARN] $msg" "Yellow" }
function Fail($msg) { Log "[FAIL] $msg" "Red" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Fail "Please re-run from an elevated PowerShell (Run as administrator)."
    exit 1
}

if (-not $FleetMsiUrl -or -not $FleetEnrollSecret) {
    Log "FLEET_MSI_URL or FLEET_ENROLL_SECRET not set. Skipping Fleet enrollment." "Yellow"
    Write-Host ""
    Write-Host "To enroll in Fleet, you must first build and host the agent package." -ForegroundColor Yellow
    Write-Host "1. Use fleetctl to create the package:" -ForegroundColor Gray
    Write-Host "   fleetctl package --type=msi --fleet-url=<your-fleet-url> --enroll-secret=<your-enroll-secret>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Host the resulting .msi file on a web server." -ForegroundColor Gray
    Write-Host "3. Set the following environment variables:" -ForegroundColor Gray
    Write-Host "   \$env:FLEET_MSI_URL = 'https://your.server/path/to/fleet-osquery.msi'" -ForegroundColor Gray
    Write-Host "   \$env:FLEET_ENROLL_SECRET = '<your-enroll-secret>'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Then, re-run this script." -ForegroundColor Yellow
    exit 0
}

Log "Downloading Fleet agent package..."
$msiPath = Join-Path $env:TEMP "fleet-osquery.msi"
Invoke-WebRequest -Uri $FleetMsiUrl -OutFile $msiPath -UseBasicParsing

Log "Installing Fleet agent..."
$installArgs = @(
    "/i", "`"$msiPath`"", "/q",
    "ENROLL_SECRET=`"$FleetEnrollSecret`""
)
$proc = Start-Process msiexec.exe -ArgumentList $installArgs -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Fail "msiexec exited with code $($proc.ExitCode) --- install failed."
    exit 1
}

Ok "Fleet agent installed and enrolled."

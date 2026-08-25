# ============================================================
# wazuh-enroll.ps1 --- Wazuh agent install + enrollment (Windows)
#
# Run from an ELEVATED PowerShell (Run as administrator):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\wazuh-enroll.ps1
#
# Prompts for the agent name (e.g. VC031); everything else is
# pre-filled below. Uses installers\wazuh-agent-<ver>.msi from
# the USB if present, otherwise downloads it from wazuh.com.
# ============================================================

param(
    [string]$Manager   = "wazuh.example.com",
    [string]$AgentName = "",
    [string]$Password  = "",
    [string]$Version   = "4.14.3-1",
    [switch]$Force     = $false
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$OssecDir   = "C:\Program Files (x86)\ossec-agent"
$LogDir     = Join-Path $ScriptDir "logs"
$LogFile    = Join-Path $LogDir ("{0}-wazuh-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))

function Log($msg, $color = "Gray") {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $LogFile -Value $line } catch {}
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

try { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null } catch {
    $LogDir  = "C:\ProgramData\staff-setup\logs"
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $LogFile = Join-Path $LogDir ("{0}-wazuh-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))
}

Log "=== Wazuh enrollment on $env:COMPUTERNAME ===" "Cyan"

# ---------- current state ------------------------------------

$svc = Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue
$keys = Join-Path $OssecDir "client.keys"
if ($svc) {
    $enrolledAs = ""
    if ((Test-Path $keys) -and (Get-Item $keys).Length -gt 0) {
        $enrolledAs = ((Get-Content $keys -First 1) -split " ")[1]
    }
    Warn "Wazuh agent already installed (service: $($svc.Status); enrolled as: '$enrolledAs')."
    $ans = Read-Host "Reinstall + re-enroll anyway? [y/N]"
    if ($ans -notmatch '^[Yy]$') { Log "Nothing to do --- exiting."; exit 0 }
    Stop-Service WazuhSvc -ErrorAction SilentlyContinue
}

# ---------- agent name ----------------------------------------

while (-not $AgentName) {
    Write-Host ""
    Write-Host "Agent name for this machine (e.g. VC031)" -ForegroundColor Cyan
    Write-Host "  (this Windows PC calls itself '$env:COMPUTERNAME' --- enter OUR name for it)"
    $AgentName = (Read-Host "Agent name").Trim()
    if (-not $AgentName) { Write-Host "An agent name is required." -ForegroundColor Yellow; continue }

    $confirm = Read-Host "Enroll this machine as '$AgentName'? [Y/n]"
    if ($confirm -match '^[Nn]') { $AgentName = "" }
}
# ---------- enrollment password --------------------------------
while (-not $Password) {
    $sec = Read-Host "Wazuh enrollment password" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if (-not $Password) { Write-Host "Password cannot be empty." -ForegroundColor Yellow }
}

Log "Manager: $Manager   Agent name: $AgentName" "Cyan"

# ---------- connectivity check --------------------------------

Log "Checking connectivity to $Manager on ports 1514/1515..."
$portsReachable = 0
foreach ($port in 1515, 1514) {
    $conn = Test-NetConnection -ComputerName $Manager -Port $port -WarningAction SilentlyContinue -InformationLevel Quiet
    if ($conn.TcpTestSucceeded) {
        Ok "${Manager}:${port} --- reachable"
        $portsReachable++
    } else {
        Warn "${Manager}:${port} --- unreachable"
    }
}

if ($portsReachable -eq 0) {
    if ($Force) {
        Warn "Both ports are unreachable, but -Force was provided. Continuing."
    } else {
        Fail "Both agent ports (1515/tcp, 1514/tcp) are unreachable."
        Write-Host ""
        Write-Host "  This is often caused by one of the following:" -ForegroundColor Yellow
        Write-Host "    1. A firewall on this machine, the network, or the server is blocking connections on these ports." -ForegroundColor Yellow
        Write-Host "    2. The manager hostname points to a Cloudflare (or other) proxy that only tunnels HTTP/S traffic." -ForegroundColor Yellow
        Write-Host "       The Wazuh agent requires a direct connection to its manager on these TCP ports." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Action:" -ForegroundColor Green
        Write-Host "    - For cloud-hosted managers, ensure the hostname you are using is a DNS-only (grey-cloud)" -ForegroundColor Green
        Write-Host "      record that resolves directly to the manager's public IP." -ForegroundColor Green
        Write-Host "    - For on-premise managers, use the manager's LAN IP address." -ForegroundColor Green
        Write-Host "    - If you are certain the host is reachable and this check is a false negative, re-run with the '-Force' switch." -ForegroundColor Green
        Write-Host ""
        exit 1
    }
}

# ---------- get the MSI ----------------------------------------

$msiName  = "wazuh-agent-$Version.msi"
$localMsi = Join-Path $ScriptDir "installers\$msiName"
if (Test-Path $localMsi) {
    $msi = $localMsi
    Log "Using MSI from USB: $msiName"
} else {
    $msi = Join-Path $env:TEMP $msiName
    $url = "https://packages.wazuh.com/4.x/windows/$msiName"
    Log "Downloading $url ..."
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
    Ok "Downloaded MSI."
}

# ---------- install + enroll -----------------------------------

Log "Installing (this also enrolls using the registration password)..."
$args = @(
    "/i", "`"$msi`"", "/q",
    "WAZUH_MANAGER=`"$Manager`"",
    "WAZUH_REGISTRATION_SERVER=`"$Manager`"",
    "WAZUH_REGISTRATION_PASSWORD=`"$Password`"",
    "WAZUH_AGENT_NAME=`"$AgentName`""
)
$p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -ne 0) {
    Fail "msiexec exited with code $($p.ExitCode) --- install failed."
    exit 1
}
Ok "MSI installed."

# ---------- start + verify -------------------------------------

Start-Service WazuhSvc
Start-Sleep -Seconds 6

$svc = Get-Service WazuhSvc
if ($svc.Status -eq "Running") { Ok "WazuhSvc service is running." }
else { Fail "Service is $($svc.Status) --- check $OssecDir\ossec.log"; exit 1 }

if ((Test-Path $keys) -and (Get-Item $keys).Length -gt 0) {
    $entry = Get-Content $keys -First 1
    Ok "Enrolled: $entry"
} else {
    Fail "client.keys is empty --- enrollment failed."
    Warn "Common causes: wrong password, duplicate agent name, port 1515 blocked."
    Warn "See: $OssecDir\ossec.log"
    exit 1
}

# connection state (may take a few more seconds to flip to connected)
$stateFile = Join-Path $OssecDir "wazuh-agent.state"
Start-Sleep -Seconds 5
$state = (Select-String -Path $stateFile -Pattern "^status=" -ErrorAction SilentlyContinue).Line
if ($state -match "connected") {
    Ok "Agent status: connected to manager."
} else {
    Warn "Agent state: $state (give it a minute, then check the Wazuh dashboard)"
}

Log "=== Done. Verify '$AgentName' shows Active in the Wazuh dashboard. ===" "Cyan"
Log "Log saved to: $LogFile"

# ============================================================
# wazuh-enroll.ps1 --- Wazuh agent install + enrollment (Windows)
#
# Run from an ELEVATED PowerShell (Run as administrator):
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\wazuh-enroll.ps1
#
# -Manager must reach the manager on raw TCP 1515/1514 (a DNS-only record or
# an IP) --- not the HTTPS-only dashboard hostname. Use -Force to enroll even
# when that preflight check fails.
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
    [switch]$Force
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

# ---------- connectivity check (hard gate) --------------------
#
# Registration (1515) and agent comms (1514) are RAW TCP, not HTTP: an
# HTTPS-only reverse proxy or CDN in front of the manager forwards 443 and
# silently drops both, so the MSI installs and the agent never enrolls.

$unreachable = @()
foreach ($port in 1515, 1514) {
    $t = Test-NetConnection -ComputerName $Manager -Port $port -WarningAction SilentlyContinue
    if ($t.TcpTestSucceeded) { Ok "${Manager}:${port} --- reachable" }
    else { Fail "${Manager}:${port} --- unreachable"; $unreachable += $port }
}

if ($unreachable.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Enrollment host is not usable ===" -ForegroundColor Yellow
    Write-Host @"

  Wazuh registration (1515/tcp) and agent comms (1514/tcp) are raw TCP. They
  are not HTTP and cannot pass through an HTTPS-only reverse proxy or CDN.

  If '$Manager' is the Wazuh *dashboard* hostname behind a proxy (e.g. a
  Cloudflare orange-cloud record), only 443 is forwarded: the name resolves,
  the dashboard loads, and enrollment still fails --- silently.

  Use instead:
    - a DNS-only (grey-cloud) record pointing at the manager's IP, or
    - the manager's LAN / VPN IP address.

  If the manager is only published on the internal network, connect to the VPN
  first and re-run --- an agent enrolled over the VPN also needs it up to stay
  'Active', or the dashboard will show it disconnected once the tunnel drops.

  Then confirm 1515/tcp and 1514/tcp are open end to end (host firewall,
  security group, NAT/port-forward).

"@
    if ($Force) {
        Warn "-Force given --- continuing despite unreachable port(s): $($unreachable -join ', ')"
    } else {
        Fail "Manager $Manager unreachable on $($unreachable -join '/'). Fix the host, or re-run with -Force to enroll anyway."
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

    # authd closes the socket on a rejected registration, so the useful detail is
    # in the agent's own log rather than the MSI exit code.
    $log    = Join-Path $OssecDir "ossec.log"
    $recent = ""
    if (Test-Path $log) { $recent = (Get-Content $log -Tail 80 -ErrorAction SilentlyContinue) -join "`n" }

    if ($recent -match '(?i)connection reset by peer|duplicate agent|already present') {
        Write-Host ""
        Write-Host "The manager accepted the connection and then closed it." -ForegroundColor Yellow
        Write-Host @"

  authd refused the registration but does not say why on this side. The reason
  is one line in the manager's own log, so read that first:

    grep -i authd /var/ossec/logs/ossec.log        # on the manager

  The two usual verdicts:

  1. 'Invalid password provided by <ip>. Closing connection.'
     The manager requires an enrollment password; re-run with the right one
     (it must match /var/ossec/etc/authd.pass on the manager).

  2. A duplicate/stale record --- a machine enrolled earlier (often against a
     previous manager hostname) still holds this name or IP:

       /var/ossec/bin/manage_agents -l             # list agents, find the stale entry
       /var/ossec/bin/manage_agents -r <agent-id>  # remove it

     (Dashboard -> Agents -> select -> Delete does the same, but the account
     needs the 'agent:delete' permission.)

     Then re-run, or enroll under a different name to keep the old record:
       .\wazuh-enroll.ps1 -AgentName <new-name>

"@
    } elseif ($recent -match '(?i)invalid password|unable to verify') {
        Write-Host ""
        Write-Host "Most likely: wrong or missing enrollment password." -ForegroundColor Yellow
        Write-Host "  authd compares what this agent sent against /var/ossec/etc/authd.pass on the manager."
        Write-Host ""
    } else {
        Warn "Common causes: wrong password, duplicate agent name, 1515/tcp blocked,"
        Warn "or the manager being reachable only over the VPN (connect, then re-run)."
    }
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
    Warn "If the manager is internal-only, the agent reports disconnected whenever the VPN is down."
}

Log "=== Done. Verify '$AgentName' shows Active in the Wazuh dashboard. ===" "Cyan"
Log "Log saved to: $LogFile"

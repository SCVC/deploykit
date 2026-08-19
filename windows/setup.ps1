# ============================================================
# Staff Windows setup - RustDesk / Wazuh / FleetDM / Chrome CBCM
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup.ps1
#
# ============================================================

# ---------- org settings - loaded from config.env (NEVER hardcode secrets) ----
# config.env is git-ignored and supplied per deployment. Copy config.env.example to config.env.
$SD = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = @((Join-Path $SD "config.env"),(Join-Path $SD "..\config.env")) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ConfigFile) { Write-Host "config.env not found - copy config.env.example to config.env and fill in your org values." -ForegroundColor Red; exit 1 }
Get-Content $ConfigFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*"?([^"#]*)"?') { Set-Variable -Name $Matches[1] -Value $Matches[2].Trim() -Scope Script }
}
$RUSTDESK_RELAY = $RUSTDESK_HOST

# Installer filenames
$RUSTDESK_EXE = "rustdesk-x86_64.exe"
$FLEET_MSI    = "fleet-osquery.msi"
$CHROME_MSI   = "googlechrome64.msi"
$CHROME_URL   = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"

# ---------- paths / logging ------------------------------------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installers = Join-Path $ScriptDir "installers"
$DataDir    = $ScriptDir
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "logs") | Out-Null
    $testFile = Join-Path $DataDir ".write-test"
    New-Item -ItemType File -Force -Path $testFile | Out-Null
    Remove-Item $testFile -Force
} catch {
    $DataDir = "C:\ProgramData\staff-setup"
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "logs") | Out-Null
    Write-Host "USB is read-only - logs/backups go to $DataDir" -ForegroundColor Yellow
}
$LogDir     = Join-Path $DataDir "logs"
$BackupBase = Join-Path $DataDir "backups"
$LogFile    = Join-Path $LogDir ("{0}-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))

function Log($msg, $color = "Gray") {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $LogFile -Value $line } catch {}
}
function Ok($msg)   { Log "[ OK ] $msg" "Green" }
function Warn($msg) { Log "[WARN] $msg" "Yellow" }
function Fail($msg) { Log "[FAIL] $msg" "Red" }

# Fetch-Installer <filename> <url> [-Always]
# Downloads <url> and returns a usable path.
function Fetch-Installer($name, $url, [switch]$Always) {
    $cached = Join-Path $Installers $name

    if ((Test-Path $cached) -and (-not $Always)) {
        Log "Using cached installers\$name"
        return $cached
    }
    if (-not $url) {
        if (Test-Path $cached) { return $cached }
        Fail "Missing installer: installers\$name (no download source - it must be supplied)."
        return $null
    }

    $dest = $cached
    try {
        New-Item -ItemType Directory -Force -Path $Installers -ErrorAction Stop | Out-Null
        $t = Join-Path $Installers ".write-test"
        New-Item -ItemType File -Force -Path $t -ErrorAction Stop | Out-Null
        Remove-Item $t -Force
    } catch {
        $dest = Join-Path $env:TEMP $name
    }

    Log "Downloading $name ..."
    Log "  $url"
    $part = "$dest.part"
    try {
        $ProgressPreference = 'SilentlyContinue'   # much faster downloads
        # Cloudflare Access service-token headers ONLY for the Access-protected host (never vendor CDNs)
        $hdrs = @{}
        if ($CF_ACCESS_CLIENT_ID -and $CF_ACCESS_HOST -and ($url -like "*$CF_ACCESS_HOST*")) {
            $hdrs['CF-Access-Client-Id'] = $CF_ACCESS_CLIENT_ID; $hdrs['CF-Access-Client-Secret'] = $CF_ACCESS_CLIENT_SECRET
        }
        Invoke-WebRequest -Uri $url -OutFile $part -Headers $hdrs -UseBasicParsing -ErrorAction Stop
        Move-Item $part $dest -Force
        $mb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Ok "Downloaded $name ($mb MB)"
        return $dest
    } catch {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        if (Test-Path $cached) {
            Warn "Download failed - falling back to cached installers\$name"
            return $cached
        }
        Fail "Download failed and nothing cached - check internet access."
        return $null
    }
}

function Resolve-RustDesk {
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" `
               -UseBasicParsing -ErrorAction Stop
        if ($rel.tag_name) {
            return @{
                Tag = $rel.tag_name
                Url = "https://github.com/rustdesk/rustdesk/releases/download/$($rel.tag_name)/rustdesk-$($rel.tag_name)-x86_64.exe"
            }
        }
    } catch {}
    return $null
}

# ---------- preflight ------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please re-run from an elevated PowerShell (Run as administrator)." -ForegroundColor Red
    exit 1
}

# ---------- staff user detection --------------------------------
function Detect-TargetUser {
    $guess = $null
    # Who ?!
    try {
        $cs = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($cs) { $guess = $cs.Split('\')[-1] }
    } catch {}
    if (-not $guess) {
        try {
            $expl = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
                Select-Object -First 1
            if ($expl) { $guess = $expl.GetOwner().User }
        } catch {}
    }
    if (-not $guess) { $guess = $env:USERNAME }

    while ($true) {
        $name = Read-Host "Staff user account to configure [$guess]"
        if (-not $name) { $name = $guess }
        $prof = Join-Path "C:\Users" $name
        if (Test-Path $prof) {
            $script:StaffUser = $name
            $script:StaffHome = $prof
            return
        }
        Write-Host "No profile at C:\Users\$name. Accounts on this PC:" -ForegroundColor Yellow
        Get-ChildItem "C:\Users" -Directory |
            Where-Object { $_.Name -notin "Public","Default","Default User","All Users" } |
            ForEach-Object { Write-Host "  $($_.Name)" }
    }
}

Detect-TargetUser
Log "=== Staff Windows setup on $env:COMPUTERNAME (staff user: $StaffUser) ===" "Cyan"

# ---------- status checks (read-only) ---------------------------
function Status-RustDesk {
    $exe = "C:\Program Files\RustDesk\rustdesk.exe"
    if (-not (Test-Path $exe)) { return @("not installed", "Yellow") }
    $v = (Get-Item $exe).VersionInfo.ProductVersion
    $cfg = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
    if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern $RUSTDESK_HOST -Quiet)) {
        return @("v$v, configured for $RUSTDESK_HOST", "Green")
    }
    return @("v$v, NOT configured for our server", "Red")
}

function Status-Wazuh {
    $svc = Get-Service WazuhSvc -ErrorAction SilentlyContinue
    if (-not $svc) { return @("not installed", "Yellow") }
    $keys = "C:\Program Files (x86)\ossec-agent\client.keys"
    $conf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
    $agent = ""
    if ((Test-Path $keys) -and (Get-Item $keys).Length -gt 0) {
        $agent = ((Get-Content $keys -First 1) -split " ")[1]
    }
    $mgrOk = (Test-Path $conf) -and (Select-String -Path $conf -Pattern $WAZUH_MANAGER -Quiet)
    if ($mgrOk -and $agent -and $svc.Status -eq "Running") {
        return @("enrolled as '$agent' -> $WAZUH_MANAGER, running", "Green")
    }
    return @("service $($svc.Status), enrolled as '$agent', manager ok: $mgrOk", "Red")
}

function Status-Fleet {
    $svc = Get-Service "Fleet osquery" -ErrorAction SilentlyContinue
    if (-not $svc) { return @("not installed", "Yellow") }
    if ($svc.Status -eq "Running") {
        return @("installed, service running (verify host at $FLEET_URL)", "Green")
    }
    return @("installed, service $($svc.Status)", "Red")
}

function Status-Chrome {
    $exe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $exe)) { $exe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" }
    if (-not (Test-Path $exe)) { return @("not installed", "Yellow") }
    $v = (Get-Item $exe).VersionInfo.ProductVersion
    $tok = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name CloudManagementEnrollmentToken -ErrorAction SilentlyContinue).CloudManagementEnrollmentToken
    switch ($tok) {
        $null            { return @("v$v, NOT enrolled (no token)", "Red") }
        $CHROME_TOKEN_CC { return @("v$v, enrollment token in place (CC)", "Green") }
        $CHROME_TOKEN_VC { return @("v$v, enrollment token in place (VC)", "Green") }
        default          { return @("v$v, has an UNRECOGNIZED enrollment token", "Red") }
    }
}

function Show-Status {
    Write-Host ""
    Write-Host "== Current status - $env:COMPUTERNAME ==" -ForegroundColor Cyan
    foreach ($row in @(
        @("RustDesk:", (Status-RustDesk)),
        @("Wazuh:",    (Status-Wazuh)),
        @("FleetDM:",  (Status-Fleet)),
        @("Chrome:",   (Status-Chrome))
    )) {
        Write-Host ("  {0,-10} " -f $row[0]) -NoNewline
        Write-Host $row[1][0] -ForegroundColor $row[1][1]
    }
    Write-Host ""
}

# ---------- 1) RustDesk install ---------------------------------
function Install-RustDesk {
    Log "--- RustDesk: install/update ---"
    $rdExe = "C:\Program Files\RustDesk\rustdesk.exe"
    $current = $null
    if (Test-Path $rdExe) {
        $current = (Get-Item $rdExe).VersionInfo.ProductVersion
        Log "RustDesk $current currently installed."
    }

    $exe = $null
    $rel = Resolve-RustDesk
    if ($rel) {
        Log "Current release: $($rel.Tag)"
        if ($current -and $current.StartsWith($rel.Tag)) {
            Ok "Already on the current version ($current) - nothing to do."
            return $true
        }
        $exe = Fetch-Installer "rustdesk-$($rel.Tag)-x86_64.exe" $rel.Url
    } else {
        Warn "Could not reach GitHub to check the current RustDesk version."
    }
    if (-not $exe) {
        # offline: newest cached RustDesk installer
        $exe = Get-ChildItem (Join-Path $Installers "rustdesk-*x86_64.exe") -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        if ($exe) { Warn "Using cached $(Split-Path $exe -Leaf)" }
    }
    if (-not $exe) { Fail "No RustDesk installer available (offline and nothing cached)."; return $false }

    Stop-Process -Name rustdesk -Force -ErrorAction SilentlyContinue
    $p = Start-Process $exe -ArgumentList "--silent-install" -Wait -PassThru
    Start-Sleep -Seconds 5
    if (Test-Path "C:\Program Files\RustDesk\rustdesk.exe") {
        $v = (Get-Item "C:\Program Files\RustDesk\rustdesk.exe").VersionInfo.ProductVersion
        Ok "RustDesk $v installed (service mode)."
        return $true
    }
    Fail "RustDesk install did not complete (exit $($p.ExitCode))."
    return $false
}

# ---------- 2) Wazuh (wazuh-enroll.ps1) ------------
function Do-Wazuh {
    Log "--- Wazuh: install + enroll (via wazuh-enroll.ps1) ---"
    $ws = Join-Path $ScriptDir "wazuh-enroll.ps1"
    if (-not (Test-Path $ws)) { Fail "wazuh-enroll.ps1 not found next to setup.ps1."; return $false }
    & $ws
    return ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
}

# ---------- 3) Fleet --------------------------------------------
function Install-Fleet {
    Log "--- FleetDM: install fleetd (this also enrolls the host) ---"
    #   fleetctl package --type=msi --enable-scripts --fleet-desktop \
    #     --fleet-url=$FLEET_URL --enroll-secret=<secret>
    $msi = Fetch-Installer $FLEET_MSI $FLEET_MSI_URL   # org-hosted fleetd MSI (config.env); enroll secret baked in
    if (-not $msi) { return $false }
    $p = Start-Process msiexec.exe -ArgumentList "/i", "`"$msi`"", "/qn" -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "Fleet MSI failed (exit $($p.ExitCode))."; return $false }
    Start-Sleep -Seconds 5
    $svc = Get-Service "Fleet osquery" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Ok "fleetd installed and running (enroll secret baked into the MSI)."
        Log "MANUAL CHECK: confirm this host appears at $FLEET_URL"

        # Restart Fleet Desktop to pick up new enrollment / config
        try { Stop-Process -Name "Fleet Desktop" -Force -ErrorAction SilentlyContinue } catch { }
        return $true
    }
    Fail "Fleet service not running after install."
    return $false
}

# ---------- 4) Chrome install -----------------------------------
function Install-Chrome {
    Log "--- Google Chrome: install ---"
    $exists = (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") -or
              (Test-Path "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")
    if ($exists) { Ok "Chrome already installed (it self-updates; leaving it alone)."; return $true }
    $msi = Fetch-Installer $CHROME_MSI $CHROME_URL -Always
    if (-not $msi) { return $false }
    $p = Start-Process msiexec.exe -ArgumentList "/i", "`"$msi`"", "/qn" -Wait -PassThru
    if ($p.ExitCode -ne 0) { Fail "Chrome MSI failed (exit $($p.ExitCode))."; return $false }
    Ok "Chrome installed."
    return $true
}

# ---------- 5) RustDesk config ----------------------------------
function Config-RustDesk {
    Log "--- RustDesk: point at our ID/relay server ---"
    if (-not (Test-Path "C:\Program Files\RustDesk\rustdesk.exe")) {
        Fail "RustDesk is not installed - run its install step first."
        return $false
    }
    Stop-Service -Name RustDesk -ErrorAction SilentlyContinue
    Stop-Process -Name rustdesk -Force -ErrorAction SilentlyContinue

    $toml = @"
rendezvous_server = '$($RUSTDESK_HOST):21116'

[options]
custom-rendezvous-server = '$RUSTDESK_HOST'
relay-server = '$RUSTDESK_RELAY'
key = '$RUSTDESK_KEY'
"@
    # service config (unattended access) + staff user's config
    $targets = @(
        "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config",
        (Join-Path $StaffHome "AppData\Roaming\RustDesk\config")
    )
    foreach ($dir in $targets) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir "RustDesk2.toml") -Value $toml -Encoding ASCII
        Ok "Config written: $dir\RustDesk2.toml"
    }
    Start-Service -Name RustDesk -ErrorAction SilentlyContinue
    Ok "RustDesk pointed at $RUSTDESK_HOST. Open RustDesk and confirm it says Ready."
    return $true
}

# ---------- 6) Chrome config (bookmarks backup + token) ---------
function Backup-ChromeBookmarks {
    $chromeDir = Join-Path $StaffHome "AppData\Local\Google\Chrome\User Data"
    if (-not (Test-Path $chromeDir)) {
        Log "No Chrome user data for $StaffUser yet - nothing to back up."
        return
    }
    $dest = Join-Path $BackupBase $env:COMPUTERNAME
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $found = $false
    Get-ChildItem $chromeDir -Directory |
        Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } |
        ForEach-Object {
            $bm = Join-Path $_.FullName "Bookmarks"
            if (Test-Path $bm) {
                $out = Join-Path $dest ("{0}-Bookmarks-{1}.json" -f ($_.Name -replace " ","_"), $stamp)
                Copy-Item $bm $out -Force
                Ok "Bookmarks backed up: $out"
                $found = $true
            }
        }
    if (-not $found) { Log "No bookmark files found for $StaffUser." }
}

function Config-Chrome {
    Log "--- Chrome: enroll in browser cloud management ---"
    $exists = (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") -or
              (Test-Path "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")
    if (-not $exists) { Fail "Chrome is not installed - run its install step first."; return $false }

    Backup-ChromeBookmarks

    $token = $null; $org = $null
    while (-not $token) {
        $ans = Read-Host "Which org is this staff member under? [1=CC, 2=VC]"
        switch -Regex ($ans) {
            '^(1|cc|CC)$' { $org = "CC"; $token = $CHROME_TOKEN_CC }
            '^(2|vc|VC)$' { $org = "VC"; $token = $CHROME_TOKEN_VC }
            default       { Write-Host "Please enter 1 (CC) or 2 (VC)." -ForegroundColor Yellow }
        }
    }
    New-Item -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" `
        -Name "CloudManagementEnrollmentToken" -Value $token
    Ok "$org enrollment token written to registry. Chrome enrolls on next launch."
    Log "Verify in Google Admin -> Managed browsers, or chrome://management on this PC."
    return $true
}

# ---------- heal / reconcile (fix drifted / offline agents) ------
# Each Heal-* checks an already-installed service against config.env and repoints
# only what's stale (old/dead URL) or offline. Skips anything not installed.

function Heal-Fleet {
    $svc = Get-Service "Fleet osquery" -ErrorAction SilentlyContinue
    if (-not $svc) { Log "Fleet not installed here - nothing to heal."; return $true }
    $cur = Get-ChildItem "C:\Program Files\Orbit" -Recurse -File -ErrorAction SilentlyContinue |
           Select-String -Pattern 'https?://fleet\.[a-z0-9.-]+' -ErrorAction SilentlyContinue |
           ForEach-Object { $_.Matches.Value } | Select-Object -Unique -First 1
    if (($cur -ne $FLEET_URL) -or ($svc.Status -ne "Running")) {
        Warn "Fleet drift - configured for '$cur', service $($svc.Status); expected $FLEET_URL."
        Log "Re-installing fleetd from the current package (repoints URL + re-enrolls)."
        return (Install-Fleet)
    }
    Ok "Fleet already on $FLEET_URL and running - no change."
    return $true
}

function Heal-Wazuh {
    $svc = Get-Service WazuhSvc -ErrorAction SilentlyContinue
    if (-not $svc) { Log "Wazuh not installed here - nothing to heal."; return $true }
    $conf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
    $cur = ""
    if (Test-Path $conf) {
        $m = Select-String -Path $conf -Pattern '<address>([^<]+)</address>' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { $cur = $m.Matches[0].Groups[1].Value.Trim() }
    }
    if (($cur -ne $WAZUH_MANAGER) -or ($svc.Status -ne "Running")) {
        Warn "Wazuh drift - manager '$cur', service $($svc.Status); expected $WAZUH_MANAGER."
        if (Test-Path $conf) {
            Copy-Item $conf "$conf.deploykit-bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
            (Get-Content $conf -Raw) -replace '<address>[^<]*</address>', "<address>$WAZUH_MANAGER</address>" |
                Set-Content $conf -Encoding ASCII
            Log "Repointed ossec.conf to $WAZUH_MANAGER; restarting the agent."
        }
        Restart-Service WazuhSvc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svc = Get-Service WazuhSvc -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") { Ok "Wazuh repointed to $WAZUH_MANAGER and running."; return $true }
        Fail "Wazuh restarted but not running - may need a fresh enroll (menu option 2)."
        return $false
    }
    Ok "Wazuh already on $WAZUH_MANAGER and running - no change."
    return $true
}

function Heal-RustDesk {
    if (-not (Test-Path "C:\Program Files\RustDesk\rustdesk.exe")) {
        Log "RustDesk not installed here - nothing to heal."; return $true
    }
    $cfg = "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
    if ((-not (Test-Path $cfg)) -or -not (Select-String -Path $cfg -Pattern $RUSTDESK_HOST -Quiet -ErrorAction SilentlyContinue)) {
        Warn "RustDesk drift - not pointed at $RUSTDESK_HOST; reconfiguring."
        return (Config-RustDesk)
    }
    Ok "RustDesk already pointed at $RUSTDESK_HOST - no change."
    return $true
}

function Heal-All {
    Log "=== Heal / reconcile: checking installed services against config.env ==="
    Heal-Fleet    | Out-Null
    Heal-Wazuh    | Out-Null
    Heal-RustDesk | Out-Null
    Log "=== Heal complete ==="
    return $true
}

# ---------- menu -------------------------------------------------
$Results = @()
function Run-Step($label, $fn) {
    $ok = & $fn
    if ($ok) { $script:Results += "  [OK]   $label" } else { $script:Results += "  [FAIL] $label" }
}

Show-Status
while ($true) {
    Write-Host "Pick steps (space-separated for several, e.g. '5 6'):" -ForegroundColor White
    Write-Host "  Install / update" -ForegroundColor Yellow
    Write-Host "    1) RustDesk        3) FleetDM (installing also enrolls)"
    Write-Host "    4) Chrome"
    Write-Host "  Install + configure in one go" -ForegroundColor Yellow
    Write-Host "    2) Wazuh agent  -> installs + enrolls (asks agent name)"
    Write-Host "  Configure only (already installed)" -ForegroundColor Yellow
    Write-Host "    5) RustDesk -> point at our ID/relay server"
    Write-Host "    6) Chrome   -> backup bookmarks + enroll in management"
    Write-Host "  Heal (fix installed services that drifted / went offline)" -ForegroundColor Yellow
    Write-Host "    h) reconcile Fleet/Wazuh/RustDesk to config.env"
    Write-Host "  Bundles" -ForegroundColor Yellow
    Write-Host "    a) everything (1-6)"
    Write-Host "  s) Show status     q) Quit"
    $choice = Read-Host ">"

    switch -Regex ($choice) {
        '^[qQ]$' { $choice = $null }
        '^[sS]$' { Show-Status; continue }
        '^[hH]$' { Heal-All; Show-Status; continue }
        '^[aA]$' { $choice = "1 2 3 4 5 6" }
    }
    if (-not $choice) { break }

    $ran = $false
    foreach ($c in ($choice -split '\s+')) {
        switch ($c) {
            "1" { Run-Step "RustDesk install"     ${function:Install-RustDesk}; $ran = $true }
            "2" { Run-Step "Wazuh install+enroll" ${function:Do-Wazuh};         $ran = $true }
            "3" { Run-Step "FleetDM install"      ${function:Install-Fleet};    $ran = $true }
            "4" { Run-Step "Chrome install"       ${function:Install-Chrome};   $ran = $true }
            "5" { Run-Step "RustDesk config"      ${function:Config-RustDesk};  $ran = $true }
            "6" { Run-Step "Chrome config"        ${function:Config-Chrome};    $ran = $true }
            default { if ($c) { Write-Host "Unknown option: $c" } }
        }
    }
    if ($ran) { Show-Status }
}

Write-Host ""
Write-Host "=== Summary for $env:COMPUTERNAME ===" -ForegroundColor Cyan
if ($Results.Count) { $Results | ForEach-Object {
    if ($_ -match "OK")   { Write-Host $_ -ForegroundColor Green }
    else                  { Write-Host $_ -ForegroundColor Red }
}} else { Write-Host "  (nothing was run)" }
Log "Log saved to: $LogFile"

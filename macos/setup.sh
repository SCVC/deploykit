#!/bin/bash
# ============================================================
# Staff Mac setup — RustDesk / Wazuh / FleetDM / Chrome
# ============================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLERS="$SCRIPT_DIR/installers"

# Logs and bookmark backups go on the USB when it's writable. If it
# isn't (NTFS sticks mount read-only on macOS), fall back to
# /Users/Shared/staff-setup on the machine itself.
if touch "$SCRIPT_DIR/.write-test" 2>/dev/null; then
  rm -f "$SCRIPT_DIR/.write-test"
  KIT_WRITABLE=1
  DATA_DIR="$SCRIPT_DIR"
else
  KIT_WRITABLE=0
  DATA_DIR="/Users/Shared/staff-setup"
fi
LOG_DIR="$DATA_DIR/logs"
BACKUP_BASE="$DATA_DIR/backups"
LOG_FILE="$LOG_DIR/$(hostname -s)-$(date +%Y%m%d-%H%M%S).log"

# ---------- helpers -----------------------------------------

BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)

log()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
ok()   { log "${GREEN}[ OK ]${RESET} $*"; }
warn() { log "${YELLOW}[WARN]${RESET} $*"; }
fail() { log "${RED}[FAIL]${RESET} $*"; }

need_installer() {  
  # need_installer <filename> [download_url] — use a local copy if present, else download.
  local name="$1" url="${2:-}"
  [[ -f "$INSTALLERS/$name" ]] && return 0
  if [[ -n "$url" ]]; then
    log "Downloading $name ..."
    mkdir -p "$INSTALLERS"
    # send Cloudflare Access service-token headers ONLY to the Access-protected host (never to vendor CDNs)
    local -a hdr=()
    if [[ -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_HOST:-}" && "$url" == *"$CF_ACCESS_HOST"* ]]; then
      hdr=(-H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}")
    fi
    if curl -fL --retry 3 "${hdr[@]}" -o "$INSTALLERS/$name.part" "$url" 2>>"$LOG_FILE" && mv "$INSTALLERS/$name.part" "$INSTALLERS/$name"; then
      ok "Downloaded $name ($(du -h "$INSTALLERS/$name" 2>/dev/null | cut -f1 | tr -d ' '))"
      return 0
    fi
    rm -f "$INSTALLERS/$name.part"; fail "Download failed: $name from $url"; return 1
  fi
  fail "Missing installer: installers/$name and no download URL set (see config.env)."
  return 1
}

# Resolve the latest RustDesk .dmg URL for an arch (aarch64 | x86_64).
rustdesk_url() {
  local tag
  tag=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | cut -d'"' -f4)
  [[ -n "$tag" ]] && printf 'https://github.com/rustdesk/rustdesk/releases/download/%s/rustdesk-%s-%s.dmg' "$tag" "$tag" "$1"
}

app_version() {
  /usr/bin/defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}


detect_target_user() {
  local guess
  guess=$(stat -f%Su /dev/console 2>/dev/null)
  [[ -z "$guess" || "$guess" == "root" ]] && guess="${SUDO_USER:-}"

  while true; do
    printf "%s" "${BOLD}Staff user account to configure [${guess}]:${RESET} "
    read -r CONSOLE_USER
    CONSOLE_USER="${CONSOLE_USER:-$guess}"
    if dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory >/dev/null 2>&1; then
      break
    fi
    echo "No such user on this Mac. Accounts here:"
    dscl . -list /Users | grep -v '^_' | grep -vE '^(daemon|nobody|root)$' | sed 's/^/  /'
  done

  CONSOLE_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')
  CONSOLE_HOME="${CONSOLE_HOME:-/Users/$CONSOLE_USER}"
}

# ---------- preflight ----------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo:  sudo bash setup.sh"
  exit 1
fi

mkdir -p "$LOG_DIR"

CONFIG_FILE="$SCRIPT_DIR/config.env"
[[ -f "$CONFIG_FILE" ]] || CONFIG_FILE="$SCRIPT_DIR/../config.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "config.env not found next to setup.sh — aborting."
  exit 1
fi
# shellcheck source=config.env
source "$CONFIG_FILE"

# Pick the right RustDesk/Wazuh installer for this machine's chip 
ARCH=$(uname -m)
if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" == "1" ]]; then
  ARCH="arm64"   # shell is running under Rosetta, but the hardware is Apple Silicon
fi
case "$ARCH" in
  arm64)
    ARCH_LABEL="Apple Silicon"
    RUSTDESK_DMG="$RUSTDESK_DMG_ARM"
    RUSTDESK_ARCH="aarch64"
    ;;
  x86_64)
    ARCH_LABEL="Intel"
    RUSTDESK_DMG="$RUSTDESK_DMG_INTEL"
    RUSTDESK_ARCH="x86_64"
    ;;
  *)
    echo "Unrecognized architecture '$ARCH' — aborting."
    exit 1
    ;;
esac

detect_target_user
log "=== Staff Mac setup started on $(hostname) ($ARCH_LABEL, staff user: $CONSOLE_USER) ==="
if [[ $KIT_WRITABLE -eq 0 ]]; then
  warn "USB is read-only on this Mac (NTFS) — logs and bookmark backups"
  warn "will be saved on this machine at $DATA_DIR instead."
fi

# ---------- status checks (read-only) ------------------------

status_rustdesk() {
  local v toml="$CONSOLE_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  v=$(app_version "/Applications/RustDesk.app")
  if [[ -z "$v" ]]; then echo "${YELLOW}not installed${RESET}"; return; fi
  if [[ -f "$toml" ]] && grep -q "$RUSTDESK_HOST" "$toml" 2>/dev/null; then
    echo "${GREEN}v$v, configured for $RUSTDESK_HOST${RESET}"
  else
    echo "${RED}v$v, NOT configured for our server${RESET}"
  fi
}

status_wazuh() {
  if [[ ! -d /Library/Ossec ]]; then echo "${YELLOW}not installed${RESET}"; return; fi
  local v state agent
  v=$(/Library/Ossec/bin/wazuh-control info -v 2>/dev/null | tr -d 'v')
  if /Library/Ossec/bin/wazuh-control status 2>/dev/null | grep -q "is running"; then
    state="running"
  else
    state="INSTALLED BUT NOT RUNNING"
  fi
  agent=$(awk '{print $2; exit}' /Library/Ossec/etc/client.keys 2>/dev/null)
  if grep -q "$WAZUH_MANAGER" /Library/Ossec/etc/ossec.conf 2>/dev/null; then
    if [[ -n "$agent" && "$state" == "running" ]]; then
      echo "${GREEN}v${v:-?}, enrolled as '$agent' -> $WAZUH_MANAGER, running${RESET}"
    else
      echo "${RED}v${v:-?}, enrolled as '${agent:-NOT ENROLLED}' -> $WAZUH_MANAGER, $state${RESET}"
    fi
  else
    echo "${RED}v${v:-?}, manager NOT set to $WAZUH_MANAGER, $state${RESET}"
  fi
}

status_fleet() {
  if [[ ! -d /opt/orbit ]]; then echo "${YELLOW}not installed${RESET}"; return; fi
  if launchctl print system/com.fleetdm.orbit >/dev/null 2>&1; then
    echo "${GREEN}installed, orbit daemon loaded${RESET} (verify host at $FLEET_URL)"
  else
    echo "${RED}installed, but orbit daemon NOT loaded${RESET}"
  fi
}

status_chrome() {
  local v tok; v=$(app_version "/Applications/Google Chrome.app")
  if [[ -z "$v" ]]; then echo "${YELLOW}not installed${RESET}"; return; fi
  tok=$(cat "/Library/Google/Chrome/CloudManagementEnrollmentToken" 2>/dev/null)
  case "$tok" in
    "")                echo "${RED}v$v, NOT enrolled (no token file)${RESET}" ;;
    "$CHROME_TOKEN_CC") echo "${GREEN}v$v, enrollment token in place (CC)${RESET}" ;;
    "$CHROME_TOKEN_VC") echo "${GREEN}v$v, enrollment token in place (VC)${RESET}" ;;
    *)                 echo "${RED}v$v, has an UNRECOGNIZED enrollment token${RESET}" ;;
  esac
}

show_status() {
  echo ""
  echo "${CYAN}${BOLD}══ Current status — $(hostname -s) (${ARCH_LABEL}) ══${RESET}"
  printf "  ${BOLD}%-12s${RESET} %s\n" "RustDesk:" "$(status_rustdesk)"
  printf "  ${BOLD}%-12s${RESET} %s\n" "Wazuh:"    "$(status_wazuh)"
  printf "  ${BOLD}%-12s${RESET} %s\n" "FleetDM:"  "$(status_fleet)"
  printf "  ${BOLD}%-12s${RESET} %s\n" "Chrome:"   "$(status_chrome)"
  echo ""
}

# ============================================================
#  INSTALL / UPDATE steps
# ============================================================

install_rustdesk() {
  log "--- RustDesk: install/update ---"
  local v; v=$(app_version "/Applications/RustDesk.app")
  [[ -n "$v" ]] && log "RustDesk $v present; replacing with USB copy."
  log "Using $RUSTDESK_DMG ($ARCH_LABEL build)."
  need_installer "$RUSTDESK_DMG" "$(rustdesk_url "$RUSTDESK_ARCH")" || return 1

  pkill -x RustDesk 2>/dev/null || true
  local mount
  mount=$(hdiutil attach -nobrowse -readonly "$INSTALLERS/$RUSTDESK_DMG" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
  if [[ -z "$mount" || ! -d "$mount" ]]; then
    fail "Could not mount $RUSTDESK_DMG"; return 1
  fi
  if [[ -d "$mount/RustDesk.app" ]]; then
    rm -rf "/Applications/RustDesk.app"
    cp -R "$mount/RustDesk.app" /Applications/
    ok "RustDesk $(app_version /Applications/RustDesk.app) installed."
  else
    fail "RustDesk.app not found inside the DMG."
    hdiutil detach "$mount" -quiet; return 1
  fi
  hdiutil detach "$mount" -quiet
}

do_wazuh() {
  log "--- Wazuh agent: install + enroll (via wazuh-enroll.sh) ---"
  local enroll_script="$SCRIPT_DIR/wazuh-enroll.sh"
  if [[ ! -f "$enroll_script" ]]; then
    fail "wazuh-enroll.sh not found next to setup.sh."
    return 1
  fi

  # agent name is unique per machine (ex: VC021)
  local default_name agent_name
  default_name=$(hostname -s)
  printf "%s" "${BOLD}Agent name for this machine (e.g. VC021) [${default_name}]:${RESET} "
  read -r agent_name
  agent_name="${agent_name:-$default_name}"

  while [[ -z "${WAZUH_ENROLL_PASSWORD:-}" ]]; do
    printf "%s" "${BOLD}Wazuh enrollment password:${RESET} "
    read -rs WAZUH_ENROLL_PASSWORD
    echo ""
    [[ -z "$WAZUH_ENROLL_PASSWORD" ]] && echo "${YELLOW}Password cannot be empty.${RESET}"
  done

  log "Enrolling as '$agent_name' against $WAZUH_ENROLL_HOST"

  bash "$enroll_script" -e "$WAZUH_ENROLL_HOST" -n "$agent_name" -p "$WAZUH_ENROLL_PASSWORD" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -eq 0 ]]; then
    ok "Wazuh agent enrolled as '$agent_name'."
    log "Verify the host shows as Active in the Wazuh dashboard."
  else
    fail "Wazuh enrollment failed (exit $rc) — see output above and $LOG_FILE"
    return 1
  fi
}

install_fleet() {
  log "--- FleetDM: install fleetd (this also enrolls the host) ---"
  need_installer "$FLEET_PKG" "${FLEET_PKG_URL:-}" || return 1
  [[ -d /opt/orbit ]] && log "fleetd present; pkg will upgrade/re-enroll."

  if installer -pkg "$INSTALLERS/$FLEET_PKG" -target / >>"$LOG_FILE" 2>&1; then
    ok "fleetd installed (enroll secret + URL are baked into the pkg)."
  else
    fail "Fleet pkg install failed — see log."; return 1
  fi

  # Restart Fleet Desktop to pick up new enrollment / config
  pkill -x "Fleet Desktop" 2>/dev/null || true
  sleep 3

  if launchctl print system/com.fleetdm.orbit >/dev/null 2>&1; then
    ok "orbit daemon is loaded."
    log "MANUAL CHECK: confirm this host appears (and its profile status) at $FLEET_URL"
  else
    fail "orbit daemon not loaded — try rebooting, then check Fleet."
    return 1
  fi
}

install_chrome() {
  log "--- Google Chrome: install/update ---"
  local v; v=$(app_version "/Applications/Google Chrome.app")
  if [[ -n "$v" ]]; then
    ok "Chrome $v already installed (it self-updates; leaving it alone)."
    return 0
  fi
  need_installer "$CHROME_PKG" "${CHROME_PKG_URL:-}" || return 1
  if installer -pkg "$INSTALLERS/$CHROME_PKG" -target / >>"$LOG_FILE" 2>&1; then
    ok "Chrome $(app_version "/Applications/Google Chrome.app") installed."
  else
    fail "Chrome pkg install failed — see log."; return 1
  fi
}

# ============================================================
#  CONFIGURE-ONLY steps (software must already be installed)
# ============================================================

config_rustdesk() {
  log "--- RustDesk: point at our ID/relay server ---"
  if [[ ! -d /Applications/RustDesk.app ]]; then
    fail "RustDesk is not installed — run its install step first."
    return 1
  fi

  pkill -x RustDesk 2>/dev/null || true
  local cfg_dir="$CONSOLE_HOME/Library/Preferences/com.carriez.RustDesk"
  mkdir -p "$cfg_dir"
  cat > "$cfg_dir/RustDesk2.toml" <<EOF
rendezvous_server = '${RUSTDESK_HOST}:21116'

[options]
custom-rendezvous-server = '${RUSTDESK_HOST}'
relay-server = '${RUSTDESK_RELAY}'
key = '${RUSTDESK_KEY}'
EOF
  chown -R "$CONSOLE_USER" "$cfg_dir"
  ok "RustDesk pointed at $RUSTDESK_HOST (ID/relay + key) for user $CONSOLE_USER."

  warn "MANUAL STEP: open RustDesk as $CONSOLE_USER and approve the System"
  warn "Settings prompts (Screen Recording, Accessibility, Input Monitoring),"
  warn "then confirm the main window shows 'Ready'."
  warn "Staff account is non-admin? System Settings will ask for admin"
  warn "credentials to unlock those toggles — enter YOUR admin login there."
}

backup_chrome_bookmarks() {
  # Copies every Chrome profile's Bookmarks file to the USB
  local chrome_dir="$CONSOLE_HOME/Library/Application Support/Google/Chrome"
  local backup_dir="$BACKUP_BASE/$(hostname -s)"
  local profile_dir profile_name dest found=0

  if [[ ! -d "$chrome_dir" ]]; then
    log "No Chrome user data for $CONSOLE_USER yet — nothing to back up."
    return 0
  fi
  mkdir -p "$backup_dir"

  for profile_dir in "$chrome_dir/Default" "$chrome_dir"/Profile\ *; do
    [[ -f "$profile_dir/Bookmarks" ]] || continue
    profile_name=$(basename "$profile_dir" | tr ' ' '_')
    dest="$backup_dir/${profile_name}-Bookmarks-$(date +%Y%m%d-%H%M%S).json"
    if cp "$profile_dir/Bookmarks" "$dest"; then
      ok "Bookmarks backed up: $dest"
      found=1
    else
      warn "Could not back up bookmarks from $profile_dir"
    fi
  done
  [[ $found -eq 0 ]] && log "No bookmark files found for $CONSOLE_USER."
  return 0
}

config_chrome() {
  log "--- Chrome: enroll in browser cloud management ---"
  if [[ ! -d "/Applications/Google Chrome.app" ]]; then
    fail "Chrome is not installed — run its install step first."
    return 1
  fi

  backup_chrome_bookmarks

  # two orgs, two tokens
  local org token
  while true; do
    printf "%s" "${BOLD}Which org is this staff member under? [1=CC, 2=VC]:${RESET} "
    read -r org
    case "$org" in
      1|cc|CC) org="CC"; token="$CHROME_TOKEN_CC"; break ;;
      2|vc|VC) org="VC"; token="$CHROME_TOKEN_VC"; break ;;
      *) echo "Please enter 1 (CC) or 2 (VC)." ;;
    esac
  done

  mkdir -p "/Library/Google/Chrome"
  printf '%s' "$token" > "/Library/Google/Chrome/CloudManagementEnrollmentToken"
  chmod 644 "/Library/Google/Chrome/CloudManagementEnrollmentToken"
  ok "$org enrollment token written. Chrome enrolls on next launch."
  log "Verify under Google Admin -> Devices -> Chrome -> Managed browsers,"
  log "or on the machine at chrome://management"
}

# ============================================================
#  HEAL / RECONCILE — fix already-installed services that have
#  drifted off config.env (wrong URL/host) or gone offline.
# ============================================================

# Fleet URL currently baked into this host's orbit config (empty if none)
fleet_current_url() {
  grep -rhoE 'https?://fleet\.[a-z0-9.-]+' \
    /Library/LaunchDaemons/com.fleetdm.orbit.plist /opt/orbit 2>/dev/null | sort -u | head -1
}

heal_fleet() {
  if [[ ! -d /opt/orbit ]]; then log "Fleet not installed here — nothing to heal."; return 0; fi
  local cur loaded=0
  cur=$(fleet_current_url)
  launchctl print system/com.fleetdm.orbit >/dev/null 2>&1 && loaded=1
  if [[ "$cur" != "$FLEET_URL" || $loaded -eq 0 ]]; then
    warn "Fleet drift — configured for '${cur:-unknown}', daemon loaded=$loaded; expected $FLEET_URL."
    log "Re-installing fleetd from the current package (repoints the URL + re-enrolls)."
    install_fleet
  else
    ok "Fleet already on $FLEET_URL and running — no change."
  fi
}

heal_wazuh() {
  if [[ ! -d /Library/Ossec ]]; then log "Wazuh not installed here — nothing to heal."; return 0; fi
  local conf=/Library/Ossec/etc/ossec.conf cur running=0
  cur=$(grep -oE '<address>[^<]+</address>' "$conf" 2>/dev/null | head -1 | sed 's/<[^>]*>//g' | xargs)
  /Library/Ossec/bin/wazuh-control status 2>/dev/null | grep -q 'is running' && running=1
  if [[ "$cur" != "$WAZUH_MANAGER" || $running -eq 0 ]]; then
    warn "Wazuh drift — manager '${cur:-unset}', running=$running; expected $WAZUH_MANAGER."
    cp "$conf" "$conf.deploykit-bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null
    sed -i '' -E "s#<address>[^<]*</address>#<address>${WAZUH_MANAGER}</address>#g" "$conf"
    log "Repointed ossec.conf to $WAZUH_MANAGER; restarting the agent."
    /Library/Ossec/bin/wazuh-control restart >>"$LOG_FILE" 2>&1
    sleep 3
    if /Library/Ossec/bin/wazuh-control status 2>/dev/null | grep -q 'is running'; then
      ok "Wazuh repointed to $WAZUH_MANAGER and running."
    else
      fail "Wazuh restarted but is not running — may need a fresh enroll (menu option 2)."; return 1
    fi
  else
    ok "Wazuh already on $WAZUH_MANAGER and running — no change."
  fi
}

heal_rustdesk() {
  if [[ ! -d /Applications/RustDesk.app ]]; then log "RustDesk not installed here — nothing to heal."; return 0; fi
  local toml="$CONSOLE_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
  if [[ ! -f "$toml" ]] || ! grep -q "$RUSTDESK_HOST" "$toml" 2>/dev/null; then
    warn "RustDesk drift — not pointed at $RUSTDESK_HOST; reconfiguring."
    config_rustdesk
  else
    ok "RustDesk already pointed at $RUSTDESK_HOST — no change."
  fi
}

# Reconcile every installed service against config.env (skips anything not installed)
heal_all() {
  log "=== Heal / reconcile: checking installed services against config.env ==="
  heal_fleet
  heal_wazuh
  heal_rustdesk
  log "=== Heal complete ==="
}

# ---------- menu -----------------------------------------------

RESULTS=""
run_step() {
  if "$2"; then RESULTS+="  ${GREEN}✓${RESET} $1\n"; else RESULTS+="  ${RED}✗${RESET} $1\n"; fi
}

show_status

while true; do
  echo "${BOLD}Pick steps (space-separated for several, e.g. '5 6'):${RESET}"
  echo "  ${YELLOW}${BOLD}Install / update${RESET}"
  echo "    ${CYAN}${BOLD}1)${RESET} RustDesk        ${CYAN}${BOLD}3)${RESET} FleetDM (installing also enrolls)"
  echo "    ${CYAN}${BOLD}4)${RESET} Chrome"
  echo "  ${YELLOW}${BOLD}Install + configure in one go${RESET}"
  echo "    ${CYAN}${BOLD}2)${RESET} Wazuh agent  -> downloads, installs, enrolls (asks agent name)"
  echo "  ${YELLOW}${BOLD}Configure only (already installed)${RESET}"
  echo "    ${CYAN}${BOLD}5)${RESET} RustDesk -> point at our ID/relay server"
  echo "    ${CYAN}${BOLD}6)${RESET} Chrome   -> enroll in browser management"
  echo "  ${YELLOW}${BOLD}Heal (fix installed services that drifted / went offline)${RESET}"
  echo "    ${CYAN}${BOLD}h)${RESET} check + repoint Fleet / Wazuh / RustDesk to config.env"
  echo "  ${YELLOW}${BOLD}Bundles${RESET}"
  echo "    ${CYAN}${BOLD}a)${RESET} everything (1-6)"
  echo "  ${GREEN}${BOLD}s)${RESET} Show status     ${RED}${BOLD}q)${RESET} Quit"
  printf "${BOLD}> ${RESET}"
  read -r choice

  case "$choice" in
    q|Q) break ;;
    s|S) show_status; continue ;;
    h|H) heal_all; show_status; continue ;;
    a|A) choice="1 2 3 4 5 6" ;;
    *)   ;;
  esac

  valid=0
  for c in $choice; do
    case "$c" in
      1) run_step "RustDesk install"       install_rustdesk; valid=1 ;;
      2) run_step "Wazuh install+enroll"   do_wazuh;         valid=1 ;;
      3) run_step "FleetDM install"        install_fleet;    valid=1 ;;
      4) run_step "Chrome install"         install_chrome;   valid=1 ;;
      5) run_step "RustDesk config"        config_rustdesk;  valid=1 ;;
      6) run_step "Chrome config"          config_chrome;    valid=1 ;;
      *) echo "Unknown option: $c" ;;
    esac
  done
  [[ $valid -eq 1 ]] && show_status
done

echo ""
echo "${BOLD}=== Summary for $(hostname -s) ===${RESET}"
if [[ -n "$RESULTS" ]]; then printf "%b" "$RESULTS"; else echo "  (nothing was run)"; fi
echo "Log saved to: $LOG_FILE"
log "=== Session finished ==="

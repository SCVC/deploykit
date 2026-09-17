#!/usr/bin/env bash
# ============================================================
# fleet-enroll.sh — FleetDM (fleetd/orbit) install + enrollment, macOS
#
# Fleet's agent is org-specific: the Fleet URL and enroll secret are baked
# into a package you build yourself with fleetctl and host where machines can
# reach it. There is no generic installer to download, so when no package is
# configured this script SKIPS with build-and-host guidance instead of failing.
#
#   sudo ./fleet-enroll.sh              — use config.env / installers/
#   sudo ./fleet-enroll.sh -u <url>     — install from an explicit .pkg URL
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLERS="${INSTALLERS:-$SCRIPT_DIR/installers}"
FLEET_PKG="${FLEET_PKG:-fleet-osquery.pkg}"

BOLD=$(tput bold 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true); RED=$(tput setaf 1 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)

log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { log "${GREEN}[ OK ]${RESET} $*"; }
warn() { log "${YELLOW}[WARN]${RESET} $*"; }
fail() { log "${RED}[FAIL]${RESET} $*"; }

usage() {
  cat <<EOF

FleetDM agent (fleetd) install + enrollment — macOS

Usage:
  sudo ./$(basename "$0")              install from FLEET_PKG_URL / installers/${FLEET_PKG}
  sudo ./$(basename "$0") -u <url>     install from an explicit package URL
  sudo ./$(basename "$0") -h           this help

Reads FLEET_PKG_URL, FLEET_URL and the optional CF_ACCESS_* settings from
config.env (beside this script or in the repo root) when they are not already
set in the environment.

EOF
}

while getopts ":u:h" opt; do
  case "$opt" in
    u) FLEET_PKG_URL="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -${OPTARG} requires an argument." >&2; exit 2 ;;
    *) usage; echo "Unknown option: -${OPTARG}" >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || { fail "macOS only — use windows/fleet-enroll.ps1 on Windows."; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Please run with sudo:  sudo bash fleet-enroll.sh"; exit 1; }

# Load config.env only when the caller hasn't already supplied the settings.
if [[ -z "${FLEET_PKG_URL:-}" && -z "${FLEET_URL:-}" ]]; then
  for candidate in "$SCRIPT_DIR/config.env" "$SCRIPT_DIR/../config.env"; do
    if [[ -f "$candidate" ]]; then
      # shellcheck source=/dev/null
      source "$candidate"
      break
    fi
  done
fi

# ---------- skip path ---------------------------------------

skip_with_guidance() {
  cat <<EOF

${YELLOW}[SKIP]${RESET} Fleet is not configured on this kit — fleetd was not installed.

  Fleet's agent is built per organization: the Fleet URL and enroll secret are
  compiled into the package, so there is no generic installer to fetch.

  To enable it:

    1. Install fleetctl and log in to your Fleet server:
         npm install -g fleetctl          # or: brew install fleetctl
         fleetctl login

    2. Build the macOS package with your enroll secret:
         fleetctl package --type=pkg --fleet-desktop \\
           --fleet-url=${FLEET_URL:-https://fleet.example.com} \\
           --enroll-secret=<your-enroll-secret>

    3. Host the resulting .pkg where machines can fetch it (GitHub Release,
       internal share, object storage — optionally behind Cloudflare Access)
       and set it in config.env:
         FLEET_PKG_URL="https://.../fleet-osquery.pkg"

       …or copy the package to installers/${FLEET_PKG} on the kit itself.

  Nothing on this machine was changed.

EOF
  exit 0
}

# ---------- fetch the package --------------------------------

fetch_pkg() {
  # Use a local copy when the kit carries one.
  [[ -f "$INSTALLERS/$FLEET_PKG" ]] && { log "Using installers/${FLEET_PKG}"; return 0; }
  [[ -n "${FLEET_PKG_URL:-}" ]] || skip_with_guidance

  log "Downloading ${FLEET_PKG} ..."
  mkdir -p "$INSTALLERS"
  # Cloudflare Access service-token headers go ONLY to the Access-protected host
  local -a hdr=()
  if [[ -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_HOST:-}" && "$FLEET_PKG_URL" == *"$CF_ACCESS_HOST"* ]]; then
    hdr=(-H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET:-}")
  fi
  if curl -fL --retry 3 "${hdr[@]+"${hdr[@]}"}" -o "$INSTALLERS/$FLEET_PKG.part" "$FLEET_PKG_URL" \
     && mv "$INSTALLERS/$FLEET_PKG.part" "$INSTALLERS/$FLEET_PKG"; then
    ok "Downloaded ${FLEET_PKG}"
    return 0
  fi
  rm -f "$INSTALLERS/$FLEET_PKG.part"
  fail "Download failed: ${FLEET_PKG} from ${FLEET_PKG_URL}"
  return 1
}

# ---------- install + verify ---------------------------------

install_pkg() {
  [[ -d /opt/orbit ]] && log "fleetd present; the pkg will upgrade/re-enroll it."
  if installer -pkg "$INSTALLERS/$FLEET_PKG" -target /; then
    ok "fleetd installed (enroll secret + URL are baked into the pkg)."
  else
    fail "Fleet pkg install failed."
    return 1
  fi

  # Restart orbit so it re-reads its config and re-enrolls
  log "Restarting orbit to pick up the new enrollment..."
  launchctl kickstart -k system/com.fleetdm.orbit 2>/dev/null || {
    launchctl unload /Library/LaunchDaemons/com.fleetdm.orbit.plist 2>/dev/null || true
    launchctl load   /Library/LaunchDaemons/com.fleetdm.orbit.plist 2>/dev/null || true
  }
  sleep 3

  if ! launchctl print system/com.fleetdm.orbit >/dev/null 2>&1; then
    fail "orbit daemon is not loaded after install — try rebooting, then re-check Fleet."
    return 1
  fi
  ok "orbit daemon is loaded."

  log "Relaunching Fleet Desktop..."
  open -a "Fleet Desktop" 2>/dev/null || true

  log "${BOLD}MANUAL CHECK:${RESET} confirm this host appears at ${FLEET_URL:-your Fleet server}"
}

fetch_pkg || exit 1
install_pkg

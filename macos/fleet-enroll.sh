#!/usr/bin/env bash
# fleet-enroll.sh — Fleetd enrollment for macOS

set -euo pipefail

# ──────────────────────────────────────────────
#  Colours
# ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ ERR]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Re-run with sudo."
}

check_vars() {
    if [[ -z "${FLEET_PKG_URL:-}" ]] || [[ -z "${FLEET_ENROLL_SECRET:-}" ]]; then
        info "FLEET_PKG_URL or FLEET_ENROLL_SECRET not set. Skipping Fleet enrollment."
        echo ""
        echo -e "${YELLOW}To enroll in Fleet, you must first build and host the agent package.${NC}"
        echo "1. Use fleetctl to create the package:"
        echo "   fleetctl package --type=pkg --fleet-url=<your-fleet-url> --enroll-secret=<your-enroll-secret>"
        echo ""
        echo "2. Host the resulting .pkg file on a web server."
        echo "3. Set the following environment variables:"
        echo "   export FLEET_PKG_URL=\"https://your.server/path/to/fleet-osquery.pkg\""
        echo "   export FLEET_ENROLL_SECRET=\"<your-enroll-secret>\""
        echo ""
        echo "Then, re-run this script."
        exit 0
    fi
}

main() {
    need_root
    check_vars

    info "Downloading Fleet agent package..."
    curl -fL -o /tmp/fleet-osquery.pkg "$FLEET_PKG_URL"

    info "Installing Fleet agent..."
    installer -pkg /tmp/fleet-osquery.pkg -target /

    info "Enrolling agent..."
    /usr/local/bin/fleet-osquery --enroll_secret="$FLEET_ENROLL_SECRET"

    ok "Fleet agent installed and enrolled."
}

main "$@"

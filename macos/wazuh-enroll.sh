#!/usr/bin/env bash
# wazuh-enroll.sh — Wazuh Agent install, enrollment, and removal (Debian/Ubuntu + macOS)
set -euo pipefail

# ──────────────────────────────────────────────
#  Config
# ──────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"
WAZUH_MAC_PKG_VER="${WAZUH_MAC_PKG_VER:-4.14.3-1}"
LOG_FILE="/tmp/${SCRIPT_NAME%.*}-$(date +%Y%m%d-%H%M%S).log"

# ──────────────────────────────────────────────
#  Colours
# ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[ ERR]${NC} $*"  | tee -a "$LOG_FILE" >&2; }
die()  { err "$*"; exit 1; }

# ──────────────────────────────────────────────
#  OS helpers
# ──────────────────────────────────────────────
is_macos() { [[ "${OSTYPE:-}" == darwin* ]]; }
is_linux() { [[ "${OSTYPE:-}" == linux*  ]]; }

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "Re-run with sudo."
}

detect_paths() {
  if is_macos; then
    OSSEC_BASE="/Library/Ossec"
  else
    OSSEC_BASE="/var/ossec"
  fi
  OSSEC_CONF="${OSSEC_BASE}/etc/ossec.conf"
  AUTH_PASS_FILE="${OSSEC_BASE}/etc/authd.pass"
  CLIENT_KEYS="${OSSEC_BASE}/etc/client.keys"
  AGENT_AUTH_BIN="${OSSEC_BASE}/bin/agent-auth"
}

normalize_host() {
  # Strip scheme + path, keep bare hostname
  echo "$1" | sed -E 's|https?://||' | cut -d'/' -f1 | cut -d':' -f1
}

get_local_hostname() {
  hostname | tr -d ' '
}

# ──────────────────────────────────────────────
#  Usage
# ──────────────────────────────────────────────
usage() {
  cat <<EOF

${CYAN}${BOLD}Wazuh Agent Enrollment Script${NC}

Usage:
  sudo ./${SCRIPT_NAME}              — interactive menu
  sudo ./${SCRIPT_NAME} -e <host> -n <agent-name> [-p <password>]
  sudo ./${SCRIPT_NAME} --remove     — remove the Wazuh agent

Options:
  -e  Enrollment host  (e.g. wazuh.example.com)
  -n  Agent name       (default: machine hostname)
  -p  Password         (optional)
  -h  Show this help
  --force              Bypass port check
  --remove             Uninstall and remove the Wazuh agent

EOF
}

# ──────────────────────────────────────────────
#  Main interactive menu (3 options)
# ──────────────────────────────────────────────
main_menu() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║      Wazuh Agent Management          ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}1)${NC} Auto Agent Install   ${BLUE}(read from ./auth file)${NC}"
  echo -e "  ${BOLD}2)${NC} Manual Agent Install ${BLUE}(enter details interactively)${NC}"
  echo -e "  ${BOLD}3)${NC} Remove Agent         ${RED}(uninstall Wazuh agent)${NC}"
  echo ""
  local choice
  read -rp "$(echo -e "${BOLD}Select [1-3]:${NC} ")" choice

  case "$choice" in
    1) _auto_install  ;;
    2) _manual_install ;;
    3) remove_agent   ;;
    *) die "Invalid selection: '${choice}'. Please choose 1, 2, or 3." ;;
  esac
}

# ──────────────────────────────────────────────
#  Auto install — reads from ./auth file
# ──────────────────────────────────────────────
_auto_install() {
  local auth_path="./auth"

  echo ""
  info "Auto Install Mode"

  # Allow user to override the auth file path
  if [[ -f "$auth_path" ]]; then
    local ans
    read -rp "$(echo -e "Found '${CYAN}./auth${NC}'. Use it? [Y/n]: ")" ans
    if [[ ! "${ans:-Y}" =~ ^[Yy]?$ ]]; then
      read -rp "Path to auth file: " auth_path
      [[ -f "$auth_path" ]] || die "File not found: $auth_path"
    fi
  else
    warn "No './auth' file found."
    read -rp "Path to auth file (or Enter to abort): " auth_path
    [[ -n "$auth_path" && -f "$auth_path" ]] || die "Auth file not found."
  fi

  read_auth_file "$auth_path"
  _run_install
}

# ──────────────────────────────────────────────
#  Manual install — interactive prompts
# ──────────────────────────────────────────────
_manual_install() {
  echo ""
  echo -e "${CYAN}${BOLD}=== Manual Agent Install ===${NC}"
  echo ""

  # ── Enrollment server ──
  echo -e "${BOLD}Enrollment Server${NC}"
  echo -e "  ${BLUE}Examples:${NC} wazuh.example.com  |  192.168.1.100"
  read -rp "  Enter enrollment host: " ENROLL_HOST
  [[ -n "${ENROLL_HOST:-}" ]] || die "Enrollment host cannot be empty."
  echo ""

  # ── Agent name ──
  local default_name
  default_name="$(get_local_hostname)"
  echo -e "${BOLD}Agent Name${NC}"
  echo -e "  ${BLUE}Default:${NC} ${default_name} (machine hostname)"
  read -rp "  Enter agent name [${default_name}]: " AGENT_NAME
  # Always fall back to local hostname if blank
  AGENT_NAME="${AGENT_NAME:-$default_name}"
  AGENT_NAME="$(echo "$AGENT_NAME" | xargs)"   # strip surrounding whitespace
  [[ -n "$AGENT_NAME" ]] || AGENT_NAME="$default_name"
  echo ""

  # ── Password ──
  echo -e "${BOLD}Enrollment Password${NC}"
  local has_pw
  read -rp "  Is a password required? [y/N]: " has_pw
  if [[ "${has_pw:-N}" =~ ^[Yy]$ ]]; then
    read -rsp "  Password: " AUTH_PASSWORD; echo ""
    [[ -n "${AUTH_PASSWORD:-}" ]] || die "Password cannot be empty when required."
  else
    AUTH_PASSWORD=""
    info "Proceeding without enrollment password."
  fi

  echo ""
  _run_install
}

# ──────────────────────────────────────────────
#  Auth file reader
#   Line 1 — enrollment host (required)
#   Line 2 — password       (optional)
#   Line 3 — agent name     (optional; defaults to hostname)
# ──────────────────────────────────────────────
read_auth_file() {
  local f="$1"
  info "Reading auth file: ${f}"

  ENROLL_HOST="$(  grep -vE '^\s*($|#)' "$f" | sed -n '1p' | xargs)"
  AUTH_PASSWORD="$(grep -vE '^\s*($|#)' "$f" | sed -n '2p' | xargs)"
  AGENT_NAME="$(   grep -vE '^\s*($|#)' "$f" | sed -n '3p' | xargs)"

  [[ -n "${ENROLL_HOST:-}" ]] || die "Auth file must have an enrollment hostname on line 1."

  # Always default to machine hostname if name not provided in file
  local default_name
  default_name="$(get_local_hostname)"
  AGENT_NAME="${AGENT_NAME:-$default_name}"
  [[ -n "$AGENT_NAME" ]] || AGENT_NAME="$default_name"

  info "  Host    : ${ENROLL_HOST}"
  info "  Agent   : ${AGENT_NAME}"
  info "  Password: $( [[ -n "${AUTH_PASSWORD:-}" ]] && echo '[PROVIDED]' || echo '[none]' )"
}

# ──────────────────────────────────────────────
#  Shared install flow
# ──────────────────────────────────────────────
_run_install() {
  local force_check="${1:-}"
  local manager
  manager="$(normalize_host "$ENROLL_HOST")"

  echo ""
  echo -e "${CYAN}${BOLD}─── Enrollment Summary ───────────────────${NC}"
  echo -e "  Manager : ${BOLD}${manager}${NC}"
  echo -e "  Agent   : ${BOLD}${AGENT_NAME}${NC}"
  echo -e "  Password: $( [[ -n "${AUTH_PASSWORD:-}" ]] && echo '[PROVIDED]' || echo '[none]' )"
  echo -e "${CYAN}${BOLD}──────────────────────────────────────────${NC}"
  echo ""

  local confirm
  read -rp "$(echo -e "${BOLD}Proceed with installation? [Y/n]:${NC} ")" confirm
  [[ "${confirm:-Y}" =~ ^[Yy]?$ ]] || die "Installation cancelled by user."

  check_ports    "$manager" "$force_check"
  stop_existing_agent

  if is_linux; then
    install_linux
  elif is_macos; then
    install_macos
  else
    die "Unsupported OS: ${OSTYPE}"
  fi

  write_authd_pass    "${AUTH_PASSWORD:-}"
  set_manager_address "$manager"
  enroll_agent        "$manager" "$AGENT_NAME" "${AUTH_PASSWORD:-}"
  start_agent
  verify_enrollment
}

# ──────────────────────────────────────────────
#  Remove agent
# ──────────────────────────────────────────────
remove_agent() {
  detect_paths

  echo ""
  echo -e "${RED}${BOLD}=== Remove Wazuh Agent ===${NC}"
  echo ""

  if [[ ! -d "$OSSEC_BASE" ]]; then
    warn "No Wazuh agent installation found at ${OSSEC_BASE}."
    return 0
  fi

  local confirm
  read -rp "$(echo -e "${RED}${BOLD}This will fully uninstall the Wazuh agent. Continue? [y/N]:${NC} ")" confirm
  [[ "${confirm:-N}" =~ ^[Yy]$ ]] || { info "Removal cancelled."; return 0; }

  info "Stopping wazuh-agent service…"
  if is_macos; then
    "$OSSEC_BASE/bin/wazuh-control" stop &>/dev/null || true
    launchctl unload /Library/LaunchDaemons/com.wazuh.agent.plist 2>/dev/null || true
  else
    systemctl stop    wazuh-agent &>/dev/null || true
    systemctl disable wazuh-agent &>/dev/null || true
  fi

  if is_linux; then
    info "Removing wazuh-agent package…"
    if command -v apt-get &>/dev/null; then
      apt-get purge -y wazuh-agent
      apt-get autoremove -y
    elif command -v yum &>/dev/null; then
      yum remove -y wazuh-agent
    elif command -v dnf &>/dev/null; then
      dnf remove -y wazuh-agent
    else
      warn "Package manager not detected. Removing files manually."
    fi
  elif is_macos; then
    info "Removing Wazuh macOS package files…"
    # macOS pkg uninstall — remove known paths
    pkgutil --forget com.wazuh.pkg.wazuh-agent 2>/dev/null || true
  fi

  # Remove residual directories
  if [[ -d "$OSSEC_BASE" ]]; then
    info "Removing residual files at ${OSSEC_BASE}…"
    rm -rf "$OSSEC_BASE"
  fi

  # Clean up APT repo on Linux
  if is_linux; then
    rm -f /etc/apt/sources.list.d/wazuh.list
    rm -f /usr/share/keyrings/wazuh.gpg
    apt-get update -qq &>/dev/null || true
    info "Wazuh APT repository removed."
  fi

  ok "Wazuh agent has been fully removed."
}

# ──────────────────────────────────────────────
#  Network check
# ──────────────────────────────────────────────
check_ports() {
  local host="$1"
  local force_check="${2:-}"
  if ! command -v nc &>/dev/null; then
    warn "nc not found; skipping port check."
    return
  fi
  info "Checking connectivity to ${host} on ports 1514 / 1515…"
  local port_ok_count=0
  local port
  for port in 1515 1514; do
    if nc -z -w3 "$host" "$port" &>/dev/null; then
      ok "  ${host}:${port} — reachable"
      ((port_ok_count++))
    else
      warn "  ${host}:${port} — unreachable"
    fi
  done

  if [[ $port_ok_count -eq 0 ]]; then
    if [[ "$force_check" == "--force" ]]; then
      warn "Both ports are unreachable, but --force was provided. Continuing."
    else
      err "Both agent ports (1515/tcp, 1514/tcp) are unreachable."
      cat <<'EOF'

  This is often caused by one of the following:
    1. A firewall on this machine, the network, or the server is blocking
       connections on these ports.
    2. The manager hostname points to a Cloudflare (or other) proxy that
       only tunnels HTTP/S traffic. The Wazuh agent requires a direct
       connection to its manager on these TCP ports.

  Action:
    - For cloud-hosted managers (like Wazuh Cloud or a self-hosted instance
      behind a proxy), ensure the hostname you are using is a DNS-only
      (grey-cloud) record that resolves directly to the manager's public IP.
    - For on-premise managers, use the manager's LAN IP address.
    - If you are certain the host is reachable and this check is a false
      negative, re-run with the '--force' flag to bypass it.

EOF
      die "Port check failed. Use --force to override."
    fi
  fi
}

# ──────────────────────────────────────────────
#  Stop existing agent
# ──────────────────────────────────────────────
stop_existing_agent() {
  detect_paths
  [[ -d "$OSSEC_BASE" ]] || return 0
  warn "Existing agent installation found at ${OSSEC_BASE} — stopping…"
  if is_macos; then
    "$OSSEC_BASE/bin/wazuh-control" stop &>/dev/null || true
  else
    systemctl stop wazuh-agent &>/dev/null || true
  fi
}

# ──────────────────────────────────────────────
#  Install — Linux (Debian / Ubuntu)
# ──────────────────────────────────────────────
_linux_install_deps() {
  info "Installing dependencies…"
  apt-get update -qq
  apt-get install -y curl gnupg ca-certificates netcat-openbsd
}

_linux_add_repo() {
  info "Adding Wazuh APT repository…"
  curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
    | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list
  apt-get update -qq
  ok "Wazuh repository configured."
}

install_linux() {
  _linux_install_deps
  apt-cache show wazuh-agent &>/dev/null || _linux_add_repo
  info "Installing wazuh-agent package…"
  apt-get install -y wazuh-agent
  ok "wazuh-agent installed."
}

# ──────────────────────────────────────────────
#  Install — macOS
# ──────────────────────────────────────────────
install_macos() {
  info "Installing wazuh-agent (macOS)…"
  local arch; arch="$(uname -m)"
  local flavor
  case "$arch" in
    arm64)  flavor="arm64"   ;;
    x86_64) flavor="intel64" ;;
    *)      die "Unsupported macOS architecture: ${arch}" ;;
  esac

  local url="https://packages.wazuh.com/4.x/macos/wazuh-agent-${WAZUH_MAC_PKG_VER}.${flavor}.pkg"
  info "Downloading: ${url}"
  curl -fL -o /tmp/wazuh-agent.pkg "$url"
  installer -pkg /tmp/wazuh-agent.pkg -target /
  rm -f /tmp/wazuh-agent.pkg
  ok "wazuh-agent installed."
}

# ──────────────────────────────────────────────
#  Configure
# ──────────────────────────────────────────────
write_authd_pass() {
  local pw="$1"
  detect_paths
  if [[ -z "$pw" ]]; then
    info "No password — skipping authd.pass."
    return
  fi
  info "Writing ${AUTH_PASS_FILE}…"
  mkdir -p "$(dirname "$AUTH_PASS_FILE")"
  printf '%s' "$pw" > "$AUTH_PASS_FILE"
  chmod 640 "$AUTH_PASS_FILE"
  chown root:wazuh "$AUTH_PASS_FILE" 2>/dev/null \
    || chown root:ossec "$AUTH_PASS_FILE" 2>/dev/null \
    || true
  ok "authd.pass written."
}

set_manager_address() {
  local manager="$1"
  detect_paths
  [[ -f "$OSSEC_CONF" ]] || die "Missing ${OSSEC_CONF} — agent install may have failed."

  info "Setting manager address → ${manager}"
  perl -0777 -i \
    -pe 's|<address>[^<]*</address>|<address>'"$manager"'</address>|s' \
    "$OSSEC_CONF"

  grep -q "<address>${manager}</address>" "$OSSEC_CONF" \
    && ok "Manager address updated in ossec.conf." \
    || warn "Could not update <address> automatically — check ${OSSEC_CONF} manually."
}

enroll_agent() {
  local manager="$1" agent="$2" pw="${3:-}"
  detect_paths
  [[ -x "$AGENT_AUTH_BIN" ]] || { warn "agent-auth not found; skipping explicit enrollment."; return; }

  info "Running agent-auth enrollment (agent name: '${agent}')…"

  if [[ -n "$pw" ]]; then
    local tmp_pass
    tmp_pass="$(mktemp)"
    printf '%s' "$pw" > "$tmp_pass"
    chmod 600 "$tmp_pass"
    "$AGENT_AUTH_BIN" -m "$manager" -A "$agent" -f "$tmp_pass" 2>>"$LOG_FILE" || true
    rm -f "$tmp_pass"
  else
    "$AGENT_AUTH_BIN" -m "$manager" -A "$agent" 2>>"$LOG_FILE" || true
  fi

  ok "agent-auth enrollment complete."
}

# ──────────────────────────────────────────────
#  Start agent
# ──────────────────────────────────────────────
start_agent() {
  detect_paths
  info "Starting wazuh-agent…"
  if is_macos; then
    "$OSSEC_BASE/bin/wazuh-control" restart
    sleep 2
    pgrep -f wazuh-agentd &>/dev/null \
      && ok "Agent is running." \
      || die "Agent failed to start — check ${LOG_FILE}"
  else
    systemctl enable --now wazuh-agent
    sleep 2
    systemctl is-active --quiet wazuh-agent \
      && ok "Agent is running." \
      || die "Agent failed to start — check ${LOG_FILE}"
  fi
}

# ──────────────────────────────────────────────
#  Verify enrollment
# ──────────────────────────────────────────────
verify_enrollment() {
  detect_paths
  info "Verifying enrollment (client.keys)…"
  sleep 4

  if [[ -s "$CLIENT_KEYS" ]]; then
    ok "Enrolled: $(head -n1 "$CLIENT_KEYS")"
    echo ""
    ok "=== Done. Agent enrolled and running. ==="
    echo -e "\n${CYAN}Log file:${NC} ${LOG_FILE}\n"
    return 0
  fi

  err "client.keys is empty — enrollment may have failed."
  cat <<EOF

${YELLOW}=== Troubleshooting ===${NC}

Common causes:
  1. Wrong password         — verify and re-run
  2. Duplicate agent name   — remove old agent on manager or choose a different name
  3. Port blocked           — ensure outbound 1515/tcp and 1514/tcp are open
  4. DNS / routing issue    — confirm the manager hostname resolves correctly

Diagnostic commands:
EOF

  if is_linux; then
    cat <<EOF
  sudo journalctl -u wazuh-agent -n 100 --no-pager
  sudo tail -n 100 ${OSSEC_BASE}/logs/ossec.log
EOF
  else
    cat <<EOF
  sudo tail -n 100 ${OSSEC_BASE}/logs/ossec.log
EOF
  fi

  echo -e "\n${CYAN}Full install log:${NC} ${LOG_FILE}\n"
  exit 1
}

# ──────────────────────────────────────────────
#  Argument parsing (non-interactive mode)
# ──────────────────────────────────────────────
parse_args() {
  # Handle --remove and --force flags
  local force_flag=""
  for arg in "$@"; do
    if [[ "$arg" == "--remove" ]]; then
      need_root
      detect_paths
      remove_agent
      exit 0
    elif [[ "$arg" == "--force" ]]; then
      force_flag="--force"
    fi
  done

  if [[ $# -eq 0 ]]; then
    main_menu
    return
  fi

  ENROLL_HOST=""; AGENT_NAME=""; AUTH_PASSWORD=""

  local opt
  while getopts ":e:n:p:h" opt; do
    case "$opt" in
      e) ENROLL_HOST="$OPTARG" ;;
      n) AGENT_NAME="$OPTARG"  ;;
      p) AUTH_PASSWORD="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "Option -${OPTARG} requires an argument." ;;
      *) usage; die "Unknown option: -${OPTARG}" ;;
    esac
  done

  [[ -n "${ENROLL_HOST:-}" ]] || { usage; die "-e (enrollment host) is required."; }

  # Default agent name to hostname if not supplied via -n
  local default_name
  default_name="$(get_local_hostname)"
  AGENT_NAME="${AGENT_NAME:-$default_name}"
  [[ -n "$AGENT_NAME" ]] || AGENT_NAME="$default_name"

  [[ -z "${AUTH_PASSWORD:-}" ]] && info "No password supplied — enrolling without auth."

  _run_install "$force_flag"
}

# ──────────────────────────────────────────────
#  Entry point
# ──────────────────────────────────────────────
main() {
  need_root
  echo -e "\n${CYAN}Log file:${NC} ${LOG_FILE}\n"
  parse_args "$@"
}

main "$@"

#!/usr/bin/env bash
# deploykit bootstrap — clone the kit, prepare config, and launch OS setup.
#   curl -fsSL https://raw.githubusercontent.com/SCVC/deploykit/main/install.sh | bash
set -euo pipefail

REPO="https://github.com/SCVC/deploykit.git"
DEST="${DEPLOYKIT_DIR:-$HOME/deploykit}"
BOLD=$(tput bold 2>/dev/null || true); NC=$(tput sgr0 2>/dev/null || true)
say() { printf '%s==>%s %s\n' "$BOLD" "$NC" "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- OS guard ---
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) die "Windows detected — run the PowerShell bootstrap instead:  irm https://raw.githubusercontent.com/SCVC/deploykit/main/install.ps1 | iex" ;;
esac
command -v git >/dev/null 2>&1 || die "git is required (install Xcode Command Line Tools or your package manager's git)."

# --- fetch / update the kit ---
if [ -d "$DEST/.git" ]; then
  say "Updating existing kit at $DEST"
  git -C "$DEST" pull --ff-only
else
  say "Cloning deploykit → $DEST"
  git clone --depth 1 "$REPO" "$DEST"
fi
cd "$DEST"

# --- config ---
if [ ! -f config.env ]; then
  cp config.env.example config.env
  say "Created config.env from the template."
  printf '    %sEdit %s/config.env with your org values, then re-run.%s\n' "$BOLD" "$DEST" "$NC"
  printf '    (RustDesk key, Chrome CBCM tokens, Wazuh/Fleet hosts.)\n'
  exit 0
fi

# --- launch setup ---
if [ "$OS" = macos ] && [ -f macos/setup.sh ]; then
  say "Launching macOS setup…"
  chmod +x macos/setup.sh
  exec bash macos/setup.sh "$@"
fi
say "Kit ready at $DEST. Run the setup for your platform under macos/ or windows/."

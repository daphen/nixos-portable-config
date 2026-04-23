#!/usr/bin/env bash
# Bootstrap the portable dev environment on a fresh Linux container/server.
#
# Run on any Linux host with network access:
#   curl -L https://raw.githubusercontent.com/daphen/nixos-portable-config/main/bootstrap.sh | bash
#
# What this does:
#   1. Installs Nix (multi-user) via the Determinate installer if missing
#   2. Enables flakes + nix-command
#   3. Runs home-manager switch against homeConfigurations.daphen-remote
#      from github:daphen/nixos-portable-config
#
# After: fish, nvim, starship, git, claude-code, opencode, and the CLI toolkit
# are installed and ready. Plugins for nvim are pre-installed (baked into the
# Nix store) so the first `nvim` launch is instant.
#
# Authentication (one-time per host, not automated):
#   - 1Password: op signin
#   - git: set up SSH key or use ssh-agent forwarding
#   - claude / opencode: first-run interactive or env vars

set -euo pipefail

readonly FLAKE_URL="${FLAKE_URL:-github:daphen/nixos-portable-config}"
readonly HM_ATTR="${HM_ATTR:-daphen-remote}"

info() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m==>\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m==>\033[0m %s\n" "$*" >&2; exit 1; }

# ── 0. Install OS-level prerequisites if missing ─────────────────────────
# The Nix installer needs curl, xz-utils, and ca-certificates. Bare container
# images don't ship them. Handle Debian/Ubuntu and RHEL/Fedora/Alpine.
install_prereqs() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v xz   >/dev/null 2>&1 || missing+=(xz-utils)
  [ -d /etc/ssl/certs ] || missing+=(ca-certificates)

  if [ ${#missing[@]} -eq 0 ]; then
    return 0
  fi

  info "Installing OS prerequisites: ${missing[*]}"

  if command -v apt-get >/dev/null 2>&1; then
    # Debian / Ubuntu
    if [ "$(id -u)" = "0" ]; then
      apt-get update >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates
    else
      sudo apt-get update >/dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates
    fi
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL
    local pkgs=()
    for p in "${missing[@]}"; do
      case "$p" in
        xz-utils) pkgs+=(xz) ;;
        *)        pkgs+=("$p") ;;
      esac
    done
    if [ "$(id -u)" = "0" ]; then dnf install -y "${pkgs[@]}"
    else sudo dnf install -y "${pkgs[@]}"
    fi
  elif command -v apk >/dev/null 2>&1; then
    # Alpine
    local pkgs=()
    for p in "${missing[@]}"; do
      case "$p" in
        xz-utils) pkgs+=(xz) ;;
        *)        pkgs+=("$p") ;;
      esac
    done
    if [ "$(id -u)" = "0" ]; then apk add --no-cache "${pkgs[@]}"
    else sudo apk add --no-cache "${pkgs[@]}"
    fi
  else
    fail "No supported package manager (apt/dnf/apk) found. Install these manually first: ${missing[*]}"
  fi
}

install_prereqs

# ── 1. Install Nix if missing ────────────────────────────────────────────
if ! command -v nix >/dev/null 2>&1; then
  info "Nix not found — installing via the Determinate installer"

  # Detect if systemd is running as init. Check PID 1 directly — merely
  # having /run/systemd/system/ isn't enough (Ubuntu images ship the dir
  # even when running under bash as PID 1).
  pid1_comm=""
  if [ -r /proc/1/comm ]; then
    pid1_comm=$(cat /proc/1/comm 2>/dev/null || true)
  fi
  if [ "$pid1_comm" = "systemd" ]; then
    INIT_FLAG=""
  else
    info "No systemd init detected (PID 1: ${pid1_comm:-unknown}) — installing in no-daemon mode (--init none)"
    INIT_FLAG="--init none"
  fi

  # Without systemd we need to specify the platform (linux) before --init none.
  # With systemd, the installer auto-detects and doesn't need the platform arg.
  # shellcheck disable=SC2086
  if [ -n "$INIT_FLAG" ]; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
      | sh -s -- install linux $INIT_FLAG --no-confirm
  else
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
      | sh -s -- install --no-confirm
  fi

  # Source the nix profile into the current shell so subsequent commands see it
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    # Single-user install (when --init none is used) sources a different file
    # shellcheck disable=SC1091
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi

  if ! command -v nix >/dev/null 2>&1; then
    # Fallback: add the install locations to PATH directly
    export PATH="/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$PATH"
  fi

  if ! command -v nix >/dev/null 2>&1; then
    fail "Nix install appeared to succeed but 'nix' is still not on PATH. Open a new shell and re-run."
  fi
else
  info "Nix already installed: $(nix --version)"
fi

# ── 2. Ensure flakes + nix-command are enabled for this invocation ────────
export NIX_CONFIG="experimental-features = nix-command flakes"

# ── 3. Run home-manager switch ────────────────────────────────────────────
# Home-manager's activation scripts rely on USER and HOME being set — containers
# often launch with neither.
export USER="${USER:-$(whoami)}"
export HOME="${HOME:-/root}"
info "USER=${USER} HOME=${HOME}"

info "Running home-manager switch --flake ${FLAKE_URL}#${HM_ATTR}"
info "(first run on a new host downloads ~1-2 GB from the Nix binary cache)"

# --impure allows home.username/homeDirectory to come from env vars.
nix run home-manager/master -- switch \
  --flake "${FLAKE_URL}#${HM_ATTR}" \
  --impure \
  -b backup \
  "$@"

# ── 4. Make home-manager's profile bin discoverable by the parent shell ──
# HM installs packages under $HOME/.local/state/nix/profile/bin (newer) or
# $HOME/.nix-profile/bin. Write a .bashrc snippet so new shells pick them up
# automatically, AND print instructions for the current shell since env
# changes from inside a piped script can't propagate back to the caller.
for profile_dir in \
  "$HOME/.local/state/nix/profile/bin" \
  "$HOME/.nix-profile/bin" \
  "/nix/var/nix/profiles/default/bin"; do
  case ":${PATH:-}:" in
    *":${profile_dir}:"*) ;;
    *) PATH="${profile_dir}:${PATH:-}" ;;
  esac
done
export PATH

# Persist the PATH change to bashrc + bash_profile so subsequent shells see it
rc_snippet='# Added by nixos-portable-config bootstrap — home-manager profile bins'
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$rc" ] || touch "$rc"
  if ! grep -qF "$rc_snippet" "$rc" 2>/dev/null; then
    {
      echo ""
      echo "$rc_snippet"
      echo 'export PATH="$HOME/.local/state/nix/profile/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"'
    } >> "$rc"
  fi
done

info "Bootstrap complete."
info ""
info "Next steps (one-time per host):"
info "  1) Auth 1Password:    op signin"
info "  2) Set up git:         ssh-add -l  # ensure an SSH key is forwarded, or add one"
info "  3) Auth claude/opencode on first run"
info ""
info "Type 'fish' to enter the shell. 'nvim' opens with all plugins pre-installed."
info "(If fish isn't found: open a new shell, or run 'exec bash -l' to reload PATH.)"

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
# After: fish, nvim, starship, git, delta, and the CLI toolkit are installed
# and ready. Plugins for nvim are pre-installed (baked into the Nix store) so
# the first `nvim` launch is instant.
#
# AI CLIs (claude-code, codex, opencode) and 1Password CLI are NOT installed
# by this config — lovbox-style containers ship the agent CLIs pre-baked, and
# we don't use `op` on remotes. If you need them elsewhere, `nix run` or add
# them back to home-modules/remote.nix.
#
# Authentication (one-time per host, not automated):
#   - git: set up SSH key or use ssh-agent forwarding

set -euo pipefail

# Note on `curl | bash`: subprocesses inherit the curl pipe as stdin. If a
# subprocess reads stdin it can eat the rest of the script before bash gets
# to it. Don't redirect bash's own stdin globally — bash reads the script
# from FD 0, and redirecting FD 0 would EOF the script. Instead, put
# `</dev/null` on individual subprocess calls that might read stdin
# (currently the home-manager invocation in hm_switch).

readonly FLAKE_URL="${FLAKE_URL:-github:daphen/nixos-portable-config}"

# Pick the home-manager attr matching the current arch. The flake exposes
# daphen-remote (x86_64) and daphen-remote-aarch64 (lovbox sandboxes are ARM).
default_hm_attr() {
  case "$(uname -m)" in
    x86_64)        echo "daphen-remote" ;;
    aarch64|arm64) echo "daphen-remote-aarch64" ;;
    *)             echo "daphen-remote" ;;
  esac
}
readonly HM_ATTR="${HM_ATTR:-$(default_hm_attr)}"

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

# Home-manager bundles its packages into a single `home-manager-path` profile
# entry. If the user's existing nix profile contains packages whose files
# overlap (e.g. lovbox sandbox images ship man-db, openssh, git-minimal as
# individual profile entries), the install fails with "An existing package
# already provides …".
#
# Rather than maintain a brittle hand-curated strip list, we run the switch in
# a retry loop: capture the conflict error, parse the existing package name,
# remove it, retry. Bounded to 8 attempts to avoid infinite loops if the
# error format ever changes.
#
# --impure allows home.username/homeDirectory to come from env vars.
# -b backup renames any pre-existing dotfile (e.g. lovbox's stock .gitconfig).
# --refresh ignores the 1h flake cache so pushes are picked up immediately.
hm_switch() {
  # </dev/null prevents nix/home-manager from consuming the rest of this
  # script when bootstrap.sh is invoked via `curl … | bash`. Without this,
  # subprocesses inherit the curl pipe as stdin and may eat lines we still
  # need to read (so the retry loop below never executes).
  nix run home-manager/master -- switch \
    --flake "${FLAKE_URL}#${HM_ATTR}" \
    --impure --refresh -b backup "$@" </dev/null
}

attempt=1
max_attempts=8
while [ $attempt -le $max_attempts ]; do
  log_file="$(mktemp -t hm-switch.XXXXXX)"
  # `set -e` is suppressed inside the `if` condition, so a failing switch
  # falls through to the conflict-handling branch.
  if hm_switch "$@" 2>&1 | tee "$log_file"; then
    rm -f "$log_file"
    break
  fi

  # Extract the *store path* of the conflicting "existing" package from
  # the error block. Removing by store path is more reliable than removing
  # by name: nix profile entries don't always have the name you'd guess
  # (the error tells the user "nix profile remove home-manager-path" but
  # that name may not match an actual profile entry).
  #
  # Error format:
  #   error: An existing package already provides the following file:
  #
  #            "/nix/store/HASH-NAME/lib/tmpfiles.d/foo.conf"
  #
  # We want /nix/store/HASH-NAME (truncated at the next "/" so we drop the
  # trailing file path). `|| true` on each pipeline step so a parse miss
  # doesn't trip set -euo pipefail.
  conflict_path=$(grep -A2 "An existing package already provides" "$log_file" 2>/dev/null \
    | grep -oE '/nix/store/[a-z0-9]{32}-[^/"[:space:]]+' | head -1 || true)

  if [ -z "$conflict_path" ]; then
    warn "home-manager switch failed and no parseable conflict — aborting."
    rm -f "$log_file"
    exit 1
  fi

  # Derive a readable name for logging only (HASH-NAME-VERSION -> NAME).
  base=${conflict_path##*/}
  stripped=${base#*-}
  conflict_pkg=$(echo "$stripped" | sed -E 's/-[0-9].*$//')

  info "Conflict on attempt ${attempt}: removing '${conflict_pkg}' (${conflict_path}) from nix profile"

  # Try by store path first (most reliable), then by name as fallback.
  if ! nix profile remove "$conflict_path" 2>&1 | tee -a "$log_file"; then
    nix profile remove "$conflict_pkg" 2>&1 | tee -a "$log_file" || true
  fi

  # Sanity check: did the conflict path actually leave the profile? If
  # the remove silently no-op'd we'll just loop forever — bail with a
  # clear message instead.
  if nix profile list 2>/dev/null | grep -qF "$conflict_path"; then
    warn "nix profile still references ${conflict_path} after remove."
    warn "Profile state:"
    nix profile list 2>&1 | head -40 >&2
    rm -f "$log_file"
    exit 1
  fi

  rm -f "$log_file"
  attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
  fail "home-manager switch failed after ${max_attempts} conflict-removal attempts."
fi

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

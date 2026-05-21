#!/usr/bin/env bash
# Bootstrap daphen's portable dev env on a fresh Linux container/server.
#
# Run on any Linux host with Nix installed:
#   curl -L https://raw.githubusercontent.com/daphen/nixos-portable-config/main/bootstrap.sh | bash
#
# What this does:
#   - Installs Nix (multi-user) via the Determinate installer if missing.
#   - Writes ~/.local/bin/dev-env: a one-line wrapper around
#     `nix run github:daphen/nixos-portable-config#daphen-env`.
#
# No home-manager activation. No nix-profile installs. No conflict with
# whatever the host image pre-populates. The dev env is a transient nix
# closure: built on first run, cached in the Nix store, and torn down
# automatically when you exit the shell.
#
# After: run `dev-env` to enter the environment. To auto-launch on every
# SSH login, append the line `exec ~/.local/bin/dev-env` to ~/.bash_profile
# (or .bashrc, for interactive non-login shells).

set -euo pipefail

readonly FLAKE_URL="${FLAKE_URL:-github:daphen/nixos-portable-config}"
readonly LAUNCHER="$HOME/.local/bin/dev-env"

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
    if [ "$(id -u)" = "0" ]; then
      apt-get update >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates
    else
      sudo apt-get update >/dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" ca-certificates
    fi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${missing[@]}"
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add --no-cache "${missing[@]}" ca-certificates
  else
    warn "No recognized package manager — assuming prerequisites are already present."
  fi
}

# ── 1. Install Nix if missing ────────────────────────────────────────────
install_nix() {
  install_prereqs

  if command -v nix >/dev/null 2>&1; then
    info "Nix already installed: $(nix --version)"
    return 0
  fi

  info "Installing Nix via the Determinate installer…"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install linux --no-confirm --init none

  # The installer writes /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  # for daemon-mode installs. Source it so `nix` is on PATH for the rest of
  # this script. For single-user installs, ~/.nix-profile/etc/profile.d/nix.sh.
  for f in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh" ; do
    [ -r "$f" ] && . "$f" || true
  done

  if ! command -v nix >/dev/null 2>&1; then
    export PATH="/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$PATH"
  fi

  if ! command -v nix >/dev/null 2>&1; then
    fail "Nix install appeared to succeed but 'nix' is still not on PATH. Open a new shell and re-run."
  fi
}

install_nix

# ── 2. Ensure flakes + nix-command are enabled for this invocation ───────
export NIX_CONFIG="experimental-features = nix-command flakes"

# ── 3. Write ~/.local/bin/dev-env ────────────────────────────────────────
info "Installing launcher: $LAUNCHER"
mkdir -p "$(dirname "$LAUNCHER")"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# daphen's ephemeral dev env. First run builds the closure (~2 min on
# fresh hosts); subsequent runs are instant via Nix store cache.
# --refresh ensures pushes to the flake are picked up without waiting on
# the 1h registry cache.
exec nix run --refresh ${FLAKE_URL}#daphen-env -- "\$@"
EOF
chmod +x "$LAUNCHER"

# ── 4. Make sure ~/.local/bin is on PATH for new shells ──────────────────
# Most distros' default .bashrc puts it on PATH if the dir exists. We just
# created it, so make sure new shells see it.
for rc in "$HOME/.bash_profile" "$HOME/.bashrc"; do
  [ -e "$rc" ] || continue
  if ! grep -q 'PATH=.*\.local/bin' "$rc" 2>/dev/null; then
    {
      echo ''
      echo '# Added by nixos-portable-config bootstrap'
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$rc"
    info "Appended PATH snippet to $(basename "$rc")"
  fi
done

info "Done. Run 'dev-env' to enter your dev environment."
info "Tip: add 'exec ~/.local/bin/dev-env' to ~/.bash_profile to auto-launch on SSH."

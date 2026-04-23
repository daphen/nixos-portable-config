# nixos-portable-config

My portable dev environment as a Nix flake — deployable to any Linux host (containers, remote servers, fresh VMs) with a single bootstrap command.

Not actually NixOS-specific, despite the name. It just uses Nix + home-manager. Runs on any distro where Nix can be installed.

## What you get

- **fish** with starship prompt + fzf/zoxide/worktrunk integrations
- **nvim** (bundled as a standalone derivation via `wrapper-modules` + `lz.n`) — ~45 plugins + LSPs + formatters pre-installed, so first launch is instant
- **git** with my config
- **CLI toolkit**: ripgrep, fd, bat, jq, gh, delta, fastfetch
- **AI CLIs**: claude-code, opencode
- **Auth**: 1password-cli

Intentionally excluded: anything with a GUI (terminal emulators, browsers, desktop apps, window manager), hardware-specific system packages, anything that needs a display server.

## Usage

### One-command bootstrap on a fresh host

```bash
curl -L https://raw.githubusercontent.com/daphen/nixos-portable-config/main/bootstrap.sh | bash
```

That installs Nix (if missing), enables flakes, and runs `home-manager switch --flake github:daphen/nixos-portable-config#daphen-remote`. Takes ~2 minutes on a reasonable connection.

### Run just nvim anywhere

```bash
nix run github:daphen/nixos-portable-config#neovim
```

### If Nix is already installed

```bash
nix run home-manager/master -- switch \
  --flake github:daphen/nixos-portable-config#daphen-remote
```

## After bootstrap

Three one-time auth steps (can't be automated — they involve secrets or interactivity):

1. **1Password**: `op signin` (wherever you pull tokens from)
2. **Git SSH**: forward your agent (`ssh -A ...`) or add a key
3. **Claude / opencode**: first run prompts for auth, or export API keys

Type `fish` to enter your shell. `nvim` opens fully configured.

## Structure

```
.
├── flake.nix                     # inputs + outputs (packages.neovim, homeConfigurations.daphen-remote)
├── bootstrap.sh                  # one-command installer
├── packages/neovim/              # standalone bundled nvim
│   ├── default.nix               # wrapper-modules + lz.n + plugin list + LSPs
│   └── lua/                      # nvim config (init.lua, core/, plugins/, ai-tracker/)
└── home-modules/
    └── remote.nix                # the portable HM config
```

## Customization

Dotfiles are consumed as a flake input (`inputs.dotfiles = github:daphen/dotfiles`). To swap in your own fork:

```nix
# flake.nix
dotfiles = {
  url = "github:YOUR-USERNAME/YOUR-DOTFILES-REPO";
  flake = false;
};
```

Then update the paths in `home-modules/remote.nix` to match your dotfile layout.

The nvim plugin list lives in `packages/neovim/default.nix` (`start` for always-loaded, `opt` for lz.n-lazy-loaded). Plugin configs are in `packages/neovim/lua/plugins/*.lua` using the lz.n spec format.

## Updating

Pull the latest of everything:

```bash
# Bump flake inputs
nix flake update

# Re-apply
home-manager switch --flake github:daphen/nixos-portable-config#daphen-remote
```

Or, if you've forked and want to update dotfiles only:

```bash
nix flake update dotfiles
home-manager switch --flake .#daphen-remote
```

## Relation to my main NixOS config

This repo is the *portable* half — designed to deploy to ephemeral hosts. My full local NixOS setup (window manager, hardware tuning, theme system) lives in [`daphen/nixos-config`](https://github.com/daphen/nixos-config) and uses a different wiring (`mkOutOfStoreSymlink` to `~/dotfiles/` for live-edit). Both read from the same dotfiles repo.

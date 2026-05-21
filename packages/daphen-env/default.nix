{ pkgs, inputs, neovim }:
# A single ephemeral dev environment: all CLI tools + dotfile configs
# packaged into a script that sets up env vars and execs fish. Designed for
# `nix run github:daphen/nixos-portable-config#daphen-env`, with no profile
# installs, no home-manager, and no per-host state — disconnect from a
# sandbox and nothing is left behind.

let
  dotfiles = inputs.dotfiles;

  # Build a read-only config tree in the Nix store and point XDG_CONFIG_HOME
  # at it. Tools find their configs via well-known relative paths from
  # XDG_CONFIG_HOME (fish/, starship/, etc.). For tools that don't honor
  # XDG_CONFIG_HOME, we set tool-specific env vars explicitly below.
  configRoot = pkgs.runCommand "daphen-env-config" { } ''
    mkdir -p $out/fish $out/starship

    # Fish: config.fish, conf.d, functions, completions
    cp ${dotfiles}/fish/.config/fish/config.fish     $out/fish/config.fish
    cp -r ${dotfiles}/fish/.config/fish/conf.d       $out/fish/conf.d
    cp -r ${dotfiles}/fish/.config/fish/functions    $out/fish/functions
    cp -r ${dotfiles}/fish/.config/fish/completions  $out/fish/completions
    cp ${dotfiles}/fish/.config/fish/fish_plugins    $out/fish/fish_plugins

    # Starship prompt
    cp ${dotfiles}/starship/.config/starship/starship.toml $out/starship/starship.toml

    # Git: write a minimal gitconfig pointing delta as the pager, set
    # identity from dotfiles, skip the includeIf entries (they reference
    # absolute paths under ~/personal etc. that don't exist on sandboxes).
    cat > $out/gitconfig <<'GITEOF'
    [init]
        defaultBranch = main
    [fetch]
        prune = true
    [user]
        name = David Karlsson
        email = davidkarlssson@gmail.com
    [pull]
        rebase = true
    [core]
        pager = delta
    [interactive]
        diffFilter = delta --color-only
    [delta]
        navigate = true
        light = false
        side-by-side = true
    [merge]
        conflictstyle = diff3
    [diff]
        colorMoved = default
    GITEOF
  '';

  # Tools that should be on PATH inside the dev-env shell. writeShellApplication
  # adds runtimeInputs to PATH for the wrapper script's execution; we `exec
  # fish` from the wrapper, so fish inherits the modified PATH.
  tools = with pkgs; [
    neovim
    fish
    git
    starship
    fzf
    zoxide
    ripgrep
    fd
    bat
    jq
    gh
    delta
    fastfetch
    openssh
  ];

in pkgs.writeShellApplication {
  name = "daphen-env";
  runtimeInputs = tools;
  # writeShellApplication uses `set -euo pipefail`. Allow unset vars when
  # sourcing fish (fish's loader checks several env vars optionally).
  text = ''
    set +u
    export XDG_CONFIG_HOME="${configRoot}"
    export GIT_CONFIG_GLOBAL="${configRoot}/gitconfig"
    export STARSHIP_CONFIG="${configRoot}/starship/starship.toml"
    export EDITOR="nvim"
    export VISUAL="nvim"
    exec ${pkgs.fish}/bin/fish -l "$@"
  '';
}

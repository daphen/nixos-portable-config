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

    # Fish: config.fish, conf.d, functions, fish_plugins (completions/ isn't
    # in the dotfiles repo — fish autoloads built-in completions from the
    # Nix package itself). Copy each optionally so a missing file doesn't
    # tank the whole build.
    for src in config.fish fish_plugins; do
      if [ -e "${dotfiles}/fish/.config/fish/$src" ]; then
        cp "${dotfiles}/fish/.config/fish/$src" "$out/fish/$src"
      fi
    done
    for dir in conf.d functions completions; do
      if [ -d "${dotfiles}/fish/.config/fish/$dir" ]; then
        cp -r "${dotfiles}/fish/.config/fish/$dir" "$out/fish/$dir"
      fi
    done

    # Starship: minimal sandbox prompt. We deliberately don't inherit the
    # dotfiles config — that's tuned for full local context (git branch,
    # node/bun/rust versions, etc.) which is mostly noise on a sandbox
    # where you SSH in to do a focused task. Just the directory + prompt
    # char. Same config for both theme_mode values (the writer below picks
    # one regardless).
    for variant in dark light; do
      cat > "$out/starship/$variant.toml" <<'SEOF'
    add_newline = true
    format = "$directory$character"

    [directory]
    truncation_length = 3
    truncation_symbol = "…/"
    format = "[$path]($style) "
    style = "bold cyan"

    [character]
    success_symbol = "[❯](green)"
    error_symbol = "[❯](red)"
    SEOF
    done

    # Override the dotfiles toggle_theme with a sandbox-friendly version.
    # The full theme-manager.sh expects niri/kitty/waybar to be running and
    # ships dozens of generated theme files — none of which exist remotely.
    # This sandbox version just flips ~/.config/theme_mode; nvim's existing
    # fs_event watcher in colorscheme.lua picks up the change live.
    # Files copied from the dotfiles store path are read-only (0444); flip
    # the functions dir to writable before overwriting, then put it back.
    chmod -R u+w $out/fish/functions
    cat > $out/fish/functions/toggle_theme.fish <<'FEOF'
    function toggle_theme --description "Flip ~/.config/theme_mode between dark and light (sandbox version)"
        set -l current "light"
        if test -f ~/.config/theme_mode
            set current (cat ~/.config/theme_mode)
        end
        set -l next "dark"
        if test "$current" = "dark"
            set next "light"
        end
        echo "$next" > ~/.config/theme_mode
        echo "→ theme_mode: $next"
    end
    FEOF

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

    # The configRoot derivation lives in /nix/store (read-only), but fish
    # needs to *write* universal variables, history, etc. under
    # XDG_CONFIG_HOME/fish/. So sync the read-only tree to a writable
    # location (~/.config/daphen-env) and point env vars there. cp with
    # --no-preserve=mode strips the read-only bits from store files;
    # we leave already-extant non-source files (fish_variables, etc.)
    # alone so they persist across sessions.
    WRITABLE_CONFIG="$HOME/.config/daphen-env"
    mkdir -p "$WRITABLE_CONFIG"
    cp -rL --no-preserve=mode "${configRoot}"/. "$WRITABLE_CONFIG/"
    chmod -R u+w "$WRITABLE_CONFIG"

    # Default ~/.config/theme_mode to "light" on first launch so nvim's
    # colorscheme.lua picks the light variant. Doesn't clobber an existing
    # preference — the toggle_theme function writes there too.
    if [ ! -f "$HOME/.config/theme_mode" ]; then
      mkdir -p "$HOME/.config"
      echo light > "$HOME/.config/theme_mode"
    fi

    # Materialize the matching starship variant. Re-evaluated each launch
    # so an `exec fish` after toggle_theme picks up the new prompt.
    THEME_MODE=$(cat "$HOME/.config/theme_mode" 2>/dev/null || echo light)
    if [ -e "$WRITABLE_CONFIG/starship/$THEME_MODE.toml" ]; then
      cp -f "$WRITABLE_CONFIG/starship/$THEME_MODE.toml" "$WRITABLE_CONFIG/starship/starship.toml"
    fi

    export XDG_CONFIG_HOME="$WRITABLE_CONFIG"
    export GIT_CONFIG_GLOBAL="$WRITABLE_CONFIG/gitconfig"
    export STARSHIP_CONFIG="$WRITABLE_CONFIG/starship/starship.toml"
    export EDITOR="nvim"
    export VISUAL="nvim"
    exec ${pkgs.fish}/bin/fish -l "$@"
  '';
}

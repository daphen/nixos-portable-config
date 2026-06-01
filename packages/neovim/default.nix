{ pkgs, inputs, lib }:

let
  # Shared formatters & linters — on PATH for conform.nvim, nvim-lint, and direct use.
  # Trimmed to what's actually used in the lovable monorepo (TS/Go/Nix/CSS).
  # Re-add language-specific tools (stylua, black, ruff, alejandra, statix) if
  # the sandbox workload changes.
  lintAndFormat = with pkgs; [
    prettier      # TS / JS / CSS / JSON
    nixpkgs-fmt   # Nix (single Nix formatter — alejandra dropped)
    eslint_d      # TS / JS lint
    shellcheck    # shell lint
  ];

  # Custom plugins not yet packaged in nixpkgs. Commits pinned from current
  # lazy-lock.json. Hashes are lib.fakeHash placeholders — Nix will tell us
  # the real hash on first build; update them then.
  customPlugins = {
    lualine-macro-recording = pkgs.vimUtils.buildVimPlugin {
      pname = "lualine-macro-recording";
      version = "unstable-2026-04";
      src = pkgs.fetchFromGitHub {
        owner = "yavorski";
        repo = "lualine-macro-recording.nvim";
        rev = "e2dcf63ba74e6111b53e1520a4f8a17a3d7427a1";
        hash = "sha256-Jcgddq7ImqHHSGXPUheWfg6t5OenK4a9IBIUcOswXsk=";
      };
      doCheck = false;
    };

    lualine-so-fancy = pkgs.vimUtils.buildVimPlugin {
      pname = "lualine-so-fancy";
      version = "unstable-2026-04";
      src = pkgs.fetchFromGitHub {
        owner = "meuter";
        repo = "lualine-so-fancy.nvim";
        rev = "6ba7b138f2ca435673eb04c2cf85f0757df69b07";
        hash = "sha256-Ctdt8kCG+4ynpfEHpvUhFQpbhcaLg0hoPX+yPkUQGS0=";
      };
      doCheck = false;
    };
  };

  # Neovim wrapper module definition.
  nvimWrapper = { wlib, pkgs, lib, config, ... }: {
    imports = [ wlib.wrapperModules.neovim ];

    options = {
      settings = {
        test_mode = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "If true, read lua config from disk (dev mode) instead of the Nix store.";
        };

        wrapped_config = lib.mkOption {
          type = wlib.types.stringable;
          default = ./.;
        };

        unwrapped_config = lib.mkOption {
          type = lib.types.either wlib.types.stringable lib.types.luaInline;
          default = lib.generators.mkLuaInline
            "vim.uv.os_homedir() .. '/nixos/packages/neovim'";
        };
      };
    };

    config = {
      settings.config_directory =
        if config.settings.test_mode
        then config.settings.unwrapped_config
        else config.settings.wrapped_config;

      # devMode uses "vim" as binary name so both derivations can coexist
      binName = lib.mkIf config.settings.test_mode (lib.mkDefault "vim");
      settings.dont_link = config.binName != "nvim";

      # ── LSP servers, formatters, linters ──────────────────────────────
      # Trimmed to essentials. Each Node-based LSP bundles its own Node
      # runtime (~80-185MB each), so pulling the whole set triples closure
      # size. Add back via overlay or extend this list if you need more.
      extraPackages = with pkgs; [
        # Language servers — what's used in the lovable monorepo daily.
        typescript-language-server     # TS / JS / TSX / JSX (`app/`, `web/`)
        gopls                          # Go (`go/api`, `go/cli`, …)
        tailwindcss-language-server    # Tailwind class completion
        vscode-langservers-extracted   # CSS / HTML / JSON
        nil                            # Nix (devenv, flake.nix)

        # Dropped to shrink the closure (re-add if you actually edit these
        # in the sandbox):
        #   lua-language-server        # ~30MB — only useful for nvim config editing
        #   bash-language-server       # ~80MB Node — shellcheck linter is enough
        #   pyright                    # ~185MB — Python work not in scope
        #   svelte-language-server     # ~110MB — Svelte not in scope
        #   emmet-ls                   # ~64MB — HTML expansion not in scope

        # Runtime deps the nvim config or plugins may invoke
        ripgrep
        fd
        git
      ] ++ lintAndFormat;

      specs = {
        initLua = {
          data = null;
          before = [ "MAIN_INIT" ];
          config = ''
            require('init')
            require('lz.n').load('plugins')
            require('lz.n').load('plugins.lsp')
          '';
        };

        # ── Plugins (always loaded) ──────────────────────────────────────
        start = let p = pkgs.vimPlugins; in [
          p.lz-n
          p.plenary-nvim
          p.nui-nvim
          p.nvim-web-devicons
          p.mini-icons
          # Specific grammars only — withAllGrammars pulls 150+ parsers (~200MB).
          # Add more languages to this list as you need them.
          (p.nvim-treesitter.withPlugins (ts: with ts; [
            bash c cpp css go gomod gosum gowork html javascript json lua
            markdown markdown_inline nix python regex rust toml tsx
            typescript vim yaml
          ]))
          p.nvim-treesitter-textobjects

          # Completion (needed early so cmp integrations work)
          p.nvim-cmp
          p.cmp-nvim-lsp
          p.cmp_luasnip
          p.luasnip
          p.friendly-snippets

          # LSP core
          p.nvim-lspconfig
          p.nvim-lsp-file-operations

          # Eagerly loaded because other plugins' config hooks require() them
          # synchronously at startup (before lz.n would trigger lazy load).
          p.nvim-notify
        ];

        # ── Plugins (lazy loaded via lz.n) ────────────────────────────────
        opt = let p = pkgs.vimPlugins; in {
          lazy = true;
          data = [
            # UI
            p.noice-nvim
            p.dressing-nvim
            p.fastaction-nvim
            p.lualine-nvim
            customPlugins.lualine-macro-recording
            customPlugins.lualine-so-fancy
            p.snacks-nvim
            p.markview-nvim

            # Editing
            p.nvim-autopairs
            p.nvim-highlight-colors
            p.mini-nvim

            # Git
            p.gitsigns-nvim
            p.diffview-nvim

            # LSP / Mason / formatting / linting
            p.mason-nvim
            p.mason-lspconfig-nvim
            p.conform-nvim
            p.nvim-lint

            # Terminals / scrollback
            p.kitty-scrollback-nvim
          ];
        };
      };
    };
  };

in {
  # Portable neovim — config baked into the Nix store.
  # Run anywhere with Nix: nix run github:daphen/nixos-config#neovim
  neovim = inputs.wrapper-modules.wrappers.neovim.wrap {
    inherit pkgs;
    imports = [ nvimWrapper ];
  };

  # Dev mode — reads lua config from ~/nixos/packages/neovim/ so edits
  # take effect instantly without rebuilding. Binary is `vim` to coexist.
  devMode = inputs.wrapper-modules.wrappers.neovim.wrap {
    inherit pkgs;
    imports = [
      nvimWrapper
      { settings.test_mode = true; }
    ];
  };

  # Auto-detect wrapper. Uses devMode if repo is cloned locally at
  # ~/nixos (live-edit workflow), otherwise the baked portable nvim.
  neovimDynamic = pkgs.writeShellApplication {
    name = "nvim";
    text = ''
      if [ -d "$HOME/nixos/packages/neovim/lua" ]; then
        exec ${lib.getExe (inputs.wrapper-modules.wrappers.neovim.wrap {
          inherit pkgs;
          imports = [ nvimWrapper { settings.test_mode = true; } ];
        })} "$@"
      else
        exec ${lib.getExe (inputs.wrapper-modules.wrappers.neovim.wrap {
          inherit pkgs;
          imports = [ nvimWrapper ];
        })} "$@"
      fi
    '';
  };

  # Make `neovim` the default for `nix run .` with no attribute
  default = inputs.wrapper-modules.wrappers.neovim.wrap {
    inherit pkgs;
    imports = [ nvimWrapper ];
  };
}

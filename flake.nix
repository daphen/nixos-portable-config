{
  description = "Portable dev environment — ephemeral 'nix run' dev shell + a bundled nvim, deployable to any Linux host with Nix installed";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Wraps neovim + plugins + config into a standalone derivation
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

    # Git worktree management CLI — provides its own home-manager module
    worktrunk = {
      url = "github:max-sixty/worktrunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dotfiles tree, fetched as a plain source (not a flake itself) so we can
    # reference individual files from the daphen-env config tree.
    dotfiles = {
      url = "github:daphen/dotfiles";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, wrapper-modules, worktrunk, dotfiles, ... }@inputs:
    let
      # Support both common Linux archs: proart is x86_64, lovbox sandboxes are aarch64.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems f;

      pkgsFor = system: import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      packagesFor = system:
        let
          pkgs = pkgsFor system;
          neovimPackages = import ./packages/neovim {
            inherit pkgs inputs;
            lib = nixpkgs.lib;
          };
          daphenEnv = import ./packages/daphen-env {
            inherit pkgs inputs;
            neovim = neovimPackages.neovim;
          };
        in neovimPackages // {
          daphen-env = daphenEnv;
          # `nix run github:daphen/nixos-portable-config` (no attr) lands here.
          default = daphenEnv;
        };

      mkHomeConfig = system: home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        extraSpecialArgs = { inherit inputs self; };
        modules = [ ./home-modules/remote.nix ];
      };

    in {
      # ─────────────────────────────────────────────────────────────────
      # Ephemeral dev-env (primary entry point for sandbox use):
      #   nix run github:daphen/nixos-portable-config
      # which is equivalent to `…#daphen-env`. Builds the closure into the
      # Nix store on first run, then drops you into fish with all tools
      # available. No profile installs, no per-host state.
      #
      # Also exposed: `…#neovim` for nix-run-only nvim, and the historical
      # devMode/neovimDynamic variants for live-edit workflows on proart.
      # ─────────────────────────────────────────────────────────────────
      packages = forAllSystems packagesFor;

      # ─────────────────────────────────────────────────────────────────
      # home-manager configurations remain for proart / other hosts that
      # want a persistent install. Not used by the lovbox bootstrap flow
      # anymore; that one uses `nix run` via daphen-env.
      # ─────────────────────────────────────────────────────────────────
      homeConfigurations = {
        daphen-remote          = mkHomeConfig "x86_64-linux";
        daphen-remote-aarch64  = mkHomeConfig "aarch64-linux";
      };

      # ─────────────────────────────────────────────────────────────────
      # Dev shell (for iterating on this flake locally)
      # ─────────────────────────────────────────────────────────────────
      devShells = forAllSystems (system: let pkgs = pkgsFor system; in {
        default = pkgs.mkShell {
          packages = [
            pkgs.nixpkgs-fmt
            pkgs.nil
            home-manager.packages.${system}.home-manager
          ];
        };
      });
    };
}

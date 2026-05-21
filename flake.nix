{
  description = "Portable dev environment — fish + bundled nvim + CLI toolkit, deployable to any Linux host with Nix installed";

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
    # reference individual files from the HM config and bake them into the store.
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

      neovimPackagesFor = system: import ./packages/neovim {
        pkgs = pkgsFor system;
        inherit inputs;
        lib = nixpkgs.lib;
      };

      mkHomeConfig = system: home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsFor system;
        extraSpecialArgs = { inherit inputs self; };
        modules = [ ./home-modules/remote.nix ];
      };

    in {
      # ─────────────────────────────────────────────────────────────────
      # Standalone packages — one set per system.
      #   nix run github:daphen/nixos-portable-config#neovim
      # ─────────────────────────────────────────────────────────────────
      packages = forAllSystems neovimPackagesFor;

      # ─────────────────────────────────────────────────────────────────
      # Portable home-manager configurations — one per system. bootstrap.sh
      # picks the right attr from `uname -m`. Apply manually with:
      #   home-manager switch --flake github:daphen/nixos-portable-config#daphen-remote
      #   home-manager switch --flake github:daphen/nixos-portable-config#daphen-remote-aarch64
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

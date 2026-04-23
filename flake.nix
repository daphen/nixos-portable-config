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
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      # The bundled neovim (three variants)
      neovimPackages = import ./packages/neovim {
        inherit pkgs inputs;
        lib = nixpkgs.lib;
      };

    in {
      # ─────────────────────────────────────────────────────────────────
      # Standalone packages
      # ─────────────────────────────────────────────────────────────────
      # Run the bundled nvim anywhere with Nix:
      #   nix run github:daphen/nixos-portable-config#neovim
      packages.${system} = neovimPackages;

      # ─────────────────────────────────────────────────────────────────
      # Portable home-manager configuration
      # ─────────────────────────────────────────────────────────────────
      # Apply on any Linux host:
      #   home-manager switch --flake github:daphen/nixos-portable-config#daphen-remote
      homeConfigurations.daphen-remote = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs self; };
        modules = [ ./home-modules/remote.nix ];
      };

      # ─────────────────────────────────────────────────────────────────
      # Dev shell (for iterating on this flake locally)
      # ─────────────────────────────────────────────────────────────────
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.nixpkgs-fmt
          pkgs.nil
          home-manager.packages.${system}.home-manager
        ];
      };
    };
}

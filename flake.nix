{
  description = "Atlassian Teamwork Graph CLI (twg) for Nix, Home Manager, and NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      release = builtins.fromJSON (builtins.readFile ./sources.json);
      systems = builtins.attrNames release.platforms;
      forAllSystems =
        function:
        lib.genAttrs systems (
          system:
          function (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = package: lib.getName package == "twg";
            }
          )
        );
    in
    {
      overlays.default = final: _prev: { twg = final.callPackage ./package.nix { }; };

      homeManagerModules = {
        twg = import ./modules/home-manager.nix;
        default = self.homeManagerModules.twg;
      };

      nixosModules = {
        twg = import ./modules/nixos.nix;
        default = self.nixosModules.twg;
      };

      packages = forAllSystems (pkgs: {
        twg = pkgs.callPackage ./package.nix { };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.twg;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.twg;
          meta.description = "Atlassian Teamwork Graph CLI";
        };
      });

      formatter = forAllSystems (
        pkgs:
        pkgs.nixfmt-tree.override {
          # Also find the checkout root before this directory is a Git repository.
          settings.tree-root-file = "flake.nix";
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.nixfmt
            pkgs.statix
            pkgs.deadnix
            pkgs.python3
            pkgs.ruff
          ];
        };
      });

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.twg;
        completions = import ./tests/completions.nix {
          inherit pkgs;
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.twg;
        };
        modules = import ./tests/modules.nix {
          inherit
            pkgs
            self
            nixpkgs
            home-manager
            ;
        };
        style =
          pkgs.runCommand "twg-style-check"
            {
              nativeBuildInputs = [
                pkgs.nixfmt
                pkgs.statix
                pkgs.deadnix
                pkgs.ruff
                pkgs.python3
              ];
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./flake.nix
                  ./package.nix
                  ./sources.json
                  ./modules
                  ./lib
                  ./tests
                  ./scripts
                  ./examples
                  ./pyproject.toml
                ];
              };
            }
            ''
              cd "$src"
              find . -name '*.nix' -print0 | xargs -0 nixfmt --check
              statix check .
              deadnix --fail .
              ruff check --no-cache scripts tests
              ruff format --check --no-cache scripts tests
              PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
              touch "$out"
            '';
      });
    };
}

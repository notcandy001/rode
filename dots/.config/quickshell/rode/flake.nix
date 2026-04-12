{
  description = "Rode - An Axtremely customizable shell by Axenide";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    axctl = {
      url = "github:Axenide/axctl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, axctl, ... }:
    let
      rodeLib = import ./nix/lib.nix { inherit nixpkgs; };
    in {
      nixosModules.default = { pkgs, lib, ... }: {
        imports = [ ./nix/modules ];
        programs.rode.enable = lib.mkDefault true;
        programs.rode.package = lib.mkDefault self.packages.${pkgs.system}.default;
      };

      packages = rodeLib.forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          lib = nixpkgs.lib;

          Rode = import ./nix/packages {
            inherit pkgs lib self system axctl;
          };
        in {
          default = Rode;
          Rode = Rode;
        }
      );

      devShells = rodeLib.forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          Rode = self.packages.${system}.default;
        in {
          default = pkgs.mkShell {
            packages = [ Rode ];
            shellHook = ''
              export QML2_IMPORT_PATH="${Rode}/lib/qt-6/qml:$QML2_IMPORT_PATH"
              export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
              echo "Rode dev environment loaded."
            '';
          };
        }
      );

      apps = rodeLib.forAllSystems (system:
        let
          Rode = self.packages.${system}.default;
        in {
          default = {
            type = "app";
            program = "${Rode}/bin/rode";
          };
        }
      );
    };
}

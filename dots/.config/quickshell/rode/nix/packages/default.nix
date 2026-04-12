# Main Rode package
{ pkgs, lib, self, system, axctl }:

let
  quickshellPkg = pkgs.quickshell;
  axctlPkg = axctl.packages.${system}.default;

  # Import sub-packages
  ttf-phosphor-icons = import ./phosphor-icons.nix { inherit pkgs; };

  # Import modular package lists
  corePkgs = import ./core.nix { inherit pkgs quickshellPkg; };
  toolsPkgs = import ./tools.nix { inherit pkgs; };
  mediaPkgs = import ./media.nix { inherit pkgs; };
  appsPkgs = import ./apps.nix { inherit pkgs; };
  fontsPkgs = import ./fonts.nix { inherit pkgs ttf-phosphor-icons; };
  tesseractPkgs = import ./tesseract.nix { inherit pkgs; };

  # Combine all packages (NixOS-specific deps handled by the module)
  baseEnv = corePkgs
    ++ [ axctlPkg ]
    ++ toolsPkgs
    ++ mediaPkgs
    ++ appsPkgs
    ++ fontsPkgs
    ++ tesseractPkgs;

  envRode = pkgs.buildEnv {
    name = "Rode-env";
    paths = baseEnv;
  };

  # Create fontconfig configuration to find bundled fonts
  fontconfigConf = pkgs.writeTextDir "etc/fonts/conf.d/99-rode-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${envRode}/share/fonts</dir>
    </fontconfig>
  '';

  # Copy shell sources to the Nix store
  shellSrc = pkgs.stdenv.mkDerivation {
    pname = "rode-shell";
    version = lib.removeSuffix "\n" (builtins.readFile ../../version);
    src = lib.cleanSource self;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };

  launcher = pkgs.writeShellScriptBin "rode" ''
    export RODE_QS="${quickshellPkg}/bin/qs"
    export PATH="${envRode}/bin:$PATH"

    # Set QML2_IMPORT_PATH to include modules from envRode (like syntax-highlighting)
    export QML2_IMPORT_PATH="${envRode}/lib/qt-6/qml:$QML2_IMPORT_PATH"
    export QML_IMPORT_PATH="$QML2_IMPORT_PATH"

    # Make bundled fonts available to fontconfig
    export FONTCONFIG_PATH="${fontconfigConf}/etc/fonts:''${FONTCONFIG_PATH:-}"

    # Delegate execution to CLI (now in the Nix store)
    exec ${shellSrc}/cli.sh "$@"
  '';

in pkgs.buildEnv {
  name = "Rode";
  paths = [ envRode launcher ];
  meta.mainProgram = "rode";
}

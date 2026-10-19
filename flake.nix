{
  description = "eva: a desktop shell, lock screen and greeter for morf";

  nixConfig = {
    extra-substituters = [ "https://paneworks.cachix.org" ];
    extra-trusted-public-keys = [ "paneworks.cachix.org-1:5XAOHaQHgDEM4dL1Cpu56zcKZxUWYP7zmv8GD3Siy0Q=" ];
  };

  inputs = {
    # The engine eva is written against: a release, moved on deliberately.
    morf.url = "github:paneworks/morf/v0.5.0";
    nixpkgs.follows = "morf/nixpkgs";
    flake-utils.follows = "morf/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils, morf, ... }:
    let
      # eva's own version, as morf.lua declares it.
      version = builtins.head (builtins.match ''.*version = "([0-9.]+)".*''
        (builtins.replaceStrings [ "\n" ] [ " " ] (builtins.readFile ./morf.lua)));
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        engine = morf.packages.${system}.morf;
        eva = pkgs.callPackage ./nix/package.nix {
          inherit version;
          src = self;
          library = morf.packages.${system}.morf-library;
        };
        # A system with eva enabled, evaluated and never built: the module's
        # options and wiring hold together.
        machine = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.default
            {
              programs.eva = {
                enable = true;
                user = "eva";
                lulePackage = pkgs.hello;
                pattern.enable = true;
                phone.enable = true;
              };
              users.users.eva.isNormalUser = true;
              boot.loader.grub.enable = false;
              fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
              system.stateVersion = "25.05";
            }
          ];
        };
      in
      {
        packages = {
          default = eva;
          inherit eva;
        };
        checks = {
          inherit eva;
          module = pkgs.writeText "eva-module-eval"
            (builtins.unsafeDiscardStringContext machine.config.system.build.toplevel.drvPath);
        };
        devShells.default = pkgs.mkShell {
          packages = [ engine pkgs.coreutils pkgs.git-cliff ];
          # The faces eva draws with, whatever the machine has installed:
          # the specs measure text in them.
          MORF_FONT_PATH = pkgs.lib.makeSearchPath "share/fonts" eva.fontPackages;
        };
      }
    )
    // {
      nixosModules.default = import ./nix/nixos { flake = self; engine = morf; };
      nixosModules.eva = self.nixosModules.default;
    };
}

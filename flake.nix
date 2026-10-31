{
  description = "eva: a desktop shell, lock screen and greeter for morf";

  nixConfig = {
    extra-substituters = [ "https://cache.bresilla.com/bresilla" ];
    extra-trusted-public-keys = [ "bresilla:zsecaZYIrjCJQS4AuGPmEVU5PRkiMmB/Mds3KaCzTvE=" ];
  };

  inputs = {
    # The engine eva is written against: a release, moved on deliberately.
    morf.url = "github:paneworks/morf/v0.6.2";
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
          inherit version keyring pattern;
          src = self;
          morf = engine;
        };
        keyring = pkgs.callPackage ./nix/keyring.nix {
          inherit version;
          src = ./helpers/keyring;
        };
        pattern = pkgs.callPackage ./nix/pattern.nix { src = ./helpers/pattern; };
        # A system with eva enabled, evaluated and never built: the module's
        # options and wiring hold together.
        machine = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ self.nixosModules.default ./nix/machine.nix ];
        };
      in
      {
        packages = {
          default = eva;
          inherit eva;
          eva-keyring = keyring;
          eva-pattern = pattern;
        };
        checks = {
          inherit eva;
          eva-keyring = keyring;
          eva-pattern = pattern;
          module = pkgs.writeText "eva-module-eval"
            (builtins.unsafeDiscardStringContext machine.config.system.build.toplevel.drvPath);
        };
        devShells.default = pkgs.mkShell {
          packages = [ engine pkgs.coreutils pkgs.git-cliff pkgs.lua5_4 ];
          # The faces eva draws with, whatever the machine has installed:
          # the specs measure text in them.
          MORF_FONT_PATH = pkgs.lib.makeSearchPath "share/fonts" eva.fontPackages;
          EVA_KEYRING_HELPER = "${keyring}/bin/eva-keyring";
        };
      }
    )
    // {
      nixosModules.default = import ./nix/nixos {
        packages = system: {
          inherit (self.packages.${system}) eva;
          morf = morf.packages.${system}.morf;
        };
      };
      nixosModules.eva = self.nixosModules.default;
    };
}

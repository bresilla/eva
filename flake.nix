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
          inherit version;
          src = self;
          morf = engine;
        };
        # A system with eva enabled, evaluated and never built: the module's
        # options and wiring hold together.
        machine =
          extra:
          pkgs.writeText "eva-module-eval" (builtins.unsafeDiscardStringContext
            (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.default
                ./nix/machine.nix
                extra
              ];
            }).config.system.build.toplevel.drvPath);
      in
      {
        packages = {
          default = eva;
          inherit eva;
          # Not a check: a login needs a Hyprland that reads Lua, so see the
          # head of the file for how to run it.
          login-test = pkgs.testers.runNixOSTest (
            import ./nix/tests/login.nix {
              module = self.nixosModules.default;
              wallpaper = ./tests/fixtures/wallpaper.png;
            }
          );
          clock-test = pkgs.testers.runNixOSTest (
            import ./nix/tests/clock.nix {
              inherit eva;
              morf = engine;
            }
          );
          # The same: the head of the file says how to run it.
          windows-test = pkgs.testers.runNixOSTest (
            import ./nix/tests/windows.nix {
              module = self.nixosModules.default;
              wallpaper = ./tests/fixtures/wallpaper.png;
              only = builtins.getEnv "EVA_VM_ONLY";
            }
          );
        };
        checks = {
          inherit eva;
          module = machine { };
          module-plymouth = machine { programs.eva.seamless.plymouth = true; };
          module-plain = machine { programs.eva.seamless.enable = false; };
          module-phone = machine {
            programs.eva.phone = {
              enable = true;
              suspendTimeout = 900;
              wakeDevices = [ "/sys/devices/platform/modem" ];
              alwaysOn = true;
            };
          };
          module-hardware = machine {
            programs.eva.hardware = {
              tabletSwitch = { enable = true; name = "Intel HID switches"; };
              chargeLimit = true;
              usbTether = true;
              ddc.enable = true;
            };
          };
          module-remap = machine { programs.eva.remap.enable = true; };
          module-fixed = machine {
            programs.eva.idle = {
              lockTimeout = 300;
              screenOffTimeout = 330;
              suspendTimeout = 900;
            };
            programs.eva.lock.settings.grace_seconds = 0;
            programs.eva.greeter.keyboardLayouts = "us,de";
          };
        };
        devShells.default = pkgs.mkShell {
          packages = [
            engine
            pkgs.coreutils
            pkgs.git-cliff
            pkgs.lua5_4
            # A real Taskwarrior for its spec, and tools/see.sh's session.
            pkgs.taskwarrior3
            pkgs.sway
            pkgs.grim
            pkgs.wtype
            pkgs.dbus
            # What the tools of apps/ call, for tools/see.sh's scenarios.
            pkgs.jq
            pkgs.wl-clipboard
            pkgs.tesseract
            pkgs.zbar
            # The assistant's transport, and the fake provider its specs ask.
            pkgs.curl
            pkgs.python3
            # A real text field for tools/see/keyboard-ime.steps.
            pkgs.zenity
            pkgs.libnotify
          ];
          # The faces eva draws with, whatever the machine has installed:
          # the specs measure text in them.
          MORF_FONT_PATH = pkgs.lib.makeSearchPath "share/fonts" eva.fontPackages;
          EVA_KEYRING_HELPER = "${eva}/bin/eva-keyring";
          MORF_LIMITS = "frame=64m";
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

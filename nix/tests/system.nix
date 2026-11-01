# What eva asks of the system, against the real thing in a VM: Hyprland's
# options, shaders, rotation and outputs; hypridle with no lock timeout fixed;
# CUPS, UPower and NetworkManager on kernel test devices.
#
# The node is windows.nix's and the helpers windows.py's. Hyprland reads Lua from
# 0.55, so the nixpkgs under the test needs that Hyprland:
#
#   nix build .#system-test --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
{ module, wallpaper }:
let
  base = import ./windows.nix { inherit module wallpaper; };
  password = "correct horse battery staple";
in
{
  name = "eva-system";

  nodes.machine =
    { pkgs, lib, ... }:
    {
      imports = [ base.nodes.machine ];
      programs.eva = {
        idle.lockTimeout = lib.mkForce null;
        hardware.chargeLimit = true;
      };
      services.printing = {
        enable = true;
        cups-pdf.enable = true;
      };
      services.upower.enable = true;
      networking.networkmanager.enable = true;
      boot.kernelModules = [
        "test_power"
        "mac80211_hwsim"
      ];
      boot.extraModprobeConfig = "options mac80211_hwsim radios=2";
      environment.systemPackages = [
        pkgs.grim
        pkgs.iw
        pkgs.jq
        pkgs.upower
        # There is no sound server here: what stands in writes down what it was
        # asked to play, and plays it for as long as a short sample would last.
        (lib.hiPrio (
          pkgs.writeShellScriptBin "pw-play" ''
            printf '%s\n' "$*" >> /tmp/sound-requests
            exec sleep 2
          ''
        ))
      ];
    };

  extraPythonPackages = base.extraPythonPackages;

  testScript =
    builtins.readFile ./windows.py
    + builtins.readFile ./system.py
    + ''

      system("${password}")
    '';
}

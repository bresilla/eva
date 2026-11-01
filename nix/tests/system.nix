# What eva asks of the system, against the real thing in a VM: Hyprland's
# options, shaders, rotation and outputs; hypridle with no lock timeout fixed; a
# timer's ring; CUPS, UPower and NetworkManager on kernel test devices.
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
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      shell = config.programs.eva.shellPackage;
      # system-job.lua beside the links a job finds the shell's modules through.
      job = pkgs.runCommand "eva-system-job" { } ''
        mkdir -p "$out"
        cp ${./system-job.lua} "$out/app.lua"
        ln -s ${shell}/share/eva/shell "$out/lua"
        ln -s ${shell}/share/eva/shell/fonts "$out/fonts"
        ln -s ${shell}/share/eva/apps/common "$out/common"
      '';
      colours = pkgs.writeShellScript "eva-test-colours" ''
        printf '\033[41m     \033[42m     \033[44m     \033[43m     \033[45m     \033[46m     \033[0m\n'
        exec sleep 3600
      '';
    in
    {
      imports = [ base.nodes.machine ];
      programs.eva = {
        idle.lockTimeout = lib.mkForce null;
        hardware.chargeLimit = true;
        hardware.hotspot = true;
      };
      users.users.alice.extraGroups = [ "networkmanager" ];
      services.printing = {
        enable = true;
        cups-pdf.enable = true;
      };
      services.upower.enable = true;
      networking.networkmanager.enable = true;
      # The VM profile takes wpa_supplicant away at this priority.
      networking.wireless.enable = lib.mkOverride 5 true;
      boot.kernelModules = [
        "test_power"
        "mac80211_hwsim"
      ];
      boot.extraModprobeConfig = "options mac80211_hwsim radios=2";
      environment.etc."eva-test-job".source = job;
      environment.etc."eva-test-colours".source = colours;
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

# The window features against a real Hyprland in a VM, on a software GPU: the
# calls the shell makes, each one read back from the compositor.
#
# The module's compositor configuration is Lua, which Hyprland reads from 0.55,
# so the nixpkgs under the test needs that Hyprland:
#
#   nix build .#windows-test --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
#
# `only` names sections of windows.py to run alone; through the flake,
# EVA_VM_ONLY="keys rules" with --impure.
{ module, wallpaper, only ? "" }:
let
  password = "correct horse battery staple";
  software = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    MORF_PRESENT = "swapchain";
  };
in
{
  name = "eva-windows";

  nodes.machine =
    { pkgs, lib, ... }:
    let
      # Answers as a monitor would: real DDC/CI needs a screen on an I2C bus.
      ddcutil = pkgs.writeShellScriptBin "ddcutil" ''
        echo "$*" >> /tmp/ddc-calls
        case "$*" in
          *detect*) printf 'Display 1\n   I2C bus:  /dev/i2c-6\n   DRM connector:           card0-Virtual-1\n   Monitor:                 DEL:DELL U2720Q:7H3KD\n' ;;
          *getvcp*) printf 'VCP 10 C %s 100\n' "$(cat /tmp/ddc-level 2>/dev/null || echo 60)" ;;
          *setvcp*) for value in "$@"; do :; done; echo "$value" > /tmp/ddc-level ;;
        esac
      '';
      lule = pkgs.writeShellScriptBin "lule" ''
        for argument in "$@"; do
          case "$argument" in
            --output=*) cp ${wallpaper} "''${argument#--output=}" ;;
            --cache=*)
              mkdir -p "''${argument#--cache=}"
              printf '{"wallpaper":"","theme":"dark","colors":["#10141c","#7fb4e8"]}' \
                > "''${argument#--cache=}/colors.json"
              ;;
          esac
        done
      '';
    in
    {
      imports = [ module ];
      programs.eva = {
        enable = true;
        user = "alice";
        usePackagedShell = true;
        lulePackage = lule;
        idle.lockTimeout = 0;
        idle.suspendTimeout = 0;
        greeter.environment = software;
        hardware.ddc.enable = true;
        remap.enable = true;
      };
      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };
      environment.systemPackages = [ pkgs.foot pkgs.ydotool pkgs.libinput (lib.hiPrio ddcutil) ];
      boot.kernelModules = [ "uinput" ];
      # No sound, modem or Bluetooth service, even in the guest.
      services.pipewire.enable = lib.mkForce false;
      services.pipewire.wireplumber.enable = lib.mkForce false;
      networking.modemmanager.enable = lib.mkForce false;
      hardware.bluetooth.enable = lib.mkForce false;
      environment.sessionVariables = software;
      systemd.user.services.eva.environment = software;
      hardware.graphics.enable = true;
      virtualisation = {
        memorySize = 4096;
        cores = 4;
        diskSize = 8192;
        qemu.options = [
          "-vga none"
          "-device virtio-gpu-pci"
        ];
      };
    };

  extraPythonPackages = python: [ python.pillow ];

  testScript = builtins.readFile ./windows.py + ''

    run("${password}", "${only}")
  '';
}

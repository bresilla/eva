# The global touch driver against a real Hyprland in a VM, on a software GPU,
# with a real multi-touch device: QEMU's virtio-multitouch-pci, driven over QMP.
# Each sequence reaches the guest kernel as evdev events, so libinput, Hyprland
# and every Wayland client see what they would see from a touchscreen.
#
# The module's compositor configuration is Lua, which Hyprland reads from 0.55,
# so the nixpkgs under the test needs that Hyprland, and QEMU 8.1 or later:
#
#   nix build .#touch-test --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
{ module, wallpaper }:
let
  password = "correct horse battery staple";
  software = {
    LIBGL_ALWAYS_SOFTWARE = "1";
    MORF_PRESENT = "swapchain";
  };
in
{
  name = "eva-touch";

  nodes.machine =
    { pkgs, lib, ... }:
    let
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
        idle.screenOffTimeout = 0;
        greeter.environment = software;
      };
      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };
      # wev logs each wl_touch event a window receives; zenity is GTK's own drag
      # to scroll, and scroller.lua a window scrolled by two fingers.
      environment.systemPackages = [ pkgs.wev pkgs.zenity pkgs.acl pkgs.hyprlock ];
      environment.etc."eva-test/scroller.lua".source = ./scroller.lua;
      # A locker that tells logind nothing.
      environment.etc."eva-test/hyprlock.conf".text = ''
        background {
          color = rgb(20, 20, 40)
        }
      '';
      security.pam.services.hyprlock = { };
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
          "-device virtio-multitouch-pci"
        ];
      };
    };

  extraPythonPackages = python: [ python.pillow ];

  testScript = builtins.readFile ./touch.py + ''

    run("${password}")
  '';
}

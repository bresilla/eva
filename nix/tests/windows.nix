# The window features against a real Hyprland in a VM, on a software GPU: the
# calls the shell makes, each one read back from the compositor.
#
# The module's compositor configuration is Lua, which Hyprland reads from 0.55,
# so the nixpkgs under the test needs that Hyprland:
#
#   nix build .#windows-test --override-input nixpkgs github:NixOS/nixpkgs/nixos-unstable
{ module, wallpaper }:
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
    { pkgs, ... }:
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
        greeter.environment = software;
      };
      users.users.alice = {
        isNormalUser = true;
        inherit password;
      };
      environment.systemPackages = [ pkgs.foot pkgs.ydotool ];
      boot.kernelModules = [ "uinput" ];
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

    run("${password}")
  '';
}

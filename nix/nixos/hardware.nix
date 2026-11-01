{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.eva.hardware;
  gadget = pkgs.writeShellApplication {
    name = "eva-usb-gadget";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.kmod
    ];
    text = builtins.readFile ./scripts/usb-gadget.sh;
  };
  threshold = file: ''
    ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{type}=="Battery", TEST=="${file}", RUN+="${pkgs.coreutils}/bin/chgrp eva-hardware /sys%p/${file}", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/${file}"
  '';
  # Every Wi-Fi interface, as each firewall backend spells it.
  wifi = if config.networking.nftables.enable then "wl*" else "wl+";
in
{
  options.programs.eva.hardware = {
    ddc.enable = lib.mkEnableOption ''
      external monitors' brightness over DDC/CI, on the one brightness slider and
      keys. Installs ddcutil and loads i2c-dev; a udev rule tags only the buses
      that lead to a display `uaccess`, so the person at the seat can reach those
      while they are at it, with no group and no other I2C device
    '';
    tabletSwitch = {
      enable = lib.mkEnableOption "following a convertible's hinge: evtest, and read access to switch devices alone";
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Intel HID switches";
        description = "The switch as `hyprctl devices` names it: Hyprland's switch binds then tell eva as the hinge moves.";
      };
    };
    chargeLimit = lib.mkEnableOption "the session writing the kernel's charge thresholds";
    usbTether = lib.mkEnableOption "a USB network gadget for the USB tethering tile";
    hotspot = lib.mkEnableOption ''
      clients of the Wi-Fi hotspot reaching the machine's DHCP and DNS: the firewall
      opens those ports on every Wi-Fi interface, to whatever listens on them
    '';
  };

  config =
    lib.mkIf
      (config.programs.eva.enable && (cfg.ddc.enable || cfg.tabletSwitch.enable || cfg.chargeLimit || cfg.usbTether || cfg.hotspot))
      (
        lib.mkMerge [
          (lib.mkIf (cfg.tabletSwitch.enable || cfg.chargeLimit) {
            users.groups.eva-hardware.members = [ config.programs.eva.user ];
          })
          (lib.mkIf cfg.tabletSwitch.enable {
            environment.systemPackages = [ pkgs.evtest ];
            services.udev.extraRules = ''
              SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", GROUP="eva-hardware", MODE="0640"
            '';
          })
          (lib.mkIf (cfg.tabletSwitch.enable && cfg.tabletSwitch.name != null) {
            programs.eva.hyprland.extraConfig = ''
              hl.bind("switch:on:${cfg.tabletSwitch.name}", hl.dsp.exec_cmd("eva tablet on"), { locked = true })
              hl.bind("switch:off:${cfg.tabletSwitch.name}", hl.dsp.exec_cmd("eva tablet off"), { locked = true })
            '';
          })
          (lib.mkIf cfg.ddc.enable {
            boot.kernelModules = [ "i2c-dev" ];
            environment.systemPackages = [ pkgs.ddcutil ];
            environment.sessionVariables.EVA_DDC = "1";
            systemd.user.services.eva.environment.EVA_DDC = "1";
            # Named to sort before 73-seat-late, which reads the tag. A display's
            # bus hangs under a DRM connector, or carries its driver's adapter name.
            services.udev.packages = [
              (pkgs.writeTextDir "lib/udev/rules.d/70-eva-ddc.rules" ''
                SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", SUBSYSTEMS=="drm", TAG+="uaccess"
                SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", ATTR{name}=="NVIDIA i2c adapter*", TAG+="uaccess"
                SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", ATTR{name}=="i915 gmbus*", TAG+="uaccess"
              '')
            ];
            programs.eva.hyprland.extraConfig = ''
              hl.unbind("XF86MonBrightnessUp")
              hl.unbind("XF86MonBrightnessDown")
              hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("eva brightness up"), { locked = true, repeating = true })
              hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("eva brightness down"), { locked = true, repeating = true })
            '';
          })
          (lib.mkIf cfg.chargeLimit {
            services.udev.extraRules = lib.concatStrings [
              (threshold "charge_control_end_threshold")
              (threshold "charge_control_start_threshold")
            ];
          })
          (lib.mkIf cfg.hotspot {
            networking.firewall.interfaces.${wifi} = {
              allowedUDPPorts = [
                53
                67
              ];
              allowedTCPPorts = [ 53 ];
            };
          })
          (lib.mkIf cfg.usbTether {
            systemd.services.eva-usb-gadget = {
              description = "A USB network port to tether over";
              wantedBy = [ "multi-user.target" ];
              before = [ "NetworkManager.service" ];
              unitConfig.ConditionPathExistsGlob = "/sys/class/udc/*";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${gadget}/bin/eva-usb-gadget start";
                ExecStop = "${gadget}/bin/eva-usb-gadget stop";
              };
            };
          })
        ]
      );
}

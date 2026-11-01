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
in
{
  options.programs.eva.hardware = {
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
  };

  config =
    lib.mkIf (config.programs.eva.enable && (cfg.tabletSwitch.enable || cfg.chargeLimit || cfg.usbTether))
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
          (lib.mkIf cfg.chargeLimit {
            services.udev.extraRules = lib.concatStrings [
              (threshold "charge_control_end_threshold")
              (threshold "charge_control_start_threshold")
            ];
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

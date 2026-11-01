{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.eva.idle;
  lockSession = "${pkgs.systemd}/bin/loginctl lock-session";
  suspendNow = "${pkgs.systemd}/bin/systemctl suspend";
  # The timeouts Settings wrote for this account win over these options; taking
  # them away there comes back here.
  hypridleStart = pkgs.writeShellScript "eva-hypridle" ''
    chosen="''${XDG_STATE_HOME:-$HOME/.local/state}/eva/idle/hypridle.conf"
    file=/etc/xdg/hypr/hypridle.conf
    if [ -r "$chosen" ]; then file=$chosen; fi
    exec ${config.services.hypridle.package}/bin/hypridle --config "$file"
  '';
in
{
  options.programs.eva.idle = {
    lockTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 300;
      description = "Idle seconds before locking; zero disables automatic locking.";
    };
    screenOffTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = cfg.lockTimeout + 30;
      defaultText = lib.literalExpression "config.programs.eva.idle.lockTimeout + 30";
      description = "Idle seconds before turning off displays; zero disables idle display power-off.";
    };
    suspendTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1800;
      description = "Idle seconds before suspending; zero leaves sleep to explicit actions such as closing the lid.";
    };
  };

  config = lib.mkIf (config.programs.eva.enable && config.programs.hyprland.enable) {
    services.hypridle.enable = true;
    system.build.hyprlandIdleDpms = pkgs.writeShellScript "hyprland-idle-dpms" ''
      action="''${1:-}"
      case "$action" in on|off) ;; *) exit 2 ;; esac
      # Hyprland accepts different dispatcher syntax for Lua and Hyprlang.
      if result=$(${config.programs.hyprland.package}/bin/hyprctl dispatch "hl.dsp.dpms({action = \"$action\"})" 2>&1) \
        && [ "$result" = ok ]; then
        exit 0
      fi
      exec ${config.programs.hyprland.package}/bin/hyprctl dispatch dpms "$action"
    '';
    # What Settings needs to write the same file with other timeouts.
    environment.etc."eva/idle.json".text = builtins.toJSON {
      inherit (cfg) lockTimeout screenOffTimeout suspendTimeout;
      commands = {
        lock_session = "${pkgs.systemd}/bin/systemctl --user start eva-idle-lock.service";
        before_sleep = lockSession;
        after_sleep = "${config.system.build.hyprlandIdleDpms} on";
        lock = lockSession;
        screen_off = "${config.system.build.hyprlandIdleDpms} off";
        screen_on = "${config.system.build.hyprlandIdleDpms} on";
        suspend = suspendNow;
      };
    };
    # Pass an explicit system config: ~/.config/hypr remains an editable
    # dotfiles symlink, and switching compositors drops this entire block.
    environment.etc."xdg/hypr/hypridle.conf".text = ''
      general {
        lock_cmd = ${pkgs.systemd}/bin/systemctl --user start eva-idle-lock.service
        before_sleep_cmd = ${lockSession}
        after_sleep_cmd = ${config.system.build.hyprlandIdleDpms} on
        inhibit_sleep = 3
      }

      ${lib.optionalString (cfg.lockTimeout > 0) ''
      listener {
        timeout = ${toString cfg.lockTimeout}
        on-timeout = ${lockSession}
      }
      ''}

      ${lib.optionalString (cfg.screenOffTimeout > 0) ''
      listener {
        timeout = ${toString cfg.screenOffTimeout}
        on-timeout = ${config.system.build.hyprlandIdleDpms} off
        on-resume = ${config.system.build.hyprlandIdleDpms} on
      }
      ''}

      ${lib.optionalString (cfg.suspendTimeout > 0) ''
      listener {
        timeout = ${toString cfg.suspendTimeout}
        on-timeout = ${suspendNow}
      }
      ''}
    '';
    systemd.user.services.hypridle = {
      partOf = [ "graphical-session.target" ];
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${hypridleStart}"
      ];
      restartTriggers = [ config.environment.etc."xdg/hypr/hypridle.conf".source ];
    };
    # Repeated idle/sleep requests reuse the same running lock process.
    systemd.user.services.eva-idle-lock = {
      description = "eva lock screen requested by Hyprland idle management";
      partOf = [ "graphical-session.target" ];
      path = [ "/run/current-system/sw" ];
      serviceConfig = {
        Type = "exec";
        ExecStart = "/run/current-system/sw/bin/morf lock";
      };
    };
  };
}

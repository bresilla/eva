{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.eva.idle;
  phone = config.programs.eva.phone;
  timeout =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      inherit description;
    };
  fixed = stage: "Idle seconds before ${stage}; zero never. Null leaves it to Settings, Idle and sleep.";
  # What the system fixes wins over Settings; each stage it fixes stays a
  # listener of hypridle's, and the shell only shows it.
  managed =
    if phone.enable then
      {
        lock = phone.idleTimeout;
        blank = phone.idleTimeout;
        suspend = 0;
      }
    else
      lib.filterAttrs (_: value: value != null) {
        lock = cfg.lockTimeout;
        blank = cfg.screenOffTimeout;
        suspend = cfg.suspendTimeout;
      };
  dpms = config.system.build.hyprlandIdleDpms;
  loginctl = "${pkgs.systemd}/bin/loginctl";
  # A lock asked for by the idle timer says so: the window after it depends on it.
  idleLock = pkgs.writeShellScript "eva-idle-lock-mark" ''
    run=''${XDG_RUNTIME_DIR:?}/eva
    ${pkgs.coreutils}/bin/mkdir -p "$run"
    read -r up _ < /proc/uptime
    printf '{"reason":"idle","at":%s}' "$up" > "$run/lock-reason.tmp"
    ${pkgs.coreutils}/bin/mv -f "$run/lock-reason.tmp" "$run/lock-reason"
    exec ${loginctl} lock-session
  '';
  # Locks before sleep unless the system or the person said not to. A lock made
  # for sleep is never an idle one.
  beforeSleep = pkgs.writeShellScript "eva-before-sleep" ''
    ${pkgs.coreutils}/bin/rm -f "''${XDG_RUNTIME_DIR:-/nonexistent}/eva/lock-reason"
    jq=${pkgs.jq}/bin/jq
    want=$($jq -r 'if has("on_suspend") then (.on_suspend | tostring) else "" end' /etc/eva/lock.json 2>/dev/null)
    if [ -z "$want" ]; then
      state=''${XDG_STATE_HOME:-$HOME/.local/state}
      file=$(${pkgs.coreutils}/bin/cat "$state/eva/settings-path" 2>/dev/null)
      want=$($jq -r 'if .lock.on_suspend == false then "false" else "true" end' "$file" 2>/dev/null)
    fi
    [ "$want" = false ] && exit 0
    exec ${loginctl} lock-session
  '';
in
{
  options.programs.eva.idle = {
    lockTimeout = timeout (fixed "locking");
    screenOffTimeout = timeout (fixed "turning off displays");
    suspendTimeout = timeout (fixed "suspending");
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
    system.build.evaIdleLock = idleLock;
    # What the shell reads: the stages fixed here, and the commands to use.
    environment.etc."eva/idle-stages.json".text = builtins.toJSON {
      inherit managed;
      commands = {
        lock = [
          loginctl
          "lock-session"
        ];
        dpms = "${dpms}";
      };
      sleep_lock = true;
    };
    # Pass an explicit system config: ~/.config/hypr remains an editable
    # dotfiles symlink, and switching compositors drops this entire block.
    environment.etc."xdg/hypr/hypridle.conf".text = ''
      general {
        lock_cmd = ${pkgs.systemd}/bin/systemctl --user start eva-idle-lock.service
        before_sleep_cmd = ${beforeSleep}
        after_sleep_cmd = ${dpms} on
        inhibit_sleep = 3
        # The shell holds org.freedesktop.ScreenSaver and passes requests on.
        ignore_dbus_inhibit = true
      }

      ${lib.optionalString (cfg.lockTimeout != null && cfg.lockTimeout > 0) ''
      listener {
        timeout = ${toString cfg.lockTimeout}
        on-timeout = ${idleLock}
      }
      ''}

      ${lib.optionalString (cfg.screenOffTimeout != null && cfg.screenOffTimeout > 0) ''
      listener {
        timeout = ${toString cfg.screenOffTimeout}
        on-timeout = ${dpms} off
        on-resume = ${dpms} on
      }
      ''}

      ${lib.optionalString (cfg.suspendTimeout != null && cfg.suspendTimeout > 0) ''
      listener {
        timeout = ${toString cfg.suspendTimeout}
        on-timeout = ${pkgs.systemd}/bin/systemctl suspend
      }
      ''}
    '';
    systemd.user.services.hypridle = {
      partOf = [ "graphical-session.target" ];
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${config.services.hypridle.package}/bin/hypridle --config /etc/xdg/hypr/hypridle.conf"
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

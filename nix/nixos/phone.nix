{
  config,
  lib,
  pkgs,
  ...
}:
let
  pointerConfig = ''
    hl.config({ cursor = { invisible = true } })
  '';
  workspaceConfig = ''
    -- eva owns bottom-edge contact sequences, including workspace previews.
    hl.config({ gestures = {
      workspace_swipe_touch = false,
    } })
    -- The native preview has already finished the transition at handoff.
    hl.animation({ leaf = "workspaces", enabled = ${lib.boolToString (config.programs.eva.phone.gestureDriver == "lisgd")}, speed = 4, bezier = "default", style = "slide" })
  '';

  hyprland = config.programs.hyprland.package;
  dpms = pkgs.writeShellScriptBin "phone-dpms" ''
    exec ${config.system.build.hyprlandIdleDpms} "$@"
  '';
  screen = pkgs.writeShellApplication {
    name = "phone-screen";
    runtimeInputs = [
      hyprland
      dpms
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/screen.sh;
  };
  deliberateWakeConfig = ''
    -- Pocket touches must not wake the screen. The power key is handled
    -- by logind in the user session and by the explicit greeter binding.
    hl.config({ misc = {
      key_press_enables_dpms = false,
      mouse_move_enables_dpms = false,
    } })
  '';
  makeIdleConfig =
    timeout:
    pkgs.writeText "phone-hypridle.conf" ''
      general {
        lock_cmd = ${screen}/bin/phone-screen toggle
        before_sleep_cmd = ${screen}/bin/phone-screen off
        inhibit_sleep = 3
      }
      ${lib.optionalString (timeout > 0) ''
        listener {
          timeout = ${toString timeout}
          on-timeout = ${screen}/bin/phone-screen off
        }
      ''}
      ${lib.optionalString (config.programs.eva.phone.suspendTimeout > 0) ''
        listener {
          timeout = ${toString config.programs.eva.phone.suspendTimeout}
          on-timeout = ${pkgs.systemd}/bin/systemctl suspend
        }
      ''}
    '';
  idleConfig = makeIdleConfig config.programs.eva.phone.idleTimeout;
  greeterIdleConfig = makeIdleConfig 60;
  gestureAction = pkgs.writeShellApplication {
    name = "phone-gesture";
    runtimeInputs = [
      config.programs.hyprland.package
      config.programs.eva.package
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      case "''${1:-}" in
        workspace-next|workspace-previous|dashboard|top|keyboard) ;;
        *) exit 2 ;;
      esac
      # Let Wayland deliver the final contacts before querying Morf's context.
      sleep 0.05
      # Global input must never act on the desktop behind a session lock.
      hyprctl -j locked | jq -e '.locked == false' >/dev/null || exit 0
      timeout 3 morf -i "$WAYLAND_DISPLAY" ipc call phone-gesture "$1" >/dev/null
    '';
  };
  phoneKey = pkgs.writeShellApplication {
    name = "phone-key";
    runtimeInputs = [ config.programs.eva.package pkgs.coreutils ];
    text = ''
      exec timeout 3 morf -i "$WAYLAND_DISPLAY" ipc call phone key "$1" >/dev/null
    '';
  };
  keyConfig = lib.concatMapStrings (entry: ''
    hl.bind("${entry.key}", hl.dsp.exec_cmd("${phoneKey}/bin/phone-key ${entry.name}"), { locked = true })
  '') [
    { key = "XF86AudioLowerVolume"; name = "volume-down"; }
    { key = "XF86AudioRaiseVolume"; name = "volume-up"; }
    { key = "XF86PowerOff"; name = "power"; }
  ];
  gestureRunner = pkgs.writeShellApplication {
    name = "phone-gestures";
    runtimeInputs = [
      pkgs.lisgd
      config.programs.hyprland.package
      pkgs.jq
      pkgs.systemd
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      export PHONE_GESTURE_ACTION=${gestureAction}/bin/phone-gesture
      ${builtins.readFile ./scripts/gestures.sh}
    '';
  };
in
{
  options.programs.eva.phone.enable =
    lib.mkEnableOption "eva phone screen power and touch gestures";
  options.programs.eva.phone.idleTimeout = lib.mkOption {
    type = lib.types.ints.unsigned;
    default = 60;
    description = "Seconds before locking and blanking a phone session; zero disables automatic locking.";
  };
  options.programs.eva.phone.calls = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Calls and texts: ModemManager, callaudiod, feedbackd and iio-sensor-proxy.
      The user joins `networkmanager`, whose polkit rule lets a session use
      ModemManager's Voice and Messaging without asking for a password that
      nothing on a locked screen could answer, and `feedbackd`.
    '';
  };
  options.programs.eva.phone.suspendTimeout = lib.mkOption {
    type = lib.types.ints.unsigned;
    default = 0;
    description = ''
      Idle seconds before suspending; zero keeps the phone awake. Leave it at zero
      until a call has been seen to wake this phone from suspend: whether one does
      is up to its kernel and its modem, and `wakeDevices` must name what rings it.
      A call in progress holds suspend off through logind.
    '';
  };
  options.programs.eva.phone.wakeDevices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "/sys/devices/platform/soc/4080000.remoteproc/wakeup" ];
    description = ''
      Sysfs device folders whose `power/wakeup` is turned on at boot, so the modem
      can wake a sleeping phone. There is no general answer: on a USB modem it is
      the USB device, on a Qualcomm SoC the modem's remoteproc or its IPC channel.
    '';
  };
  options.programs.eva.phone.gestureDriver = lib.mkOption {
    type = lib.types.enum [ "native" "lisgd" ];
    default = "native";
    description = ''
      Native gestures follow the finger and settle with its release velocity.
      lisgd is a completed-swipe fallback for older Morf engines.
    '';
  };
  config =
    lib.mkIf
      (
        config.programs.eva.enable && config.programs.eva.phone.enable && config.programs.hyprland.enable
      )
      {
        services.logind.settings.Login.HandlePowerKey = "lock";
        networking.modemmanager.enable = lib.mkIf config.programs.eva.phone.calls (lib.mkDefault true);
        programs.feedbackd.enable = lib.mkIf config.programs.eva.phone.calls (lib.mkDefault true);
        hardware.sensor.iio.enable = lib.mkIf config.programs.eva.phone.calls (lib.mkDefault true);
        services.dbus.packages = lib.optional config.programs.eva.phone.calls pkgs.callaudiod;
        systemd.tmpfiles.rules = map (device: "w ${device}/power/wakeup - - - - enabled")
          config.programs.eva.phone.wakeDevices;
        # Only lisgd reads /dev/input; native gestures come over Wayland.
        users.users.${config.programs.eva.user}.extraGroups =
          lib.optional (config.programs.eva.phone.gestureDriver == "lisgd") "input"
          ++ lib.optionals config.programs.eva.phone.calls [ "networkmanager" "feedbackd" ];
        environment.systemPackages = [ screen ]
          ++ lib.optional (config.programs.eva.phone.gestureDriver == "lisgd") pkgs.lisgd
          ++ lib.optional config.programs.eva.phone.calls pkgs.callaudiod;
        # Shared by the user's lockscreen and the separate greeter process.
        environment.etc."eva/phone-screen.json".text = builtins.toJSON {
          command = "${screen}/bin/phone-screen";
          doubleTap = true;
        };
        environment.etc."xdg/hypr/hypridle.conf".source = lib.mkForce idleConfig;
        environment.etc."xdg/hypr/hypridle.conf".text = lib.mkForce null;
        programs.eva.hyprland.extraConfig = deliberateWakeConfig + pointerConfig + workspaceConfig
          + lib.optionalString config.programs.eva.phone.calls keyConfig;
        programs.eva.greeter = {
          environment.EVA_PHONE_GREETER = "1";
          sessionSetup = ''
            ${config.services.hypridle.package}/bin/hypridle --config ${greeterIdleConfig} &
            idle=$!
            trap 'kill "$idle" 2>/dev/null || true' EXIT
          '';
          extraConfig =
            deliberateWakeConfig
            + pointerConfig
            + ''
              -- logind does not send Lock to sessions of class greeter.
              hl.bind("XF86PowerOff", hl.dsp.exec_cmd("${screen}/bin/phone-screen toggle"), { locked = true })
            '';
        };
        systemd.user.services.eva.environment.EVA_GESTURE_DRIVER = config.programs.eva.phone.gestureDriver;
        systemd.user.services.phone-gestures = lib.mkIf (config.programs.eva.phone.gestureDriver == "lisgd") {
          description = "Phone edge swipes through lisgd";
          wantedBy = [ "graphical-session.target" ];
          after = [
            "graphical-session.target"
            "eva.service"
          ];
          partOf = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${gestureRunner}/bin/phone-gestures";
            Restart = "on-failure";
            RestartSec = 2;
            TimeoutStopSec = 5;
          };
        };
        # Keep phone preferences writable and stable when the theme path changes.
        # Seed the visible bar once, or carry over the file from before the
        # rename; eva can save other preferences normally.
        systemd.user.services.eva = {
          environment.EVA_SETTINGS = "%h/.local/state/eva/phone.json";
          preStart = ''
            ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$EVA_SETTINGS")"
            legacy="$HOME/.local/state/caelestia/phone.json"
            if [ ! -e "$EVA_SETTINGS" ] && [ -e "$legacy" ]; then
              ${pkgs.coreutils}/bin/install -m 600 "$legacy" "$EVA_SETTINGS"
            fi
            if [ ! -e "$EVA_SETTINGS" ]; then
              ${pkgs.coreutils}/bin/install -m 600 ${
                pkgs.writeText "eva-phone.json" (
                  builtins.toJSON {
                    edgebar.enabled = "on";
                  }
                )
              } "$EVA_SETTINGS"
            fi
          '';
        };
      };
}

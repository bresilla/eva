# `packages` gives, for a system, the eva output and the morf it runs on:
# built from eva's flake, or store paths taken from a binary cache.
{ packages }:
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  given = packages system;
  morf = config.programs.eva.package;
  shell = config.programs.eva.shellPackage;
  keyring = config.programs.eva.keyringPackage;
  user = config.programs.eva.user;
  userHome = config.users.users.${user}.home;
  # Keep advanced CLI invocations unchanged; protect the default entry points.
  morfDefault = pkgs.writeShellScriptBin "morf" ''
    set -u
    export MORF_RUNTIME_PATH="${
      lib.concatMapStringsSep ":" toString config.programs.eva.runtimePaths
    }''${MORF_RUNTIME_PATH:+:$MORF_RUNTIME_PATH}"
    export EVA_KEYRING_HELPER="''${EVA_KEYRING_HELPER:-${keyring}/bin/eva-keyring}"
    export EVA_SCALE_MODE=compositor
    export EVA_SCALE_FILE="''${EVA_SCALE_FILE:-${config.programs.eva.uiScaleFile}}"
    export EVA_SCALE_DEFAULT="''${EVA_SCALE_DEFAULT:-${toString config.programs.eva.uiScale}}"
    if [ "$#" -gt 1 ]; then exec ${morf}/bin/morf "$@"; fi
    role="''${1:-shell}"
    case "$role" in shell|lock|greet) ;; *) exec ${morf}/bin/morf "$@" ;; esac
    if [ "$role" = shell ] && [ -z "''${XDG_SESSION_ID:-}" ]; then
      # User services do not inherit UWSM's login session. Polkit needs the
      # graphical session, rather than the systemd user manager's session.
      session=$(${pkgs.systemd}/bin/loginctl show-user "$(${pkgs.coreutils}/bin/id -u)" \
        --property=Display --value 2>/dev/null || true)
      if [ -n "$session" ]; then export XDG_SESSION_ID="$session"; fi
    fi
    if [ "$role" = shell ] && [ -n "''${MORF_CONFIG:-}" ]; then
      exec ${morf}/bin/morf "$@"
    fi
    root="''${XDG_CONFIG_HOME:-$HOME/.config}"
    if [ "$role" = greet ] && [ -n "''${EVA_GREETER_CONFIG_HOME:-}" ]; then
      root="$EVA_GREETER_CONFIG_HOME"
    fi
    candidate="$root/eva/$role/init.lua"
    fallback="/etc/xdg/morf/default/$role/init.lua"
    # The chosen appearance lives in state, so read-only configs keep it and the
    # greeter can follow it. An older file, under morf's state or beside the
    # theme, moves there once.
    if [ -z "''${EVA_APPEARANCE:-}" ]; then
      if [ "$role" = greet ] && [ -n "''${EVA_GREETER_CONFIG_HOME:-}" ]; then
        appearance="''${EVA_GREETER_APPEARANCE:-}"
        if [ -n "$appearance" ] && [ -r "$appearance" ]; then export EVA_APPEARANCE="$appearance"; fi
      else
        appearance="''${XDG_STATE_HOME:-$HOME/.local/state}/eva/appearance/appearance.json"
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$appearance")"
        old="''${XDG_STATE_HOME:-$HOME/.local/state}/morf/appearance/appearance.json"
        if [ ! -e "$appearance" ] && [ -r "$old" ]; then ${pkgs.coreutils}/bin/install -m 644 "$old" "$appearance"; fi
        if [ ! -e "$appearance" ] && [ -r "$candidate" ]; then
          legacy="$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/readlink -f "$candidate")")")/appearance.json"
          if [ -r "$legacy" ]; then ${pkgs.coreutils}/bin/install -m 644 "$legacy" "$appearance"; fi
        fi
        export EVA_APPEARANCE="$appearance"
      fi
    fi
    ${lib.optionalString config.programs.eva.usePackagedShell ''
      # Keep the shipped UI and engine together while preserving the user's
      # appearance preferences. Custom CLI paths remain explicit overrides.
      if [ -z "''${EVA_APPEARANCE:-}" ] && [ -r "$candidate" ]; then
        theme=$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/readlink -f "$candidate")")")
        if [ -r "$theme/appearance.json" ]; then export EVA_APPEARANCE="$theme/appearance.json"; fi
      fi
      export XDG_CONFIG_DIRS=/etc/xdg
      exec ${morf}/bin/morf "$fallback"
    ''}
    if [ -r "$candidate" ]; then
      if [ "$role" = greet ] && [ -n "''${EVA_GREETER_CONFIG_HOME:-}" ]; then
        theme=$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/dirname "$(${pkgs.coreutils}/bin/readlink -f "$candidate")")")
        if [ -r "$theme/appearance.json" ]; then export EVA_APPEARANCE="$theme/appearance.json"; fi
      fi
      check_args=()
      if [ "$role" = lock ]; then check_args=(-- window preview); fi
      if EVA_DRY_RUN=1 ${pkgs.coreutils}/bin/timeout 10 \
        ${morf}/bin/morf check "$candidate" --no-dbus --isolate --after 0 "''${check_args[@]}" >/dev/null; then
        ${morf}/bin/morf "$candidate"
        status=$?
        if [ "$status" -eq 0 ]; then exit 0; fi
        echo "eva $role exited with $status; using $fallback" >&2
      else
        echo "eva $role configuration failed validation; using $fallback" >&2
      fi
    fi
    if [ "$role" = greet ] && [ -n "''${EVA_GREETER_CONFIG_HOME:-}" ]; then unset EVA_APPEARANCE; fi
    export XDG_CONFIG_DIRS=/etc/xdg
    exec ${morf}/bin/morf "$fallback"
  '';
  greeterAccess = pkgs.writeShellScript "eva-greeter-access" ''
    # No write access, and no directory listing outside the eva tree.
    home=$(${pkgs.coreutils}/bin/readlink -e ${lib.escapeShellArg userHome}) || exit 0
    # The chosen appearance is the one state folder the greeter may read.
    appearance="$home/.local/state/eva/appearance"
    if [ -d "$appearance" ] && [ ! -L "$appearance" ]; then
      for parent in "$home" "$home/.local" "$home/.local/state" "$home/.local/state/eva"; do
        ${pkgs.acl}/bin/setfacl -m u:greeter:--x "$parent" || echo "Cannot grant greeter traversal on $parent" >&2
      done
      ${pkgs.acl}/bin/setfacl -R -P -m u:greeter:rX,d:u:greeter:rX "$appearance" \
        || echo "Cannot grant greeter read access on $appearance" >&2
    fi
    root=$(${pkgs.coreutils}/bin/readlink -e "$home/.config/eva") || exit 0
    [ -d "$root" ] || exit 0
    for start in "$home" "$(${pkgs.coreutils}/bin/readlink -e "$home/.config")" "$root"; do
      parent="$start"
      while [ -n "$parent" ]; do
        case "$parent" in "$home"|"$home"/*) ;; *) break ;; esac
        ${pkgs.acl}/bin/setfacl -m u:greeter:--x "$parent" || echo "Cannot grant greeter traversal on $parent" >&2
        parent=$(${pkgs.coreutils}/bin/dirname "$parent")
      done
    done
    case "$root" in
      "$home"/*)
        ${pkgs.acl}/bin/setfacl -R -P -m u:greeter:rX "$root" || echo "Cannot grant greeter read access on $root" >&2
        ${pkgs.findutils}/bin/find "$root" -type d -exec ${pkgs.acl}/bin/setfacl -m d:u:greeter:r-x {} + \
          || echo "Cannot set inherited greeter read access on $root" >&2
        ;;
    esac
    exit 0
  '';
  greeter = pkgs.writeShellScript "eva-greeter" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.systemd
        pkgs.fontconfig
      ]
    }:/run/current-system/sw/bin
    export XDG_CONFIG_HOME=/var/lib/greetd/.config
    export EVA_GREETER_CONFIG_HOME=${lib.escapeShellArg "${userHome}/.config"}
    export EVA_GREETER_APPEARANCE=${lib.escapeShellArg "${userHome}/.local/state/eva/appearance/appearance.json"}
    export XDG_CONFIG_DIRS=${lib.escapeShellArg "${userHome}/.config:/etc/xdg"}
    export XDG_DATA_DIRS=${config.services.displayManager.sessionData.desktops}/share:/run/current-system/sw/share
    exec ${config.system.build.evaGreeterCompositor}
  '';
  scaleDirectory = "/var/lib/eva/ui-scale/${user}";
  directory = "/var/lib/eva/wallpaper/${user}";
  lule = config.programs.eva.lulePackage;
  bridge = pkgs.writeShellScriptBin "eva-wallpaper" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/wallpaper.py} "$@"
  '';
  # A minimal greeter-only palette config: user hooks belong to their session.
  luleConfig = pkgs.writeTextDir "init.lua" ''
    local lule = require("lule")
    lule.theme = "dark"
    lule.palette = "pigment"
  '';
  fallbackLogo = pkgs.writeText "eva-wallpaper-logo.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <path fill="#ffffff" d="M15 75V25h14l21 25 21-25h14v50H70V48L50 71 30 48v27z"/>
    </svg>
  '';
in
{
  imports = [
    ./authentication.nix
    ./compositor.nix
    ./idle.nix
    ./phone.nix
    ./pattern.nix
  ];

  options.programs.eva = {
    enable = lib.mkEnableOption "the eva desktop shell, greeter and lock screen on morf";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary desktop user whose preferences are shared with the greeter.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = given.morf;
      description = "The morf engine; a cached package can be supplied independently of the shell.";
    };
    shellPackage = lib.mkOption {
      type = lib.types.package;
      # A cached output is used as it is; one from the flake follows `package`.
      default =
        if given.eva ? override then
          given.eva.override { morf = config.programs.eva.package; }
        else
          given.eva;
      description = "The eva output; its share/eva is installed as /etc/xdg/morf/eva.";
    };
    usePackagedShell = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the shell, lockscreen and greeter shipped with eva instead of the ones in ~/.config/eva. Appearance preferences remain user-controlled.";
    };
    keyringPackage = lib.mkOption {
      type = lib.types.package;
      default = config.programs.eva.shellPackage;
      description = "The bridge that shows GNOME Keyring prompts in eva's dialog.";
    };
    lulePackage = lib.mkOption {
      type = lib.types.package;
      description = "Lule package used to generate and share the session wallpaper.";
    };
    wallpaperLogo = lib.mkOption {
      type = lib.types.str;
      default = "${userHome}/.config/eva/logo.svg";
      description = "Optional logo for generated wallpapers.";
    };
  };
  options.programs.eva.uiScale = lib.mkOption {
    type = lib.types.addCheck lib.types.number (value: value >= 0.5 && value <= 2);
    default = 1.0;
    description = "Initial Hyprland display scale shared by desktop, lock and greet. eva's scale slider persists its override.";
  };
  options.programs.eva.uiScaleFile = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "${scaleDirectory}/scale.json";
    description = "Shared, user-writable UI scale preference readable by the greeter.";
  };
  options.programs.eva.runtimePaths = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ "${config.programs.eva.package}/share/morf/library" ];
    description = "Additional Morf desktop modules and startup plugins.";
  };

  config = lib.mkIf config.programs.eva.enable (
    {
      programs.hyprland.enable = lib.mkDefault true;
      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${greeter}";
          user = "greeter";
        };
      };

      users.users.greeter = {
        home = "/var/lib/greetd";
        createHome = true;
      };

      environment.systemPackages = [
        (lib.hiPrio morfDefault)
        bridge
      ];
      system.build.evaLauncher = morfDefault;
      system.build.evaGreeter = greeter;
      system.build.evaGreeterAccess = greeterAccess;
      # Account activation reapplies the private home mode, which clears the ACL
      # mask. Regrant traversal even when the Home Manager package did not change.
      system.activationScripts.evaGreeterAccess = {
        deps = [ "users" ];
        text = "${greeterAccess}";
      };
      # State kept under morf's names before eva had its own, moved once.
      system.activationScripts.evaState = {
        deps = [ "users" "groups" ];
        text = ''
          moved=""
          move() {
            if [ -e "$1" ] && [ ! -e "$2" ]; then
              ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$2")"
              ${pkgs.coreutils}/bin/mv "$1" "$2" && moved="$moved $2"
            fi
          }
          move /var/lib/morf/ui-scale /var/lib/eva/ui-scale
          move /var/lib/morf/wallpaper /var/lib/eva/wallpaper
          move /var/lib/morf/pattern /var/lib/eva/pattern
          move /etc/morf/pattern /etc/eva/pattern
          move /etc/morf/eva-accent /etc/eva/accent
          # The shared wallpaper's files carry the old group, which is gone.
          case "$moved" in
            *" /var/lib/eva/wallpaper"*) ${pkgs.coreutils}/bin/chgrp -R eva-wallpaper /var/lib/eva/wallpaper || true ;;
          esac
          ${pkgs.coreutils}/bin/rmdir /var/lib/morf 2>/dev/null || true
        '';
      };
      systemd.services.eva-greeter-access = {
        description = "Allow the greeter to read the primary user's eva shell";
        wantedBy = [ "multi-user.target" ];
        after = [ "home-manager-${user}.service" ];
        before = [ "greetd.service" ];
        restartTriggers = lib.optionals (options ? home-manager) [
          config.home-manager.users.${user}.home.activationPackage
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = greeterAccess;
        };
      };
      systemd.services.greetd.wants = [ "eva-greeter-access.service" ];

      environment.etc."xdg/morf/eva".source = "${shell}/share/eva";
      environment.etc."xdg/morf/default".source = "${shell}/share/eva";
      environment.etc."greetd/default-session" = lib.mkIf config.programs.hyprland.enable {
        text = if config.programs.hyprland.withUWSM then "hyprland-uwsm\n" else "hyprland\n";
      };
      programs.hyprland.withUWSM = lib.mkIf config.programs.hyprland.enable (lib.mkDefault true);

      systemd.user.services.eva = {
        description = "eva desktop shell on morf";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        path = [ "/run/current-system/sw" ];
        environment.MORF_RUNTIME_PATH =
          lib.concatMapStringsSep ":" toString
            config.programs.eva.runtimePaths;
        serviceConfig = {
          ExecStartPre = "-${bridge}/bin/eva-wallpaper adopt";
          ExecStart = "${morfDefault}/bin/morf shell";
          ExecStopPost = "-${bridge}/bin/eva-wallpaper publish";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
      # The faces the packaged shell draws with, for the greeter too.
      fonts.packages = [ "${shell}/share/fonts" ];

      system.build.evaWallpaper = bridge;
      environment.etc."eva/wallpaper.json".text = builtins.toJSON {
        inherit user directory;
        logo = config.programs.eva.wallpaperLogo;
        fallback_logo = toString fallbackLogo;
        lule = "${lule}/bin/lule";
        lule_config = toString luleConfig;
        command = "${bridge}/bin/eva-wallpaper";
      };
      users.groups.eva-wallpaper.members = [
        user
        "greeter"
      ];
      systemd.tmpfiles.rules = [
        "d /var/lib/eva 0755 root root -"
        "d /var/lib/eva/ui-scale 0755 root root -"
        "d ${scaleDirectory} 0755 ${user} ${config.users.users.${user}.group} -"
        "d /var/lib/eva/wallpaper 0755 root root -"
        "d ${directory} 2770 ${user} eva-wallpaper -"
        "f ${directory}/.lock 0666 ${user} eva-wallpaper -"
      ];
      systemd.services.eva-wallpaper-logo = {
        description = "Share the wallpaper logo with the greeter";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-tmpfiles-setup.service"
          "home-manager-${user}.service"
        ];
        before = [ "eva-wallpaper-boot.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = user;
          ExecStart = "${bridge}/bin/eva-wallpaper logo";
          RemainAfterExit = true;
        };
      };
      systemd.services.eva-wallpaper-boot = {
        description = "Generate the shared Lule wallpaper once per boot";
        wantedBy = [ "multi-user.target" ];
        wants = [ "eva-wallpaper-logo.service" ];
        after = [
          "systemd-tmpfiles-setup.service"
          "eva-wallpaper-logo.service"
        ];
        before = [ "greetd.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "greeter";
          # Lule's palette extractor uses /tmp/lule_palette. Keep the greeter's
          # scratch file separate from the one owned by the logged-in user.
          PrivateTmp = true;
          ExecStart = "${bridge}/bin/eva-wallpaper greet";
          RemainAfterExit = true;
          TimeoutStartSec = 250;
        };
      };
    }
    // lib.optionalAttrs (options ? home-manager) {
      home-manager.users.${user} = { lib, ... }: {
        home.activation.restartEva = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if ${pkgs.systemd}/bin/systemctl --user is-active --quiet eva.service 2>/dev/null; then
            run ${pkgs.systemd}/bin/systemctl --user restart eva.service
          fi
        '';
      };

    }
  );
}

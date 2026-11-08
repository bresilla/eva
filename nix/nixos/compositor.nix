{
  config,
  lib,
  pkgs,
  ...
}:
let
  seamless = config.programs.eva.seamless;
  handoff = ''local handoff = dofile("${./scripts/hyprland-handoff.lua}")'';
  background =
    if seamless.enable then
      ''handoff.background(${builtins.toJSON seamless.colourFile}, "rgb(000000)")''
    else
      ''"rgb(000000)"'';
  quietConfig = ''
    hl.config({
        misc = {
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            background_color = ${background},
            disable_watchdog_warning = true,
            disable_xdg_env_checks = true,
        },
        ecosystem = { no_update_news = true, no_donation_nag = true },
    })
  '';
  hyprland = config.programs.hyprland.package;
  plain = !config.programs.hyprland.withUWSM;
  # Without UWSM: the compositor's environment to systemd, then the graphical
  # session, unless UWSM runs this compositor after all.
  activate = pkgs.writeShellScript "eva-session-start" ''
    case "$(${pkgs.coreutils}/bin/cat /proc/self/cgroup)" in *wayland-wm@*) exit 0 ;; esac
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all
    exec ${pkgs.systemd}/bin/systemctl --user start eva-session.target
  '';
  desktopConfig = pkgs.writeText "hyprland-session.lua" ''
    ${handoff}
    local apply_scale = dofile("${./scripts/hyprland-scale.lua}")(
      ${builtins.toJSON config.programs.eva.uiScaleFile}, ${toString config.programs.eva.uiScale})
    local root = (os.getenv("XDG_CONFIG_HOME") or (assert(os.getenv("HOME")) .. "/.config")) .. "/hypr"
    local file = io.open(root .. "/hyprland.lua", "r")
    local own_config = file ~= nil
    if file then
      file:close()
      -- require registers the user's file with Hyprland's config watcher.
      package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
      require("hyprland")
    else
      dofile("${hyprland}/share/hypr/hyprland.lua")
    end
    -- The arrangement Settings, Displays kept.
    local state = os.getenv("XDG_STATE_HOME") or (assert(os.getenv("HOME")) .. "/.local/state")
    local kept = io.open(state .. "/eva/displays/monitors.lua", "r")
    if kept then
      kept:close()
      dofile(state .. "/eva/displays/monitors.lua")
    end
    ${quietConfig}
    -- A lock screen that dies leaves the session locked; a new one may take over.
    hl.config({ misc = { allow_session_lock_restore = true } })
    ${lib.optionalString (config.programs.eva.hyprland.binds != "never") ''
      -- The keys of the window features, unless this person has their own.
      if ${if config.programs.eva.hyprland.binds == "always" then "true" else "not own_config"} then
        dofile("${config.programs.eva.shellPackage}/share/eva/shell/keybinds.lua").apply(hl, "${config.system.build.evaLauncher}/bin/morf")
      end
    ''}
    ${config.programs.eva.hyprland.extraConfig}
    apply_scale()
    ${lib.optionalString seamless.enable "handoff.record(${builtins.toJSON seamless.outputsFile})"}
    ${lib.optionalString plain ''
      hl.on("hyprland.start", function()
        hl.exec_cmd("${activate}")
      end)
    ''}
  '';
  desktop =pkgs.writeShellScriptBin "hyprland-session" ''
    # The greeter's picture is the session's before anything reads the old one.
    ${config.system.build.evaWallpaper}/bin/eva-wallpaper adopt >/dev/null 2>&1 || :
    ${
      if plain then
        ''
          ${pkgs.systemd}/bin/systemd-cat --identifier=hyprland -- \
            ${hyprland}/bin/start-hyprland -- --config /etc/xdg/hypr/session.lua "$@"
          status=$?
          ${pkgs.systemd}/bin/systemctl --user stop eva-session.target
          exit "$status"
        ''
      else
        ''
          exec ${pkgs.systemd}/bin/systemd-cat --identifier=hyprland -- \
            ${hyprland}/bin/start-hyprland -- --config /etc/xdg/hypr/session.lua "$@"
        ''
    }
  '';
  sessions =
    pkgs.runCommand "hyprland-quiet-sessions"
      {
        passthru.providedSessions =
          if plain then lib.remove "hyprland-uwsm" hyprland.providedSessions else hyprland.providedSessions;
      }
      ''
        mkdir -p "$out/share"
        cp -R ${hyprland}/share/wayland-sessions "$out/share/"
        chmod -R u+w "$out/share/wayland-sessions"
        substituteInPlace "$out/share/wayland-sessions/hyprland.desktop" \
          --replace-fail '${hyprland}/bin/start-hyprland' '${desktop}/bin/hyprland-session'
        ${lib.optionalString (!config.programs.hyprland.withUWSM) ''
          rm -f "$out/share/wayland-sessions/hyprland-uwsm.desktop"
        ''}
      '';
  cfg = config.programs.eva.greeter;
  greeterExit = pkgs.writeShellScript "eva-greeter-exit" ''
    ${hyprland}/bin/hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 \
      || ${hyprland}/bin/hyprctl dispatch exit >/dev/null 2>&1
  '';
  session = pkgs.writeShellScript "eva-greeter-session" ''
    ${cfg.sessionSetup}
    EVA_GREETER_EXIT=${greeterExit} ${config.system.build.evaLauncher}/bin/morf greet
    status=$?
    ${greeterExit}
    exit "$status"
  '';
  greeterConfig = pkgs.writeText "eva-greeter.lua" ''
    ${handoff}
    local apply_scale = dofile("${./scripts/hyprland-scale.lua}")(
      ${builtins.toJSON config.programs.eva.uiScaleFile}, ${toString config.programs.eva.uiScale})
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
    ${lib.optionalString seamless.enable "handoff.adopt(${builtins.toJSON seamless.outputsFile})"}
    ${quietConfig}
    hl.config({
      animations = { enabled = false },
      general = { border_size = 0, gaps_in = 0, gaps_out = 0 },
      input = { kb_layout = ${builtins.toJSON cfg.keyboardLayouts} },
    })
    ${cfg.extraConfig}
    apply_scale()
    hl.on("hyprland.start", function()
      hl.exec_cmd("${session}")
    end)
  '';
in
{
  options.programs.eva.hyprland.extraConfig = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "Profile-specific Lua applied after the user's Hyprland configuration.";
  };

  options.programs.eva.hyprland.binds = lib.mkOption {
    type = lib.types.enum [
      "auto"
      "always"
      "never"
    ];
    default = "auto";
    description = ''
      The keys of eva's window features (shell/keybinds.lua): the overview, the
      switcher, snapping and the rest. `auto` binds them unless the user has a
      ~/.config/hypr/hyprland.lua of their own. eva-keys lists them either way.
    '';
  };

  # Keep the standard session names and other installed desktop environments.
  # UWSM starts hyprland.desktop too, so both login paths use the same settings.
  options.services.displayManager.sessionPackages = lib.mkOption {
    apply =
      packages:
      if config.programs.eva.enable && config.programs.hyprland.enable then
        map (package: if package.outPath == hyprland.outPath then sessions else package) packages
      else
        packages;
  };

  options.programs.eva.greeter = {
    keyboardLayouts = lib.mkOption {
      type = lib.types.str;
      default = config.services.xserver.xkb.layout;
      defaultText = lib.literalExpression "config.services.xserver.xkb.layout";
      example = "us,de";
      description = "Keyboard layouts the greeter offers, comma separated; with more than one a chip switches them.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional Lua for the dedicated Hyprland greeter.";
    };
    sessionSetup = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell setup before starting the eva greeter.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the greeter compositor and its children.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.programs.eva.enable && config.programs.hyprland.enable) {
      environment.etc."xdg/hypr/session.lua".source = desktopConfig;
      environment.systemPackages = [
        desktop
        (lib.hiPrio sessions)
      ];
      system.build.hyprlandQuietSessions = sessions;
      system.build.hyprlandSessionConfig = desktopConfig;
      # The plain session's hold on the graphical session, which UWSM has otherwise.
      systemd.user.targets.eva-session = lib.mkIf plain {
        description = "eva's Hyprland session without UWSM";
        bindsTo = [ "graphical-session.target" ];
        wants = [ "graphical-session-pre.target" ];
        after = [ "graphical-session-pre.target" ];
      };
    })
    (lib.mkIf config.programs.eva.enable {
      system.build.evaGreeterConfig = greeterConfig;
      system.build.evaGreeterCompositor = pkgs.writeShellScript "eva-greeter-compositor" ''
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.environment
        )}
        # Capture even early startup messages, while retaining journal diagnostics.
        exec ${pkgs.systemd}/bin/systemd-cat --identifier=eva-greeter -- \
          ${hyprland}/bin/Hyprland --config ${greeterConfig}
      '';
    })
  ];
}

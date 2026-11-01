# Boot to desktop with nothing but pictures on the way: a quiet kernel and
# systemd, one VT painted in the wallpaper's colour, session output in the
# journal and, when asked, Plymouth handing over to the greeter.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  eva = config.programs.eva;
  cfg = eva.seamless;
  ready = "/run/eva-greeter/ready";
  plymouth = "${config.boot.plymouth.package}/bin/plymouth";
  # Palette entry 0 is the VT's background, so a cleared VT is one colour.
  vt = pkgs.writeShellScript "eva-vt" ''
    [ -t 1 ] || exit 0
    colour=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.colourFile} 2>/dev/null)
    case "$colour" in
      \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
        printf '\033]P0%s' "''${colour#\#}" ;;
    esac
    printf '\033[?25l\033[0m\033[H\033[2J\033[3J'
  '';
  session = pkgs.writeShellScript "eva-session" ''
    ${vt}
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=eva-session -- "$@"
  '';
in
{
  options.programs.eva.seamless = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Hide the way from boot to the desktop: quiet kernel and systemd output,
        no getty on the greeter's VT, session output in the journal, the
        wallpaper's colour behind both compositors and on the VT, and one
        output description shared by the greeter and the session.
      '';
    };
    plymouth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show Plymouth through boot and hand its last frame to the greeter.";
    };
    colourFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/eva/wallpaper/${eva.user}/dominant";
      description = "The wallpaper's dominant colour as #rrggbb, written by the wallpaper bridge.";
    };
    outputsFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${dirOf eva.uiScaleFile}/outputs";
      description = "Each output as the session left it, read by the greeter.";
    };
    readyFile = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = ready;
      description = "Created when the greeter's first frame is on screen.";
    };
  };

  config = lib.mkIf (eva.enable && cfg.enable) (
    lib.mkMerge [
      {
        boot.consoleLogLevel = lib.mkDefault 3;
        boot.initrd.verbose = lib.mkDefault false;
        boot.kernelParams = [
          "quiet"
          "rd.systemd.show_status=false"
          "systemd.show_status=false"
          "rd.udev.log_level=3"
          "udev.log_level=3"
          "vt.global_cursor_default=0"
        ];
        # The cursor back on the VTs that keep a login prompt.
        services.getty.helpLine = lib.mkAfter "\\e[?25h";
        services.greetd.settings.terminal.vt = 1;
        systemd.services."getty@tty1".enable = false;
        systemd.services."autovt@tty1".enable = false;
        system.build.evaVt = vt;
        system.build.evaSession = session;
      }
      (lib.mkIf cfg.plymouth {
        boot.plymouth.enable = true;
        services.greetd.greeterManagesPlymouth = true;
        systemd.services.greetd = {
          after = [ "plymouth-start.service" ];
          conflicts = [ "plymouth-quit.service" ];
          onFailure = [ "plymouth-quit.service" ];
          serviceConfig = {
            ExecStartPre = [ "-${plymouth} deactivate" ];
            Type = lib.mkForce "simple";
          };
        };
        systemd.services.plymouth-quit.wantedBy = lib.mkForce [ ];
        systemd.paths.eva-plymouth-quit = {
          description = "Wait for the greeter's first frame";
          wantedBy = [ "graphical.target" ];
          pathConfig.PathExists = ready;
        };
        systemd.services.eva-plymouth-quit = {
          description = "End Plymouth under the greeter's first frame";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "-${plymouth} quit --retain-splash";
          };
        };
        systemd.tmpfiles.rules = [ "d ${dirOf ready} 0750 greeter greeter -" ];
      })
    ]
  );
}

# Greeter to desktop with nothing but pictures on the way: one VT painted in
# the wallpaper's colour and session output in the journal.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  eva = config.programs.eva;
  cfg = eva.seamless;
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
        Hide the way from the greeter to the desktop: no getty on the
        greeter's VT, session output in the journal, the wallpaper's colour
        behind both compositors and on the VT, and one output description
        shared by the greeter and the session. Boot messages stay on screen.
      '';
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
  };

  config = lib.mkIf (eva.enable && cfg.enable) {
    services.greetd.settings.terminal.vt = 1;
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;
    system.build.evaVt = vt;
    system.build.evaSession = session;
  };
}

# The global touch driver reads the touchscreen beside the compositor, through
# `libinput debug-events` (lib/services/touch_reader.lua). The logged-in user
# gets the touchscreens and nothing else: `input` would hand over every
# keystroke, so this is the `uaccess` tag on touchscreen nodes alone.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.eva.touch;
  libinput = lib.getBin pkgs.libinput;
  # Numbered before 73-seat-late.rules, which acts on the tag; extraRules would
  # land in 99-local.rules, after it.
  rule = pkgs.writeTextDir "lib/udev/rules.d/70-eva-touch.rules" ''
    SUBSYSTEM=="input", ENV{ID_INPUT_TOUCHSCREEN}=="1", TAG+="uaccess"
  '';
in
{
  options.programs.eva.touch.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Gestures anywhere on a touchscreen: the session reads the touchscreen
      through libinput and recognises them itself, while apps keep every touch.
      Adds a udev rule giving the logged-in user the touchscreens alone, and
      libinput. Harmless on a machine with no touchscreen, where nothing runs.
    '';
  };

  config = lib.mkIf (config.programs.eva.enable && cfg.enable) {
    services.udev.packages = [ rule ];
    environment.systemPackages = [ libinput ];
    systemd.user.services.eva.path = [ libinput ];
  };
}

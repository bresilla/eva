# The lock's system policy: what is set here wins over what a person sets in
# Settings, and the page shows it as set. The keys are those of
# models/lock_defaults.lua.
{ config, lib, ... }:
let
  cfg = config.programs.eva.lock;
in
{
  options.programs.eva.lock.settings = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    example = {
      grace_seconds = 0;
      power_buttons = false;
      notifications.level = "count";
    };
    description = ''
      Lock screen settings fixed by the system, as in models/lock_defaults.lua.
      Written to /etc/eva/lock.json; anything left out stays the person's.
    '';
  };

  config = lib.mkIf config.programs.eva.enable {
    environment.etc."eva/lock.json".text = builtins.toJSON cfg.settings;
  };
}

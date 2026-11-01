{
  config,
  lib,
  pkgs,
  ...
}:
let
  eva = config.programs.eva;
  cfg = eva.remap;
  directory = "/var/lib/eva/remap/${eva.user}";
  choices = "${directory}/choices.json";
  rendered = "/run/eva-remap/kanata.kbd";
  render = pkgs.writeShellApplication {
    name = "eva-remap-render";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    # `$tap` and `$hold` are kanata's own variables, kept as written.
    excludeShellChecks = [ "SC2016" ];
    text = builtins.readFile ./scripts/remap-render.sh;
  };
in
{
  options.programs.eva.remap = {
    enable = lib.mkEnableOption ''
      remapping keys in Settings (Caps Lock, a hyper key, tap versus hold) through
      kanata. It reads every keyboard, so it stays off unless enabled here. kanata
      then runs as a system service with no capabilities, a dynamic user that alone
      holds the input group, and no network; nothing is added to the person's
      groups, and it starts only once something is chosen
    '';
    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/dev/input/by-id/usb-Keyboard-event-kbd" ];
      description = "The keyboards to remap; empty for all of them.";
    };
  };

  config = lib.mkIf (eva.enable && cfg.enable) {
    environment.sessionVariables.EVA_REMAP = directory;
    systemd.user.services.eva.environment.EVA_REMAP = directory;
    systemd.tmpfiles.rules = [
      "d /var/lib/eva/remap 0755 root root -"
      "d ${directory} 0700 ${eva.user} ${config.users.users.${eva.user}.group} -"
    ];
    services.kanata = {
      enable = true;
      keyboards.eva = {
        config = "";
        configFile = rendered;
      };
    };
    systemd.services.kanata-eva = {
      # Rendered as root from the person's choices: kanata reads the result, and
      # with nothing chosen it never starts.
      serviceConfig.ExecCondition = "+${render}/bin/eva-remap-render ${choices} ${rendered} ${lib.escapeShellArgs cfg.devices}";
      unitConfig.StartLimitIntervalSec = 0;
    };
    systemd.services.eva-remap = {
      description = "kanata following the choices made in Settings";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.systemd.package}/bin/systemctl restart kanata-eva.service";
      };
    };
    systemd.paths.eva-remap = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = choices;
    };
  };
}

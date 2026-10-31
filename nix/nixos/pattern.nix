{ flake }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.eva.pattern;
  package = flake.packages.${pkgs.stdenv.hostPlatform.system}.eva-pattern;
  helper = "/run/wrappers/bin/eva-pattern-check";
  pamExec = "${pkgs.pam}/lib/security/pam_exec.so";
  rule = {
    order = 11600;
    control = "sufficient";
    modulePath = pamExec;
    args = [ "quiet" "quiet_log" "expose_authtok" helper "--check" ];
  };
  reset = {
    order = 20000;
    control = "optional";
    modulePath = pamExec;
    args = [ "quiet" "quiet_log" helper "--reset" ];
  };
in {
  options.programs.eva.pattern.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Allow locally enrolled unlock patterns for the eva lock and greetd.
      A 4-9 dot pattern has far less entropy than a password and installs a
      setuid verifier that PAM accepts as sufficient, so enable it only where
      that trade-off is acceptable. Failed attempts earn growing cooldowns
      (30 s, 1 min, 5 min, 15 min); after 25 failures patterns stay disabled
      until a password login through greetd or `sudo eva-pattern reset`.
      Enroll with `sudo eva-pattern setup`; credentials stay outside the Nix store.
    '';
  };
  config = lib.mkIf (config.programs.eva.enable && cfg.enable) {
    environment.systemPackages = [ package ];
    security.wrappers.eva-pattern-check = {
      source = "${package}/libexec/eva-pattern-check";
      owner = "root";
      group = "root";
      setuid = true;
    };
    security.pam.services.eva-lock.rules.auth.eva-pattern = rule;
    security.pam.services.greetd.rules.auth.eva-pattern = rule;
    security.pam.services.greetd.rules.account.eva-pattern-reset = reset;
  };
}

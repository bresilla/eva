{ config, lib, pkgs, ... }:
let
  sudo = config.security.pam.services.sudo.rules;
  authStep = pkgs.writeShellScript "eva-auth-step" (builtins.replaceStrings
    [ "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
    [ "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux ]}" ]
    (builtins.readFile ../../helpers/pam/eva-auth-step));
  marker = order: step: {
    inherit order;
    control = "optional";
    modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
    args = [ "quiet" "${authStep}" step ];
  };
in
{
  config = lib.mkIf config.programs.eva.enable {
    security.polkit.enable = true;
    services.gnome.gnome-keyring.enable = true;

    security.pam.services = {
      greetd = {
        enableGnomeKeyring = true;
        fprintAuth = false;
      };
      eva-lock = {
        enableGnomeKeyring = true;
        fprintAuth = false;
      };
      eva-lock-finger = lib.mkIf config.services.fprintd.enable {
        text = ''
          auth sufficient ${config.services.fprintd.package}/lib/security/pam_fprintd.so
          auth required ${config.security.pam.package}/lib/security/pam_deny.so
          account include eva-lock
        '';
      };
      # The validators remain NixOS's PAM rules. These optional markers only
      # report progress to the shell; they never receive the password.
      sudo.rules = lib.mkIf config.security.sudo.enable {
        auth.eva-finger = (marker (sudo.auth.fprintd.order - 1) "finger") // {
          enable = sudo.auth.fprintd.enable;
        };
        auth.eva-password = marker
          ((if sudo.auth.unix-early.enable or false
            then sudo.auth.unix-early.order else sudo.auth.unix.order) - 1)
          "password";
        account.eva-ok = marker (sudo.account.unix.order + 1) "ok";
      };
    };
  };
}

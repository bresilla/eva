# The test machine: eva enabled with every part the checks evaluate.
{ pkgs, ... }:
{
  programs.eva = {
    enable = true;
    user = "eva";
    lulePackage = pkgs.hello;
    pattern.enable = true;
    phone.enable = true;
  };
  users.users.eva.isNormalUser = true;
  boot.loader.grub.enable = false;
  fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
  system.stateVersion = "25.05";
}

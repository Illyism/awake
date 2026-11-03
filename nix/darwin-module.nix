self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.awake;
in
{
  options.services.awake = {
    enable = lib.mkEnableOption "Awake lid-closed keep-awake CLI and sudoers rule";
    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.awake;
      description = "The Awake package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.etc."sudoers.d/awake" = {
      text = ''
        # Managed by nix-darwin (services.awake)
        %admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
      '';
    };
  };
}

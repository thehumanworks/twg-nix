{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.twg;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.sessionVariables = import ../lib/environment.nix { inherit lib cfg; };
  };
}

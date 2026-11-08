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
    home.packages = [ cfg.package ];
    home.sessionVariables = import ../lib/environment.nix { inherit lib cfg; };
  };
}

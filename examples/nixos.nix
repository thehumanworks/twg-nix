{ inputs, ... }:
{
  imports = [ inputs.twg.nixosModules.default ];

  nixpkgs.config.allowUnfreePredicate =
    package: builtins.elem (inputs.nixpkgs.lib.getName package) [ "twg" ];

  # Credentials and config remain separate for each user.
  programs.twg.enable = true;

  # Prefer per-user Home Manager options on a multi-user system.
  # programs.twg.site = "example.atlassian.net";
}

{ inputs, ... }:
{
  imports = [ inputs.twg.homeManagerModules.default ];

  # The CLI is distributed as an unfree binary.
  nixpkgs.config.allowUnfreePredicate =
    package: builtins.elem (inputs.nixpkgs.lib.getName package) [ "twg" ];

  programs.twg = {
    enable = true;
    site = "example.atlassian.net";
    # profile = "work"; # Select an existing profile created with twg login.
  };
}

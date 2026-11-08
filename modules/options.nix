{
  lib,
  pkgs,
  ...
}:
let
  runtimeDirectory = lib.types.nullOr (
    lib.types.addCheck (lib.types.strMatching "/.*") (
      directory: directory != builtins.storeDir && !(lib.hasPrefix "${builtins.storeDir}/" directory)
    )
  );
in
{
  options.programs.twg = {
    enable = lib.mkEnableOption "the Atlassian Teamwork Graph CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.twg or (pkgs.callPackage ../package.nix { });
      defaultText = lib.literalExpression "pkgs.twg or (pkgs.callPackage ../package.nix { })";
      description = ''
        Teamwork Graph CLI package to install. The bundled package is used when
        no overlay supplies pkgs.twg. Allow the unfree twg package in Nixpkgs,
        or supply the flake's preconfigured package explicitly.
      '';
    };

    site = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "example.atlassian.net";
      description = "Default Atlassian site (TWG_SITE). Null preserves the CLI's saved default.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "you@example.com";
      description = ''
        Default account for Basic authentication (TWG_USER). Leave null for
        browser-based OAuth; setting this variable can change auth resolution.
      '';
    };

    profile = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "work";
      description = "Saved login profile to select (TWG_PROFILE). Does not create a login profile.";
    };

    configDir = lib.mkOption {
      type = runtimeDirectory;
      default = null;
      example = "/home/alice/.config/twg";
      description = ''
        Writable, absolute runtime config directory (TWG_CONFIG_DIR). Null uses
        the CLI's XDG default. Do not point this at the Nix store: it holds
        mutable credentials, consent, and installation metadata.
      '';
    };

    cacheDir = lib.mkOption {
      type = runtimeDirectory;
      default = null;
      example = "/home/alice/.cache/twg";
      description = "Writable, absolute cache directory (TWG_CACHE_DIR). Null uses the CLI's XDG default.";
    };

    skillsDir = lib.mkOption {
      type = runtimeDirectory;
      default = null;
      example = "/home/alice/.agents/skills";
      description = ''
        Absolute directory for manually installed agent skills (TWG_SKILLS_DIR).
        This module does not install skills or modify agent configuration.
      '';
    };

    secretStore = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "file"
          "keychain"
        ]
      );
      default = null;
      example = "keychain";
      description = ''
        Authentication storage backend during login/migration (TWG_SECRET_STORE).
        Null preserves upstream selection. Does not provision a keychain service.
      '';
    };

    agentDefaults = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      example = true;
      description = ''
        Enable or disable agent-oriented output defaults (TWG_AGENT_DEFAULTS).
        Null leaves the environment unchanged. Set only for agent hosts, not
        ordinary interactive shells.
      '';
    };
  };
}

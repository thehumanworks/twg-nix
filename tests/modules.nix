{
  pkgs,
  self,
  nixpkgs,
  home-manager,
}:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  package = self.packages.${system}.twg;
  customPackage = pkgs.writeShellScriptBin "twg" "exit 0";

  baseHome = {
    home = {
      username = "twg-test";
      homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/twg-test" else "/home/twg-test";
      stateVersion = "26.05";
    };
  };
  mkHome =
    settings:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.default
        baseHome
        {
          programs.twg = {
            enable = true;
          }
          // settings;
        }
      ];
    };

  configured = {
    site = "example.atlassian.net";
    user = "test@example.com";
    profile = "work";
    configDir = "/runtime/twg/config";
    cacheDir = "/runtime/twg/cache";
    skillsDir = "/runtime/agent-skills";
    secretStore = "file";
    agentDefaults = true;
  };
  expectedEnvironment = {
    TWG_SITE = "example.atlassian.net";
    TWG_USER = "test@example.com";
    TWG_PROFILE = "work";
    TWG_CONFIG_DIR = "/runtime/twg/config";
    TWG_CACHE_DIR = "/runtime/twg/cache";
    TWG_SKILLS_DIR = "/runtime/agent-skills";
    TWG_SECRET_STORE = "file";
    TWG_AGENT_DEFAULTS = "1";
  };
  names = builtins.attrNames expectedEnvironment;
  selectEnvironment =
    environment: lib.filterAttrs (name: _value: lib.hasPrefix "TWG_" name) environment;
  home = mkHome configured;
  defaults = mkHome { };
  disabled = mkHome (configured // { enable = false; });
  custom = mkHome { package = customPackage; };
  explicitFalse = mkHome { agentDefaults = false; };

  baseSystem = {
    nixpkgs.hostPlatform = system;
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "/dev/disk/by-label/test-root";
      fsType = "ext4";
    };
    system.stateVersion = "26.05";
  };
  mkSystem =
    settings:
    nixpkgs.lib.nixosSystem {
      modules = [
        self.nixosModules.default
        baseSystem
        {
          nixpkgs.pkgs = pkgs;
          programs.twg = {
            enable = true;
          }
          // settings;
        }
      ];
    };
  enabledSystem = mkSystem configured;
  disabledSystem = mkSystem (configured // { enable = false; });
  customSystem = mkSystem { package = customPackage; };
  integratedSystem = nixpkgs.lib.nixosSystem {
    modules = [
      baseSystem
      home-manager.nixosModules.home-manager
      {
        nixpkgs.pkgs = pkgs;
        users.users.twg-test.isNormalUser = true;
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          sharedModules = [ self.homeManagerModules.default ];
          users.twg-test = {
            home.stateVersion = "26.05";
            programs.twg = {
              enable = true;
              site = "example.atlassian.net";
            };
          };
        };
      }
    ];
  };

  rejects =
    settings:
    !(builtins.tryEval (builtins.deepSeq (mkHome settings).config.home.sessionVariables true)).success;

  exampleHome = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.inputs = {
      inherit nixpkgs;
      twg = self;
    };
    modules = [
      baseHome
      ../examples/home-manager.nix
    ];
  };
  exampleSystem = nixpkgs.lib.nixosSystem {
    specialArgs.inputs = {
      inherit nixpkgs;
      twg = self;
    };
    modules = [
      baseSystem
      ../examples/nixos.nix
    ];
  };
  overlayPkgs = import nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
    config.allowUnfreePredicate = pkg: lib.getName pkg == "twg";
  };
  report = {
    homeManager = {
      installsPackage = builtins.elem package home.config.home.packages;
      bundledPackageNeedsNoOverlay = home.config.programs.twg.package.drvPath == package.drvPath;
      exportsOnlyConfiguredValues =
        selectEnvironment home.config.home.sessionVariables == expectedEnvironment;
      defaultsDoNotOverrideRuntime = selectEnvironment defaults.config.home.sessionVariables == { };
      disabledDoesNotInstall = !(builtins.elem package disabled.config.home.packages);
      disabledDoesNotExport = selectEnvironment disabled.config.home.sessionVariables == { };
      packageCanBeOverridden = builtins.elem customPackage custom.config.home.packages;
      agentDefaultsCanBeExplicitlyDisabled =
        explicitFalse.config.home.sessionVariables.TWG_AGENT_DEFAULTS == "0";
      doesNotOwnMutableConfig =
        !(builtins.any (name: name == "twg" || lib.hasPrefix "twg/" name) (
          builtins.attrNames home.config.xdg.configFile
        ));
      noActivationSideEffects =
        !(builtins.any (lib.hasPrefix "twg") (builtins.attrNames home.config.home.activation));
      exampleEvaluates = builtins.isString exampleHome.activationPackage.drvPath;
      badConfigDirRejected = rejects { configDir = "~/.config/twg"; };
      badCacheDirRejected = rejects { cacheDir = "relative/cache"; };
      storeConfigDirRejected = rejects { configDir = "${package}/config"; };
      storeCacheDirRejected = rejects { cacheDir = builtins.storeDir; };
      storeSkillsDirRejected = rejects { skillsDir = "${package}/skills"; };
      badSecretStoreRejected = rejects { secretStore = "plaintext"; };
    };
    overlay = {
      suppliesSamePackage = overlayPkgs.twg.drvPath == package.drvPath;
      defaultPackageMatches = self.packages.${system}.default.drvPath == package.drvPath;
    };
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    nixos = {
      installsPackage = builtins.elem package enabledSystem.config.environment.systemPackages;
      exportsOnlyConfiguredValues =
        builtins.intersectAttrs expectedEnvironment enabledSystem.config.environment.sessionVariables
        == expectedEnvironment;
      disabledDoesNotInstall = !(builtins.elem package disabledSystem.config.environment.systemPackages);
      disabledDoesNotExport = builtins.all (
        name: !(builtins.hasAttr name disabledSystem.config.environment.sessionVariables)
      ) names;
      packageCanBeOverridden = builtins.elem customPackage customSystem.config.environment.systemPackages;
      noSystemService =
        !(builtins.any (lib.hasPrefix "twg") (builtins.attrNames enabledSystem.config.systemd.services));
      integratedHomeManagerWorks =
        builtins.elem package integratedSystem.config.home-manager.users.twg-test.home.packages
        &&
          integratedSystem.config.home-manager.users.twg-test.home.sessionVariables.TWG_SITE
          == "example.atlassian.net"
        && !(integratedSystem.config.environment.sessionVariables ? TWG_SITE)
        && builtins.isString integratedSystem.config.system.build.toplevel.drvPath;
      exampleEvaluates = builtins.isString exampleSystem.config.system.build.toplevel.drvPath;
    };
  };
  failures = lib.concatLists (
    lib.mapAttrsToList (
      group: cases:
      lib.mapAttrsToList (name: _value: "${group}.${name}") (lib.filterAttrs (_name: value: !value) cases)
    ) report
  );
in
assert lib.assertMsg (
  failures == [ ]
) "twg module contract failed: ${lib.concatStringsSep ", " failures}";
pkgs.runCommand "twg-module-checks"
  {
    reportJSON = builtins.toJSON report;
    passAsFile = [ "reportJSON" ];
  }
  ''
    cp "$reportJSONPath" "$out"
  ''

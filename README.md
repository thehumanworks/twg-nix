# Teamwork Graph CLI for Nix

A Nix package, flake, Home Manager module, and NixOS module for Atlassian's
**Teamwork Graph CLI**, whose executable is `twg`.

This replaces the binary-installation part of:

```sh
curl -fsSL --retry 2 https://teamwork-graph.atlassian.com/cli/install | bash
```

The installer is **never executed**. The package fetches versioned binaries from
Atlassian's CDN with pinned SHA-256 hashes, patches the Linux interpreter for
NixOS, and installs upstream-generated Bash, Zsh, and Fish completions.
No shell profiles, credentials, agent configuration, or home directories are
modified during a build or module activation.

## Quick start

From this checkout:

```sh
nix run . -- --version
nix run . -- --help
nix shell .#twg                  # opens a shell with twg on PATH
nix build .#twg                  # creates result/bin/twg
```

The pinned release is **1.4.4**. Supported native platforms:

| Nix system | Upstream artifact |
| --- | --- |
| `x86_64-linux` | `twg-linux-x64` |
| `aarch64-linux` | `twg-linux-arm64` |
| `x86_64-darwin` | `twg-darwin-x64` |
| `aarch64-darwin` | `twg-darwin-arm64` |

The flake pins Nixpkgs and Home Manager **26.05** to retain Intel macOS support;
Nixpkgs 26.11/unstable has dropped that platform. On Intel macOS, do not follow an
unsupported Nixpkgs input: retain this flake's pin or follow a compatible 26.05
input instead.

Completions are generated on native builds. Cross builds do not run the target
executable, so they omit generated completions and runtime install checks.

The upstream binary is treated as **unfree**. The flake's own package outputs
allow only `twg`; module and overlay users must allow it in their own Nixpkgs
configuration. If you already have an unfree predicate, add `twg` to that
allowlist rather than replacing it. This repository does not grant rights to
redistribute Atlassian's binaries.

## Add the flake input

Add this to your configuration flake's `inputs`, replacing the local path with
the location of this checkout (or its Git URL after you publish it):

```nix
twg = {
  url = "path:/absolute/path/to/twg";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Home Manager

Add the module to your Home Manager configuration's imports, and enable it:

```nix
{ inputs, lib, ... }:
{
  imports = [ inputs.twg.homeManagerModules.default ];

  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "twg";

  programs.twg = {
    enable = true;
    site = "example.atlassian.net";
    # profile = "work"; # Only after creating that login profile.
  };
}
```

Pass `inputs` via `extraSpecialArgs = { inherit inputs; };` when calling
`home-manager.lib.homeManagerConfiguration`. See
[`examples/home-manager.nix`](examples/home-manager.nix).

For Home Manager integrated into NixOS, pass it using
`home-manager.extraSpecialArgs = { inherit inputs; };`. If
`home-manager.useGlobalPkgs = true`, put the unfree allowance in the **NixOS**
`nixpkgs.config` rather than the Home Manager configuration.

### NixOS

```nix
{ inputs, lib, ... }:
{
  imports = [ inputs.twg.nixosModules.default ];

  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "twg";

  programs.twg.enable = true;
}
```

Pass `inputs` with `specialArgs = { inherit inputs; };` in
`nixpkgs.lib.nixosSystem`. See [`examples/nixos.nix`](examples/nixos.nix).

This installs `twg` system-wide; authentication and mutable state remain per-user.
**No system service is created**: this is a CLI, not a daemon. Prefer Home Manager
for account, site, profile, and directory settings on multi-user machines.
There is no need to enable both modules for the same user.

### Package selection and overlay

Neither module requires an overlay. Their default package is `pkgs.twg` if
available, otherwise the bundled `package.nix`.

Optionally expose `pkgs.twg` throughout your configuration:

```nix
nixpkgs.overlays = [ inputs.twg.overlays.default ];
```

Override the module's package explicitly if desired:

```nix
programs.twg.package = inputs.twg.packages.${pkgs.stdenv.hostPlatform.system}.twg;
```

That package output uses this flake's narrowly scoped unfree allowance; it does
not require changing your caller's unfree configuration. For non-flake use,
`pkgs.callPackage /path/to/twg/package.nix { }` works with an appropriate
Nixpkgs unfree allowance.

## Module options

Both modules expose the same `programs.twg` options:

| Option | Default | Effect |
| --- | --- | --- |
| `enable` | `false` | Install the package and export configured variables |
| `package` | bundled package / `pkgs.twg` | Select the package to install |
| `site` | `null` | `TWG_SITE`: site prefix, hostname, or cloud ID |
| `user` | `null` | `TWG_USER`: Basic-auth account; leave unset for normal OAuth |
| `profile` | `null` | `TWG_PROFILE`: select an existing login profile |
| `configDir` | `null` | `TWG_CONFIG_DIR`: writable configuration/credential directory |
| `cacheDir` | `null` | `TWG_CACHE_DIR`: writable cache directory |
| `skillsDir` | `null` | `TWG_SKILLS_DIR`: location for manually installed agent skills |
| `secretStore` | `null` | `TWG_SECRET_STORE`: `"file"` or `"keychain"` during login/migration |
| `agentDefaults` | `null` | `TWG_AGENT_DEFAULTS`: enable (`true`) or disable (`false`) agent defaults |

`null` means **do not export the variable**, preserving the CLI's saved settings
and environment defaults. Disabled modules do not install or export anything.

Directory values must be absolute runtime paths outside the Nix store; tilde
and shell-variable expansion is not performed. For example, in Home Manager:

```nix
programs.twg.configDir = "${config.home.homeDirectory}/.config/twg";
```

Home Manager uses `home.sessionVariables`; NixOS uses
`environment.sessionVariables`. Start a new login session after applying
changes. These are session defaults, not settings for arbitrary system services.

The upstream defaults are `$XDG_CONFIG_HOME/twg` (falling back to
`~/.config/twg`), `$XDG_CACHE_HOME/twg` (falling back to `~/.cache/twg`), and
`~/.agents/skills`. Directories are managed by the CLI at runtime, not symlinked
to read-only store files. Selecting `"keychain"` does not configure a desktop
keyring service.

Completions are installed in standard package locations. Enable completion
support in your normal Bash/Zsh/Fish configuration; the modules do not enable or
reconfigure your shell for you.

## Authentication, skills, and upstream setup

After installing, run these yourself in a terminal:

```sh
twg login
twg doctor
```

Login handles browser authorization and runtime consent. Neither module logs
in, accepts terms, installs agent skills, or creates an upstream maintenance
schedule.

For agent skills, use `twg skills install` explicitly. The broader `twg setup`
flow can also install skills and enable upstream upkeep; review those choices
because those changes are **not Nix-managed**.

**Never put tokens, passwords, or credential contents in Nix expressions.** There
is deliberately no token option. Use the CLI's runtime credential store, or
provide `TWG_TOKEN` (and `TWG_USER` for Basic auth) through your existing runtime
secret-management mechanism. Nix store contents are generally world-readable.

Upstream runtime telemetry is not changed by this package. To opt out for a
command without affecting other applications:

```sh
DO_NOT_TRACK=1 twg --help
```

## Updates and removal

Use Nix to update or remove the executable, **not** `twg upgrade` or
`twg uninstall`: the installed executable lives in the read-only Nix store.

- Consumers: update the `twg` flake input and rebuild your configuration.
- Maintainers: run the updater below, commit `sources.json`, then publish.
- To remove: disable the module and rebuild, or remove your Nix profile entry.
  Existing runtime credentials, caches, and skills are intentionally retained.
- Previously enabled upstream upkeep is not removed by these modules; use
  `twg upkeep disable` if you no longer want that per-user schedule.

Updating Nixpkgs alone does not change the CLI version. The CLI's release pin is
independent of `flake.lock`.

## Development and verification

```sh
nix develop
python3 scripts/update.py          # latest stable manifest; run from repo root
python3 scripts/update.py 1.4.4    # pin a specific stable release
python3 scripts/update.py --check # verify all downloads without writing
nix fmt
nix flake check --print-build-logs
nix flake check --all-systems --no-build
```

The updater downloads and hashes all four binaries, rejects malformed, missing,
or duplicate checksums, and only replaces `sources.json` after every binary has
verified. It does not run the installer or downloaded binaries.

Checks cover the installed version/help, generated and live shell completions,
Home Manager and NixOS module contracts (including disabled and overridden
packages), example evaluation, Nix formatting/linting, and updater unit tests.
CI is configured for native Linux and macOS runners on both architectures.

No network-authenticated API calls or interactive login are exercised by the
checks.

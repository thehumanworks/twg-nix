{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  makeBinaryWrapper,
  xdg-utils,
  python3,
}:
let
  release = builtins.fromJSON (builtins.readFile ./sources.json);
  platform =
    release.platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "twg: unsupported platform ${stdenvNoCC.hostPlatform.system}");
  canExecute = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
in
stdenvNoCC.mkDerivation {
  pname = "twg";
  inherit (release) version;

  src = fetchurl {
    url = "https://teamwork-graph.atlassian.com/cli/twg-${platform.asset}-v${release.version}";
    inherit (platform) hash;
  };

  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Bun's standalone executable contains the application payload; stripping it
  # destroys that payload.
  dontStrip = true;
  # Patch explicitly before running the CLI to generate completions. The hook's
  # automatic postFixup callback would otherwise run after our postFixup.
  dontAutoPatchelf = true;

  nativeBuildInputs = [
    installShellFiles
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
    autoPatchelfHook
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/twg"
    runHook postInstall
  '';

  postFixup =
    lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
      autoPatchelf "$out/bin/twg"
      wrapProgram "$out/bin/twg" \
        --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
    ''
    + lib.optionalString canExecute ''
      export HOME="$(mktemp -d)"
      export XDG_CONFIG_HOME="$HOME/.config"
      export XDG_CACHE_HOME="$HOME/.cache"
      export DO_NOT_TRACK=1

      "$out/bin/twg" completion script bash > twg.bash
      "$out/bin/twg" completion script zsh > _twg
      "$out/bin/twg" completion script fish > twg.fish
      installShellCompletion --bash --name twg twg.bash
      installShellCompletion --zsh _twg
      installShellCompletion --fish twg.fish
    '';

  doInstallCheck = canExecute;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$(mktemp -d)"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export DO_NOT_TRACK=1

    test "$("$out/bin/twg" --version)" = "${release.version}"
    "$out/bin/twg" --help > help.txt
    grep -F "Teamwork Graph" help.txt
    for completion in \
      "$out/share/bash-completion/completions/twg" \
      "$out/share/zsh/site-functions/_twg" \
      "$out/share/fish/vendor_completions.d/twg.fish"; do
      test -s "$completion"
    done
    runHook postInstallCheck
  '';

  passthru.updateScript = [
    (lib.getExe python3)
    ./scripts/update.py
  ];

  meta = {
    description = "Command-line interface to Atlassian Teamwork Graph and Cloud services";
    homepage = "https://teamwork-graph.atlassian.com";
    changelog = "https://teamwork-graph.atlassian.com/cli/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "twg";
    platforms = builtins.attrNames release.platforms;
  };
}

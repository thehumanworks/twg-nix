{ pkgs, package }:
pkgs.runCommand "twg-completion-checks"
  {
    nativeBuildInputs = [
      package
      pkgs.bash
      pkgs.zsh
      pkgs.fish
      pkgs.python3
    ];
    TWG_PACKAGE = package;
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export DO_NOT_TRACK=1
    mkdir -p "$HOME"

    python3 ${./completions.py}
    touch "$out"
  ''

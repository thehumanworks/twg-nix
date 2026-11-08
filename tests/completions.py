"""Exercise upstream completions in their actual shell/terminal context."""

import errno
import os
import pty
import shlex
import subprocess
import unittest
from pathlib import Path

PACKAGE = Path(os.environ["TWG_PACKAGE"])
BASH_COMPLETION = shlex.quote(str(PACKAGE / "share/bash-completion/completions/twg"))
ZSH_COMPLETIONS = shlex.quote(str(PACKAGE / "share/zsh/site-functions"))
FISH_COMPLETION = shlex.quote(str(PACKAGE / "share/fish/vendor_completions.d/twg.fish"))


class CompletionTests(unittest.TestCase):
    def complete(self, command):
        # twg deliberately emits no candidates unless stdout or stderr is a TTY.
        # Give stderr a PTY while keeping stdout machine-readable, as real shell
        # command substitutions do. This does not run login or answer prompts.
        master, terminal = pty.openpty()
        try:
            result = subprocess.run(
                command, stdout=subprocess.PIPE, stderr=terminal, text=True, timeout=30
            )
            os.close(terminal)
            terminal = None
            os.set_blocking(master, False)
            errors = bytearray()
            while True:
                try:
                    chunk = os.read(master, 65536)
                except BlockingIOError:
                    break
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                errors.extend(chunk)
            self.assertEqual(result.returncode, 0, errors.decode(errors="replace"))
            return result.stdout.splitlines()
        finally:
            if terminal is not None:
                os.close(terminal)
            os.close(master)

    def test_bash_and_fish_syntax(self):
        for command in (
            ["bash", "-n", str(PACKAGE / "share/bash-completion/completions/twg")],
            ["fish", "-n", str(PACKAGE / "share/fish/vendor_completions.d/twg.fish")],
        ):
            with self.subTest(command=command):
                subprocess.run(command, check=True, capture_output=True, text=True)

    def test_live_command_completion(self):
        for words, expected in ((["ji"], "jira"), (["jira", "worki"], "workitem")):
            with self.subTest(words=words):
                self.assertIn(expected, self.complete(["twg", "__complete", "--", *words]))

    def test_bash_completion(self):
        for words, expected in ((["ji"], "jira"), (["jira", "worki"], "workitem")):
            script = (
                f"source {BASH_COMPLETION}; "
                f"COMP_WORDS=(twg {shlex.join(words)}); "
                f"COMP_CWORD={len(words)}; "
                '_twg_completion; printf "%s\\n" "${COMPREPLY[@]}"'
            )
            with self.subTest(words=words):
                self.assertIn(
                    expected, self.complete(["bash", "--noprofile", "--norc", "-c", script])
                )

    def test_zsh_completion(self):
        # Zsh's noexec mode mis-parses the generated arithmetic array slice.
        # Autoload and execute the actual function with completion context
        # instead: this checks its syntax AND the resulting live candidates.
        for words, expected in ((["ji"], "jira"), (["jira", "worki"], "workitem")):
            script = (
                f"fpath=({ZSH_COMPLETIONS} $fpath); autoload -Uz _twg; "
                '_describe() { print -rl -- "${candidates[@]}"; }; '
                f"words=(twg {shlex.join(words)}); CURRENT={len(words) + 1}; "
                f"PREFIX={shlex.quote(words[-1])}; _twg"
            )
            with self.subTest(words=words):
                self.assertIn(expected, self.complete(["zsh", "-f", "-c", script]))

    def test_fish_completion(self):
        for words, expected in ((["ji"], "jira"), (["jira", "worki"], "workitem")):
            script = (
                f"source {FISH_COMPLETION}; complete -C {shlex.quote('twg ' + shlex.join(words))}"
            )
            with self.subTest(words=words):
                self.assertIn(expected, self.complete(["fish", "--no-config", "-c", script]))


if __name__ == "__main__":
    unittest.main(verbosity=2)

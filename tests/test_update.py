import base64
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "twg_update", Path(__file__).resolve().parent.parent / "scripts/update.py"
)
update = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update)


class UpdateTests(unittest.TestCase):
    def test_checksums_allow_sha256sum_and_shasum_formats(self):
        digest = "ab" * 32
        text = f"{digest}  a\r\n{digest.upper()} *b\r\n"
        self.assertEqual(update.parse_checksums(text, ["a", "b"]), {"a": digest, "b": digest})

    def test_checksums_reject_missing_duplicate_and_invalid(self):
        digest = "ab" * 32
        for text in ("", f"{digest} a\n{digest} a", "not-a-digest a"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                update.parse_checksums(text, ["a"])

    def test_version_is_validated_before_network_access(self):
        with patch.object(update, "read_url") as fetch:
            for version in ("", "../install", "v1.2.3", "1.2", "01.2.3", "1.2.3-beta"):
                with self.subTest(version=version), self.assertRaises(ValueError):
                    update.release_sources(version)
            fetch.assert_not_called()

    def test_download_hash_is_checked(self):
        content = b"test artifact"
        digest = hashlib.sha256(content).hexdigest()
        with patch.object(update.urllib.request, "urlopen", return_value=io.BytesIO(content)):
            update.verify_download("https://example.invalid/binary", digest)
        with (
            patch.object(update.urllib.request, "urlopen", return_value=io.BytesIO(content)),
            self.assertRaisesRegex(ValueError, "Checksum mismatch"),
        ):
            update.verify_download("https://example.invalid/binary", "00" * 32)

    def test_release_covers_and_verifies_all_platforms(self):
        digest = "ab" * 32
        sums = "\n".join(f"{digest}  twg-{asset}-v1.2.3" for asset in update.ASSETS.values())
        with (
            patch.object(update, "read_url", return_value=sums),
            patch.object(update, "verify_download") as verify,
        ):
            sources = update.release_sources("1.2.3")
        self.assertEqual(verify.call_count, 4)
        self.assertEqual(set(sources["platforms"]), set(update.ASSETS))
        self.assertEqual(sources["version"], "1.2.3")
        for system, asset in update.ASSETS.items():
            self.assertEqual(sources["platforms"][system]["asset"], asset)
            self.assertEqual(
                sources["platforms"][system]["hash"],
                "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode("ascii"),
            )

    def test_main_writes_only_a_fully_verified_release(self):
        sources = {"version": "1.2.3", "platforms": {}}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "sources.json"
            target.write_text('{"version": "old"}\n')
            with (
                patch.object(update, "SOURCES", target),
                patch.object(update, "release_sources", return_value=sources),
                patch.object(update.sys, "argv", ["update.py", "1.2.3"]),
            ):
                update.main()
            self.assertEqual(json.loads(target.read_text()), sources)
            self.assertEqual(target.stat().st_mode & 0o777, 0o644)
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_failed_release_leaves_pin_unchanged(self):
        digest = "ab" * 32
        sums = "\n".join(f"{digest}  twg-{asset}-v1.2.3" for asset in update.ASSETS.values())
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "sources.json"
            original = '{"version": "old"}\n'
            target.write_text(original)
            with (
                patch.object(update, "SOURCES", target),
                patch.object(update, "read_url", return_value=sums),
                patch.object(update, "verify_download", side_effect=[None, ValueError("bad hash")]),
                patch.object(update.sys, "argv", ["update.py", "1.2.3"]),
                self.assertRaisesRegex(ValueError, "bad hash"),
            ):
                update.main()
            self.assertEqual(target.read_text(), original)
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_check_does_not_write_and_detects_changes(self):
        sources = {"version": "1.2.3", "platforms": {}}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "sources.json"
            original = json.dumps(sources)
            target.write_text(original)
            with (
                patch.object(update, "SOURCES", target),
                patch.object(update, "release_sources", return_value=sources),
                patch.object(update.sys, "argv", ["update.py", "1.2.3", "--check"]),
            ):
                update.main()
                self.assertEqual(target.read_text(), original)
                target.write_text("{}")
                with self.assertRaisesRegex(ValueError, "differs"):
                    update.main()
                self.assertEqual(target.read_text(), "{}")

    def test_checked_in_sources_have_all_platforms_and_valid_hashes(self):
        sources = json.loads((Path(__file__).resolve().parent.parent / "sources.json").read_text())
        self.assertRegex(sources["version"], "^" + update.VERSION.pattern + "$")
        self.assertEqual(set(sources["platforms"]), set(update.ASSETS))
        for system, asset in update.ASSETS.items():
            source = sources["platforms"][system]
            self.assertEqual(source["asset"], asset)
            algorithm, digest = source["hash"].split("-", 1)
            self.assertEqual(algorithm, "sha256")
            self.assertEqual(len(base64.b64decode(digest, validate=True)), 32)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Update sources.json from Atlassian's stable release and verify every binary."""

import argparse
import base64
import hashlib
import json
import re
import sys
import tempfile
import urllib.request
from pathlib import Path

BASE_URL = "https://teamwork-graph.atlassian.com/cli"
# The passthru updateScript is copied to the store; update the calling checkout.
SOURCES = Path.cwd() / "sources.json"
ASSETS = {
    "aarch64-darwin": "darwin-arm64",
    "aarch64-linux": "linux-arm64",
    "x86_64-darwin": "darwin-x64",
    "x86_64-linux": "linux-x64",
}
VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", re.ASCII)


def read_url(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read().decode("utf-8")


def parse_checksums(text, filenames):
    """Require one well-formed checksum for each expected artifact."""
    wanted = set(filenames)
    checksums = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        digest, filename = fields
        filename = filename.removeprefix("*")
        if filename not in wanted:
            continue
        if filename in checksums:
            raise ValueError(f"Duplicate checksum for {filename}")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", digest, re.ASCII):
            raise ValueError(f"Invalid SHA-256 for {filename}")
        checksums[filename] = digest.lower()
    missing = wanted - checksums.keys()
    if missing:
        raise ValueError(f"Missing checksums: {', '.join(sorted(missing))}")
    return checksums


def verify_download(url, expected):
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f"Checksum mismatch for {url}")


def release_sources(version):
    if not VERSION.fullmatch(version):
        raise ValueError(f"Expected a stable version like 1.4.4, got {version!r}")
    filenames = {system: f"twg-{asset}-v{version}" for system, asset in ASSETS.items()}
    checksums = parse_checksums(read_url(f"{BASE_URL}/SHA256SUMS-v{version}"), filenames.values())
    platforms = {}
    for system, asset in ASSETS.items():
        filename = filenames[system]
        expected = checksums[filename]
        print(f"Verifying {filename}...", file=sys.stderr)
        verify_download(f"{BASE_URL}/{filename}", expected)
        platforms[system] = {
            "asset": asset,
            "hash": "sha256-" + base64.b64encode(bytes.fromhex(expected)).decode("ascii"),
        }
    return {"version": version, "platforms": platforms}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", help="stable release (default: stable manifest)")
    parser.add_argument(
        "--check", action="store_true", help="verify upstream and fail if sources.json differs"
    )
    args = parser.parse_args()
    version = args.version
    if version is None:
        version = json.loads(read_url(f"{BASE_URL}/manifest.json"))["version"]
    sources = release_sources(version)
    if args.check:
        if json.loads(SOURCES.read_text()) != sources:
            raise ValueError("sources.json differs from the verified upstream release")
        print(f"sources.json matches verified release {version}")
        return

    # No partial updates: replace the pin only after every platform verifies.
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=SOURCES.parent, delete=False
    ) as output:
        temporary = Path(output.name)
        try:
            output.write(json.dumps(sources, indent=2) + "\n")
            output.flush()
            temporary.chmod(0o644)
            temporary.replace(SOURCES)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"Updated {SOURCES} to {version}; run nix flake check next.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"update: {error}")

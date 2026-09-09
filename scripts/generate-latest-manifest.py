#!/usr/bin/env python3
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate public/latest.json from real release artifacts.

Reads the exact published files, hashes them, and writes the updater manifest
atomically. Never hard-codes versions: everything comes from argv plus the
files on disk. Fails (nonzero) unless every --require asset is present, so a
failed build can never advance latest.json.

Asset discovery: each --asset takes key=path, e.g.
  linux-x86_64-appimage=Tipsy-1.2.3-x86_64.AppImage
URLs are built as <release-base>/<basename> where --release-base is the real
GitHub Release download base (https://github.com/<owner>/Tipsy-repo/releases/download/<tag>/).
"""
import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Generic arch -> ecosystem arch names. Extend when Tipsy gains targets.
ARCH_MAP = {
    "x86_64": {"generic": "x86_64", "debian": "amd64", "rpm": "x86_64", "flatpak": "x86_64"},
    "aarch64": {"generic": "aarch64", "debian": "arm64", "rpm": "aarch64", "flatpak": "aarch64"},
}

REQUIRED_DEFAULT = ("linux-x86_64-appimage", "linux-x86_64-deb", "linux-x86_64-rpm")


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Generate Tipsy latest.json")
    parser.add_argument("--version", required=True, help="App version without v prefix, e.g. 1.2.3")
    parser.add_argument("--tag", required=True, help="Release tag, e.g. v1.2.3")
    parser.add_argument("--channel", default="stable", choices=("stable", "beta", "nightly"))
    parser.add_argument("--owner", required=True, help="GitHub owner, e.g. 32bitx64bit")
    parser.add_argument("--distro-repo", default="Tipsy-repo")
    parser.add_argument("--pages-base", required=True, help="Pages base URL, e.g. https://OWNER.github.io/Tipsy-repo")
    parser.add_argument("--asset", action="append", default=[], metavar="key=path",
                        help="Manifest key mapped to a real file (repeatable)")
    parser.add_argument("--require", action="append", default=[],
                        help="Manifest key required to be present (repeatable; default: appimage+deb+rpm)")
    parser.add_argument("--output", required=True, help="Destination latest.json path")
    parser.add_argument("--published-at", default="",
                        help="ISO-8601 timestamp; defaults to current UTC time")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if not args.version or args.version.startswith("v"):
        print("generate-latest-manifest: --version must omit the v prefix", file=sys.stderr)
        return 1
    release_base = f"https://github.com/{args.owner}/{args.distro_repo}/releases/download/{args.tag}"
    if not release_base.startswith("https://"):
        print("generate-latest-manifest: release base must be HTTPS", file=sys.stderr)
        return 1

    assets = {}
    seen_paths = set()
    for item in args.asset:
        if "=" not in item:
            print(f"generate-latest-manifest: bad --asset {item!r}, want key=path", file=sys.stderr)
            return 1
        key, raw_path = item.split("=", 1)
        path = Path(raw_path)
        if not path.is_file():
            print(f"generate-latest-manifest: asset file missing for {key}: {raw_path}", file=sys.stderr)
            return 1
        if key in assets:
            print(f"generate-latest-manifest: duplicate asset key {key}", file=sys.stderr)
            return 1
        resolved = str(path.resolve())
        if resolved in seen_paths:
            print(f"generate-latest-manifest: same file mapped twice: {raw_path}", file=sys.stderr)
            return 1
        seen_paths.add(resolved)
        digest = sha256_of(path)
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            print(f"generate-latest-manifest: bad digest for {key}", file=sys.stderr)
            return 1
        assets[key] = {
            "name": path.name,
            "url": f"{release_base}/{path.name}",
            "sha256": digest,
            "size": path.stat().st_size,
        }

    required = tuple(args.require) if args.require else REQUIRED_DEFAULT
    missing = [key for key in required if key not in assets]
    if missing:
        print(f"generate-latest-manifest: missing required assets: {', '.join(missing)}", file=sys.stderr)
        return 1

    published_at = args.published_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    manifest = {
        "version": args.version,
        "channel": args.channel,
        "publishedAt": published_at,
        "releaseUrl": release_base,
        "releaseNotesUrl": f"{release_base}",
        "assets": assets,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    # Round-trip check: the file we publish must parse as valid JSON.
    json.loads(tmp.read_text(encoding="utf-8"))
    tmp.replace(output)
    print(f"generate-latest-manifest: wrote {output} ({len(assets)} assets)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

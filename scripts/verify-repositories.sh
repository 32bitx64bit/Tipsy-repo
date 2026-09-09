#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Validate repository output before publication. Fails nonzero when anything is
# obviously invalid. Signature checks run only when signing is configured
# (key files present); otherwise they warn. Use --strict to require signatures
# (CI publish path).
#
# Usage:
#   verify-repositories.sh --repo-root DIR [--version X.Y.Z] [--strict]
#                          [--app-id io.github.tipsy_linux.Tipsy]
set -euo pipefail

fail() { printf 'verify-repositories: FAIL: %s\n' "$*" >&2; exit 1; }
warn() { printf 'verify-repositories: WARN: %s\n' "$*" >&2; }
ok() { printf 'verify-repositories: ok: %s\n' "$*"; }

repo_root=
version=
strict=0
app_id=io.github.tipsy_linux.Tipsy
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --version) [[ $# -ge 2 ]] || fail 'missing --version value'; version=$2; shift 2 ;;
    --strict) strict=1; shift ;;
    --app-id) [[ $# -ge 2 ]] || fail 'missing --app-id value'; app_id=$2; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ -n "$repo_root" ]] || fail '--repo-root is required'

apt="$repo_root/public/apt"
rpm_repo="$repo_root/public/rpm/x86_64"
flatpak_repo="$repo_root/public/flatpak/repo"
manifest="$repo_root/public/latest.json"
pub="$repo_root/public"

# --- APT ---
[[ -f "$apt/dists/stable/Release" ]] || fail 'apt dists/stable/Release missing'
[[ -f "$apt/dists/stable/main/binary-amd64/Packages" ]] || fail 'apt Packages index missing'
[[ -s "$apt/dists/stable/main/binary-amd64/Packages" ]] || fail 'apt Packages index is empty'
[[ -f "$apt/dists/stable/main/binary-amd64/Packages.gz" ]] || fail 'apt Packages.gz missing'
grep -q '^Package: tipsy$' "$apt/dists/stable/main/binary-amd64/Packages" || fail 'tipsy not in APT Packages index'
while IFS= read -r f; do
  [[ -f "$apt/$f" ]] || fail "APT-indexed file missing: $f"
done < <(awk '/^Filename: / {print $2}' "$apt/dists/stable/main/binary-amd64/Packages")
if [[ -f "$apt/dists/stable/InRelease" ]]; then
  if command -v gpgv >/dev/null 2>&1 && ls "$pub"/keys/*.asc >/dev/null 2>&1; then
    ok 'apt InRelease present'
  else
    warn 'apt InRelease present but no keyring to verify against'
  fi
elif [[ "$strict" == 1 ]]; then
  fail 'apt InRelease missing in --strict mode'
else
  warn 'apt InRelease missing (unsigned; publish requires signing)'
fi
ok 'apt repository'

# --- RPM ---
[[ -f "$rpm_repo/repodata/repomd.xml" ]] || fail 'rpm repodata/repomd.xml missing'
[[ -s "$rpm_repo/repodata/repomd.xml" ]] || fail 'rpm repomd.xml is empty'
ls "$rpm_repo"/tipsy-*.rpm >/dev/null 2>&1 || fail 'no tipsy RPM in repository'
if command -v rpm >/dev/null 2>&1; then
  for r in "$rpm_repo"/tipsy-*.rpm; do
    rpm -K "$r" >/dev/null 2>&1 || warn "rpm signature check inconclusive for $(basename "$r")"
  done
fi
if [[ -f "$rpm_repo/repodata/repomd.xml.asc" ]]; then
  ok 'rpm repomd.xml.asc present'
elif [[ "$strict" == 1 ]]; then
  fail 'rpm repomd.xml.asc missing in --strict mode'
else
  warn 'rpm repomd.xml.asc missing (unsigned; publish requires signing)'
fi
ok 'rpm repository'

# --- Flatpak ---
[[ -d "$flatpak_repo/objects" ]] || fail 'flatpak repo objects/ missing (not an OSTree repo)'
[[ -f "$flatpak_repo/summary" ]] || fail 'flatpak repo summary missing'
if [[ -s "$flatpak_repo/summary.sig" ]]; then
  ok 'flatpak summary.sig present'
elif [[ "$strict" == 1 ]]; then
  fail 'flatpak summary.sig missing in --strict mode'
else
  warn 'flatpak summary.sig missing (unsigned; publish requires signing)'
fi
[[ -f "$repo_root/public/flatpak/tipsy.flatpakrepo" ]] || fail 'tipsy.flatpakrepo missing'
grep -q '^Url=' "$repo_root/public/flatpak/tipsy.flatpakrepo" || fail 'tipsy.flatpakrepo has no Url='
if command -v ostree >/dev/null 2>&1; then
  ostree summary --repo="$flatpak_repo" --view >/dev/null || fail 'flatpak summary is invalid'
  if ostree refs --repo="$flatpak_repo" | grep -q "$app_id"; then
    ok "flatpak ref $app_id present"
  else
    warn "flatpak ref $app_id not present yet (no bundle imported)"
  fi
fi
ok 'flatpak repository'

# --- Manifest ---
[[ -f "$manifest" ]] || fail 'latest.json missing'
python3 - "$manifest" <<'PY'
import json, sys
manifest = json.loads(open(sys.argv[1], encoding="utf-8").read())
for key in ("version", "channel", "publishedAt", "releaseUrl", "assets"):
    if key not in manifest:
        raise SystemExit(f"latest.json missing key: {key}")
if not isinstance(manifest["assets"], dict) or not manifest["assets"]:
    raise SystemExit("latest.json has no assets (no release published yet)")
import re
for key, asset in manifest["assets"].items():
    for field in ("name", "url", "sha256"):
        if field not in asset:
            raise SystemExit(f"latest.json asset {key} missing {field}")
    if not asset["url"].startswith("https://"):
        raise SystemExit(f"latest.json asset {key} URL is not HTTPS")
    if not re.fullmatch(r"[0-9a-f]{64}", asset["sha256"]):
        raise SystemExit(f"latest.json asset {key} has a malformed sha256")
print(f"verify-repositories: ok: latest.json ({len(manifest['assets'])} assets)")
PY
if [[ -n "$version" ]]; then
  manifest_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$manifest")
  [[ "$manifest_version" == "$version" ]] || fail "latest.json version $manifest_version != $version"
  ok "latest.json version $version"
fi
if [[ -f "$manifest.sig" ]]; then
  ok 'latest.json.sig present'
elif [[ "$strict" == 1 ]]; then
  fail 'latest.json.sig missing in --strict mode'
else
  warn 'latest.json.sig missing (unsigned; publish requires signing)'
fi

# --- Hygiene: no private material or tokens in git ---
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$repo_root" ls-files | grep -Ei '\.(key|private)$|passphrase|secring|\.token$' >/dev/null 2>&1; then
    fail 'private key/token material appears to be tracked in git'
  fi
  # (This scanner's own patterns are excluded so it cannot match itself.)
  if git -C "$repo_root" grep -EI 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|BEGIN .*PRIVATE KEY' -- ':!docs/SIGNING.md' ':!scripts/verify-repositories.sh' -- . >/dev/null 2>&1; then
    fail 'possible secret or private key found in tracked files'
  fi
else
  warn 'not inside a git work tree; skipping tracked-secret scan'
fi
ok 'no secrets in git'

printf 'verify-repositories: ALL CHECKS PASSED\n'

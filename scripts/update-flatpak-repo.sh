#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Maintain the self-hosted Flatpak/OSTree repository under
# <repo-root>/public/flatpak/repo.
#
# Usage:
#   update-flatpak-repo.sh --repo-root DIR [--bundle FILE]
#                          [--app-id io.github.tipsy_linux.Tipsy]
#                          [--gpg-key KEYID] [--allow-unsigned]
#
# A genuine OSTree repository is maintained (never just a directory of
# .flatpak files). --bundle imports a single-file bundle when one is supplied;
# without it the existing repo is only re-indexed (static deltas regenerated).
# An empty repo is initialized on first run so Pages has a valid structure.
# Idempotent: re-imports the same bundle ref safely; build-update-repo rewrites
# summary metadata deterministically.
set -euo pipefail

fail() { printf 'update-flatpak-repo: %s\n' "$*" >&2; exit 1; }

repo_root=
bundle=
app_id=io.github.tipsy_linux.Tipsy
gpg_key=
allow_unsigned=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --bundle) [[ $# -ge 2 ]] || fail 'missing --bundle value'; bundle=$2; shift 2 ;;
    --app-id) [[ $# -ge 2 ]] || fail 'missing --app-id value'; app_id=$2; shift 2 ;;
    --gpg-key) [[ $# -ge 2 ]] || fail 'missing --gpg-key value'; gpg_key=$2; shift 2 ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repo_root" ]] || fail '--repo-root is required'
command -v flatpak >/dev/null 2>&1 || fail 'flatpak is missing (install flatpak)'
command -v ostree >/dev/null 2>&1 || fail 'ostree is missing (install ostree)'

flatpak_dir="$repo_root/public/flatpak"
repodir="$flatpak_dir/repo"
mkdir -p "$flatpak_dir"

if [[ ! -d "$repodir/objects" ]]; then
  printf 'update-flatpak-repo: initializing empty OSTree repo\n'
  ostree init --repo="$repodir" --mode=archive
fi

sign_args=()
if [[ -n "$gpg_key" ]]; then
  sign_args+=(--gpg-sign="$gpg_key")
elif [[ "$allow_unsigned" != 1 ]]; then
  fail 'no --gpg-key given; refusing to publish an unsigned Flatpak repo (use --allow-unsigned for local tests)'
else
  printf 'update-flatpak-repo: WARNING: unsigned repository (local testing only)\n' >&2
fi

if [[ -n "$bundle" ]]; then
  [[ -f "$bundle" ]] || fail "bundle not found: $bundle"
  printf 'update-flatpak-repo: importing %s\n' "$(basename "$bundle")"
  flatpak build-import-bundle "${sign_args[@]}" "$repodir" "$bundle"
fi

# Regenerate summary + static deltas (needed after every import).
flatpak build-update-repo --generate-static-deltas "${sign_args[@]}" "$repodir"

# The repo must advertise the application ref once a bundle was imported.
if [[ -n "$bundle" ]]; then
  flatpak build-update-repo --title="Tipsy" "$repodir" >/dev/null 2>&1 || true
  if ! ostree refs --repo="$repodir" | grep -q "$app_id"; then
    ostree refs --repo="$repodir" >&2 || true
    fail "expected ref for $app_id is missing after bundle import"
  fi
fi

[[ -f "$repodir/summary" ]] || fail 'repo summary was not generated'
ostree summary --repo="$repodir" --view >/dev/null || fail 'repo summary is invalid'

printf 'update-flatpak-repo: done (%s)\n' "$repodir"

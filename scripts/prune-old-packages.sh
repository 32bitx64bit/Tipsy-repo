#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prune old installable files from public/ (Pages stays small).
# GitHub Release assets are NEVER touched: history lives there permanently.
#
# Usage: prune-old-packages.sh --repo-root DIR [--keep 3]
set -euo pipefail

fail() { printf 'prune-old-packages: %s\n' "$*" >&2; exit 1; }

repo_root=
keep=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --keep) [[ $# -ge 2 ]] || fail 'missing --keep value'; keep=$2; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ -n "$repo_root" ]] || fail '--repo-root is required'
[[ "$keep" =~ ^[0-9]+$ && "$keep" -ge 1 ]] || fail '--keep must be a positive integer'

prune_by_version() {
  local dir=$1 pattern=$2
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  # Group by everything up to the version separator, keep newest --keep.
  declare -A groups=()
  local f base key
  for f in "$dir"/$pattern; do
    base=$(basename "$f")
    key=$(printf '%s' "$base" | sed -E 's/_[0-9][0-9A-Za-z._+~-]*_.*//; s/-[0-9][0-9A-Za-z._+~-]*\..*//')
    groups[$key]+="$f"$'\n'
  done
  for key in "${!groups[@]}"; do
    mapfile -t files < <(printf '%s' "${groups[$key]}" | sort -V)
    local drop=$(( ${#files[@]} - keep ))
    local i
    for (( i = 0; i < drop; i++ )); do
      printf 'prune-old-packages: pruning %s\n' "${files[$i]}"
      rm -f "${files[$i]}"
    done
  done
  shopt -u nullglob
}

# Pacman package names are tipsy-<ver>-<rel>-<arch>.pkg.tar.zst (pkgver never
# contains a hyphen), so group explicitly and take the detached signature with
# each removed package.
prune_pacman() {
  local dir="$repo_root/public/pacman/x86_64"
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  declare -A groups=()
  local f base key
  for f in "$dir"/*.pkg.tar.zst; do
    base=$(basename "$f")
    key=$(sed -E 's/-[0-9][^-]*-[0-9]+-.*\.pkg\.tar\.zst$//' <<<"$base")
    groups[$key]+="$f"$'\n'
  done
  for key in "${!groups[@]}"; do
    mapfile -t files < <(printf '%s' "${groups[$key]}" | sort -V)
    local drop=$(( ${#files[@]} - keep ))
    local i
    for (( i = 0; i < drop; i++ )); do
      printf 'prune-old-packages: pruning %s\n' "${files[$i]}"
      rm -f "${files[$i]}" "${files[$i]}.sig"
    done
  done
  shopt -u nullglob
}

prune_by_version "$repo_root/public/apt/pool" '*.deb'
prune_by_version "$repo_root/public/rpm/x86_64" '*.rpm'
prune_pacman
# The Flatpak/OSTree repo is pruned by update-flatpak-repo.sh (--keep): every
# summary rewrite must be signed, and an unsigned `build-update-repo --prune`
# here would delete summary.sig.

printf 'prune-old-packages: done (keep=%s)\n' "$keep"

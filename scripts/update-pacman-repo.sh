#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerate the pacman repository under <repo-root>/public/pacman/<arch>.
#
# Usage:
#   update-pacman-repo.sh --repo-root DIR --pkg FILE [--pkg FILE ...]
#                         [--arch x86_64] [--keep 3]
#                         [--key-id KEYID] [--allow-unsigned]
#
# Idempotent: new packages are copied in (identical name+hash = skip), the
# directory is pruned to --keep newest per package name, packages are
# detached-signed, then the database is rebuilt from scratch with repo-add.
#
# GitHub Pages does not follow symlinks, so the repo-add symlinks
# (tipsy.db -> tipsy.db.tar.gz, tipsy.files -> tipsy.files.tar.gz) are
# materialized as regular files and both signature names are written.
#
# Signing: --key-id signs every package (<name>.pkg.tar.zst.sig) and the
# database (tipsy.db.sig + tipsy.db.tar.gz.sig). Without it the script fails
# unless --allow-unsigned is given (local testing only; CI must always sign).
set -euo pipefail

fail() { printf 'update-pacman-repo: %s\n' "$*" >&2; exit 1; }

repo_root=
pkg_files=()
arch=x86_64
keep=3
key_id=
allow_unsigned=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --pkg) [[ $# -ge 2 ]] || fail 'missing --pkg value'; pkg_files+=("$2"); shift 2 ;;
    --arch) [[ $# -ge 2 ]] || fail 'missing --arch value'; arch=$2; shift 2 ;;
    --keep) [[ $# -ge 2 ]] || fail 'missing --keep value'; keep=$2; shift 2 ;;
    --key-id) [[ $# -ge 2 ]] || fail 'missing --key-id value'; key_id=$2; shift 2 ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repo_root" ]] || fail '--repo-root is required'
[[ -d "$repo_root" ]] || fail "repo root not found: $repo_root"
repo_root=$(CDPATH= cd -- "$repo_root" && pwd)
[[ "$keep" =~ ^[0-9]+$ && "$keep" -ge 1 ]] || fail '--keep must be a positive integer'
command -v repo-add >/dev/null 2>&1 || fail 'repo-add is missing (pacman-package-manager on Debian/Ubuntu)'
command -v bsdtar >/dev/null 2>&1 || fail 'bsdtar is missing (libarchive-tools)'
if [[ -z "$key_id" && "$allow_unsigned" != 1 ]]; then
  fail 'no --key-id given; refusing to publish an unsigned pacman repo (use --allow-unsigned for local tests)'
fi
if [[ -n "$key_id" ]]; then
  command -v gpg >/dev/null 2>&1 || fail 'gpg is missing but --key-id was given'
fi

repodir="$repo_root/public/pacman/$arch"
mkdir -p "$repodir"

# 1. Ingest new packages (same name + same hash = skip, same name + new hash =
# replace and drop the now-stale signature).
for pkg in "${pkg_files[@]}"; do
  [[ -f "$pkg" ]] || fail "package not found: $pkg"
  base=$(basename "$pkg")
  [[ "$base" == *.pkg.tar.zst ]] || fail "not a pacman package: $base"
  if [[ -f "$repodir/$base" ]]; then
    old=$(sha256sum "$repodir/$base"); old=${old%% *}
    new=$(sha256sum "$pkg"); new=${new%% *}
    if [[ "$old" == "$new" ]]; then
      printf 'update-pacman-repo: keeping identical %s\n' "$base"
      continue
    fi
    printf 'update-pacman-repo: replacing %s (hash changed)\n' "$base"
    rm -f "$repodir/$base.sig"
  fi
  install -m 0644 "$pkg" "$repodir/$base"
done

# 2. Prune to the newest --keep per package name
# (tipsy-1.2.3-1-x86_64.pkg.tar.zst; versions never contain a hyphen).
shopt -s nullglob
declare -A seen=()
mapfile -t all_pkgs < <(ls -1 "$repodir"/*.pkg.tar.zst 2>/dev/null | sort -Vr)
kept=()
for f in "${all_pkgs[@]}"; do
  base=$(basename "$f")
  key=$(sed -E 's/-[^-]*-[^-]*-'"$arch"'\.pkg\.tar\.[a-z]+$//' <<<"$base")
  [[ "$key" != "$base" && -n "$key" ]] || fail "cannot parse package name: $base"
  count=${seen[$key]:-0}
  if (( count < keep )); then
    kept+=("$f"); seen[$key]=$((count + 1))
  else
    printf 'update-pacman-repo: pruning %s\n' "$base"
    rm -f "$f" "$f.sig"
  fi
done
shopt -u nullglob
[[ ${#kept[@]} -ge 1 ]] || fail 'no packages to index'

# Sign packages before building the database so the index covers final files.
sign_detached() {
  local file=$1 out=$2
  if [[ -n "${TIPSY_GPG_PASSPHRASE:-}" ]]; then
    gpg --batch --yes --pinentry-mode loopback --local-user "$key_id" --passphrase-fd 3 \
      --detach-sign -o "$out" "$file" 3<<<"$TIPSY_GPG_PASSPHRASE"
  else
    # No passphrase supplied: gpg signs an unprotected key without prompting.
    # (--pinentry-mode loopback without --passphrase would abort in batch mode.)
    gpg --batch --yes --local-user "$key_id" --detach-sign -o "$out" "$file"
  fi
  gpg --batch --verify "$out" "$file" >/dev/null 2>&1 || fail "signature verification failed for $out"
}

if [[ -n "$key_id" ]]; then
  for pkg in "${kept[@]}"; do
    if [[ -s "$pkg.sig" ]] && gpg --batch --verify "$pkg.sig" "$pkg" >/dev/null 2>&1; then
      printf 'update-pacman-repo: already signed %s\n' "$(basename "$pkg")"
      continue
    fi
    printf 'update-pacman-repo: signing %s\n' "$(basename "$pkg")"
    sign_detached "$pkg" "$pkg.sig"
  done
else
  printf 'update-pacman-repo: WARNING: unsigned repository (local testing only)\n' >&2
fi

# 3. Rebuild the database from scratch. Repository metadata is small, so a
# fresh rebuild is the only way to guarantee pruned versions leave no stale
# entries. Ubuntu noble's repo-add 6.0.2 keeps one entry per pkgname and
# the LAST added package wins (the "newer version already present" line is
# only a warning). kept[] is newest-first for --keep; pass oldest-first
# here so 1.3.0 is not replaced by 1.2.3.
rm -f "$repodir/tipsy.db" "$repodir/tipsy.db.tar.gz" \
      "$repodir/tipsy.db.sig" "$repodir/tipsy.db.tar.gz.sig" \
      "$repodir/tipsy.files" "$repodir/tipsy.files.tar.gz" \
      "$repodir/tipsy.files.sig" "$repodir/tipsy.files.tar.gz.sig" \
      "$repodir/tipsy.db.tar.gz.old" "$repodir/tipsy.files.tar.gz.old"
mapfile -t index_pkgs < <(printf '%s\n' "${kept[@]}" | sort -V)
repo-add "$repodir/tipsy.db.tar.gz" "${index_pkgs[@]}"
[[ -f "$repodir/tipsy.db.tar.gz" ]] || fail 'repo-add did not produce tipsy.db.tar.gz'
newest_pkg=$(printf '%s\n' "${kept[@]}" | sort -Vr | head -n 1)
newest_entry=$(basename "$newest_pkg" | sed -E "s/-${arch}\\.pkg\\.tar\\.[a-z0-9]+$//")
[[ -n "$newest_entry" && "$newest_entry" != "$(basename "$newest_pkg")" ]] \
  || fail "cannot parse repo-add entry from $(basename "$newest_pkg")"
bsdtar -tf "$repodir/tipsy.db.tar.gz" | grep -qx "${newest_entry}/desc" \
  || fail "repo-add left ${newest_entry} out of tipsy.db (last-add-wins on 6.0.2; pass oldest-first)"

# 4. Materialize repo-add's symlinks as regular files. GitHub Pages serves
# plain files; a symlink would either 404 or break the database signature.
for name in tipsy.db tipsy.files; do
  if [[ -L "$repodir/$name" ]]; then
    target=$(readlink -f -- "$repodir/$name")
    rm -f "$repodir/$name"
    cp --preserve=mode,timestamps -- "$target" "$repodir/$name"
  fi
done
[[ -f "$repodir/tipsy.db" && ! -L "$repodir/tipsy.db" ]] || fail 'tipsy.db is missing or still a symlink'

# 5. Sign the database under both names pacman may fetch.
if [[ -n "$key_id" ]]; then
  sign_detached "$repodir/tipsy.db" "$repodir/tipsy.db.sig"
  cp -f -- "$repodir/tipsy.db.sig" "$repodir/tipsy.db.tar.gz.sig"
  if [[ -f "$repodir/tipsy.files" ]]; then
    sign_detached "$repodir/tipsy.files" "$repodir/tipsy.files.sig"
    cp -f -- "$repodir/tipsy.files.sig" "$repodir/tipsy.files.tar.gz.sig"
  fi
  printf 'update-pacman-repo: signed database with %s\n' "$key_id"
fi

printf 'update-pacman-repo: done (%s, %s packages)\n' "$arch" "${#kept[@]}"

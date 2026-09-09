#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerate the self-hosted APT repository under <repo-root>/public/apt.
#
# Usage:
#   update-apt-repo.sh --repo-root DIR --deb FILE [--deb FILE ...]
#                      [--origin Tipsy] [--codename stable]
#                      [--arch amd64] [--keep 3]
#                      [--key-id KEYID] [--allow-unsigned]
#
# Deterministic and idempotent: metadata is rebuilt from scratch on every run
# from exactly the .deb files retained in pool/. New --deb files are copied in
# first; then pool/ is pruned to the newest --keep versions per package.
#
# Signing: --key-id signs Release (-> InRelease + Release.gpg). Without it the
# script fails unless --allow-unsigned is given (local testing only; CI must
# always sign).
set -euo pipefail

fail() { printf 'update-apt-repo: %s\n' "$*" >&2; exit 1; }

repo_root=
deb_files=()
origin=Tipsy
codename=stable
arch=amd64
keep=3
key_id=
allow_unsigned=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --deb) [[ $# -ge 2 ]] || fail 'missing --deb value'; deb_files+=("$2"); shift 2 ;;
    --origin) [[ $# -ge 2 ]] || fail 'missing --origin value'; origin=$2; shift 2 ;;
    --codename) [[ $# -ge 2 ]] || fail 'missing --codename value'; codename=$2; shift 2 ;;
    --arch) [[ $# -ge 2 ]] || fail 'missing --arch value'; arch=$2; shift 2 ;;
    --keep) [[ $# -ge 2 ]] || fail 'missing --keep value'; keep=$2; shift 2 ;;
    --key-id) [[ $# -ge 2 ]] || fail 'missing --key-id value'; key_id=$2; shift 2 ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repo_root" ]] || fail '--repo-root is required'
[[ "$keep" =~ ^[0-9]+$ && "$keep" -ge 1 ]] || fail '--keep must be a positive integer'
command -v dpkg-scanpackages >/dev/null 2>&1 || fail 'dpkg-scanpackages is missing (install dpkg-dev)'
command -v apt-ftparchive >/dev/null 2>&1 || fail 'apt-ftparchive is missing (install apt)'

apt_root="$repo_root/public/apt"
pool="$apt_root/pool"
dists="$apt_root/dists/$codename"
bindir="$dists/main/binary-$arch"
mkdir -p "$pool" "$bindir"

# 1. Ingest new .debs (same name + same hash = skip, same name + new hash = replace).
for deb in "${deb_files[@]}"; do
  [[ -f "$deb" ]] || fail "deb not found: $deb"
  base=$(basename "$deb")
  if [[ -f "$pool/$base" ]]; then
    old=$(sha256sum "$pool/$base"); old=${old%% *}
    new=$(sha256sum "$deb"); new=${new%% *}
    if [[ "$old" == "$new" ]]; then
      printf 'update-apt-repo: keeping identical %s\n' "$base"
      continue
    fi
    printf 'update-apt-repo: replacing %s (hash changed)\n' "$base"
  fi
  install -m 0644 "$deb" "$pool/$base"
done

# 2. Prune pool/ to the newest --keep files per package name.
# Names look like tipsy_1.2.3_amd64.deb; sort -V on the version field.
if [[ "$(ls "$pool" 2>/dev/null | wc -l)" -gt 0 ]]; then
  while IFS= read -r pkg; do
    mapfile -t files < <(ls "$pool/${pkg}_"* 2>/dev/null | sort -V)
    drop=$(( ${#files[@]} - keep ))
    for (( i = 0; i < drop; i++ )); do
      printf 'update-apt-repo: pruning %s\n' "$(basename "${files[$i]}")"
      rm -f "${files[$i]}"
    done
  done < <(ls "$pool" | sed 's/_.*//' | sort -u)
fi

# 3. Rebuild the package index deterministically from pool/.
(
  cd "$apt_root"
  dpkg-scanpackages --arch "$arch" pool /dev/null > "$bindir/Packages"
)
gzip -9n -c "$bindir/Packages" > "$bindir/Packages.gz"

# Every indexed file must exist (catches stale entries).
while IFS= read -r filename; do
  [[ -f "$apt_root/$filename" ]] || fail "indexed file missing: $filename"
done < <(awk '/^Filename: / {print $2}' "$bindir/Packages")

# 4. Build Release with apt-ftparchive (deterministic field order).
cat > "$dists/.apt-release.conf" <<EOF
APT::FTPArchive::Release::Origin "$origin";
APT::FTPArchive::Release::Label "$origin";
APT::FTPArchive::Release::Suite "$codename";
APT::FTPArchive::Release::Codename "$codename";
APT::FTPArchive::Release::Architectures "$arch";
APT::FTPArchive::Release::Components "main";
APT::FTPArchive::Release::Description "Official $origin Linux packages";
EOF
(
  cd "$apt_root"
  apt-ftparchive -c "dists/$codename/.apt-release.conf" release "dists/$codename" > "dists/$codename/Release"
)
rm -f "$dists/.apt-release.conf"

# 5. Sign (InRelease = clearsigned, Release.gpg = detached).
# Passphrase comes from TIPSY_GPG_PASSPHRASE via fd 3 when set: never argv.
if [[ -n "$key_id" ]]; then
  command -v gpg >/dev/null 2>&1 || fail 'gpg is missing but --key-id was given'
  gpg_sign=(gpg --batch --yes --pinentry-mode loopback --local-user "$key_id")
  if [[ -n "${TIPSY_GPG_PASSPHRASE:-}" ]]; then
    gpg_sign+=(--passphrase-fd 3)
    "${gpg_sign[@]}" --clearsign -o "$dists/InRelease" "$dists/Release" 3<<<"$TIPSY_GPG_PASSPHRASE"
    "${gpg_sign[@]}" --armor --detach-sign -o "$dists/Release.gpg" "$dists/Release" 3<<<"$TIPSY_GPG_PASSPHRASE"
  else
    "${gpg_sign[@]}" --clearsign -o "$dists/InRelease" "$dists/Release"
    "${gpg_sign[@]}" --armor --detach-sign -o "$dists/Release.gpg" "$dists/Release"
  fi
  gpg --verify "$dists/InRelease" >/dev/null 2>&1 || fail 'InRelease verification failed'
  printf 'update-apt-repo: signed with %s\n' "$key_id"
elif [[ "$allow_unsigned" == 1 ]]; then
  printf 'update-apt-repo: WARNING: unsigned repository (local testing only)\n' >&2
else
  fail 'no --key-id given; refusing to publish an unsigned APT repo (use --allow-unsigned for local tests)'
fi

printf 'update-apt-repo: done (%s, %s)\n' "$codename" "$arch"

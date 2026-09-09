#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerate the RPM/DNF repository under <repo-root>/public/rpm/<arch>.
#
# Usage:
#   update-rpm-repo.sh --repo-root DIR --rpm FILE [--rpm FILE ...]
#                      [--arch x86_64] [--keep 3]
#                      [--key-id KEYID] [--allow-unsigned]
#
# Idempotent: new RPMs are copied in (identical name+hash = skip), the
# directory is pruned to --keep newest per package name, then createrepo_c
# --update refreshes repodata. Packages and repomd.xml are signed when
# --key-id is given; otherwise --allow-unsigned is required (local tests).
set -euo pipefail

fail() { printf 'update-rpm-repo: %s\n' "$*" >&2; exit 1; }

repo_root=
rpm_files=()
arch=x86_64
keep=3
key_id=
allow_unsigned=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --rpm) [[ $# -ge 2 ]] || fail 'missing --rpm value'; rpm_files+=("$2"); shift 2 ;;
    --arch) [[ $# -ge 2 ]] || fail 'missing --arch value'; arch=$2; shift 2 ;;
    --keep) [[ $# -ge 2 ]] || fail 'missing --keep value'; keep=$2; shift 2 ;;
    --key-id) [[ $# -ge 2 ]] || fail 'missing --key-id value'; key_id=$2; shift 2 ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repo_root" ]] || fail '--repo-root is required'
[[ "$keep" =~ ^[0-9]+$ && "$keep" -ge 1 ]] || fail '--keep must be a positive integer'
command -v createrepo_c >/dev/null 2>&1 || fail 'createrepo_c is missing (install createrepo_c)'
command -v rpm >/dev/null 2>&1 || fail 'rpm is missing'

repodir="$repo_root/public/rpm/$arch"
mkdir -p "$repodir"

for rpm_file in "${rpm_files[@]}"; do
  [[ -f "$rpm_file" ]] || fail "rpm not found: $rpm_file"
  base=$(basename "$rpm_file")
  if [[ -f "$repodir/$base" ]]; then
    old=$(sha256sum "$repodir/$base"); old=${old%% *}
    new=$(sha256sum "$rpm_file"); new=${new%% *}
    if [[ "$old" == "$new" ]]; then
      printf 'update-rpm-repo: keeping identical %s\n' "$base"
      continue
    fi
    printf 'update-rpm-repo: replacing %s (hash changed)\n' "$base"
  fi
  install -m 0644 "$rpm_file" "$repodir/$base"
done

# Sign packages before (re)generating metadata so repodata hashes cover them.
# Passphrase comes from TIPSY_GPG_PASSPHRASE via fd 3 when set: never argv.
if [[ -n "$key_id" ]]; then
  command -v gpg >/dev/null 2>&1 || fail 'gpg is missing but --key-id was given'
  command -v rpmsign >/dev/null 2>&1 || fail 'rpmsign is missing but --key-id was given'
  rpm_macros=()
  if [[ -n "${TIPSY_GPG_PASSPHRASE:-}" ]]; then
    sign_macros=$(mktemp "${TMPDIR:-/tmp}/tipsy-rpmsign.XXXXXXXX")
    cat > "$sign_macros" <<'EOF'
%__gpg_sign_cmd %{__gpg} gpg --force-v3-sigs --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase-fd 3 --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} %{__plaintext_filename}
EOF
    rpm_macros=(--define "_topdir $HOME/rpmbuild" --macros "$sign_macros")
  fi
  for rpm_file in "$repodir"/*.rpm; do
    [[ -e "$rpm_file" ]] || break
    if rpm -K "$rpm_file" 2>/dev/null | grep -q 'digests signatures OK'; then
      printf 'update-rpm-repo: already signed %s\n' "$(basename "$rpm_file")"
    else
      printf 'update-rpm-repo: signing %s\n' "$(basename "$rpm_file")"
      if [[ -n "${TIPSY_GPG_PASSPHRASE:-}" ]]; then
        rpmsign "${rpm_macros[@]}" --addsign --define "_gpg_name $key_id" "$rpm_file" 3<<<"$TIPSY_GPG_PASSPHRASE"
      else
        rpmsign --addsign --define "_gpg_name $key_id" "$rpm_file"
      fi
    fi
  done
  [[ -z "${sign_macros:-}" ]] || rm -f "$sign_macros"
elif [[ "$allow_unsigned" != 1 ]]; then
  fail 'no --key-id given; refusing to publish an unsigned RPM repo (use --allow-unsigned for local tests)'
else
  printf 'update-rpm-repo: WARNING: unsigned repository (local testing only)\n' >&2
fi

# Prune to newest --keep per name (tipsy-1.2.3-1.x86_64.rpm).
shopt -s nullglob
declare -A seen=()
mapfile -t all_rpms < <(ls -1 "$repodir"/*.rpm 2>/dev/null | sort -Vr)
kept=()
for f in "${all_rpms[@]}"; do
  name=$(basename "$f"); name=${name%-*-*}; name=${name%.rpm}
  count=${seen[$name]:-0}
  if (( count < keep )); then
    kept+=("$f"); seen[$name]=$((count + 1))
  else
    printf 'update-rpm-repo: pruning %s\n' "$(basename "$f")"
    rm -f "$f"
  fi
done
shopt -u nullglob

createrepo_c --update --keep-all-metadata --database --pretty "$repodir"
[[ -f "$repodir/repodata/repomd.xml" ]] || fail 'repomd.xml was not generated'

# Detached-sign repository metadata when a key is configured.
if [[ -n "$key_id" ]]; then
  if [[ -n "${TIPSY_GPG_PASSPHRASE:-}" ]]; then
    gpg --batch --yes --pinentry-mode loopback --local-user "$key_id" --passphrase-fd 3 \
      --armor --detach-sign -o "$repodir/repodata/repomd.xml.asc" "$repodir/repodata/repomd.xml" 3<<<"$TIPSY_GPG_PASSPHRASE"
  else
    gpg --batch --yes --pinentry-mode loopback --local-user "$key_id" \
      --armor --detach-sign -o "$repodir/repodata/repomd.xml.asc" "$repodir/repodata/repomd.xml"
  fi
  gpg --verify "$repodir/repomd.xml.asc" "$repodir/repomd.xml" || fail 'repomd.xml.asc verification failed'
  printf 'update-rpm-repo: signed repodata with %s\n' "$key_id"
fi

printf 'update-rpm-repo: done (%s)\n' "$arch"

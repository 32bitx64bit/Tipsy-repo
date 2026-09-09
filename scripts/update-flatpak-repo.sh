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
#                          [--gpg-key KEYID] [--allow-unsigned] [--keep 3]
#
# A genuine OSTree repository is maintained (never just a directory of
# .flatpak files). --bundle imports a single-file bundle when one is supplied;
# without it the existing repo is only re-indexed (static deltas regenerated).
# An empty repo is initialized on first run so Pages has a valid structure.
# Pruning happens here too (--keep newest commits per ref) because every
# summary rewrite must carry the signature; an unsigned prune elsewhere would
# silently drop summary.sig.
# Idempotent: re-imports the same bundle ref safely; build-update-repo rewrites
# summary metadata deterministically.
set -euo pipefail

fail() { printf 'update-flatpak-repo: %s\n' "$*" >&2; exit 1; }

repo_root=
bundle=
app_id=io.github.tipsy_linux.Tipsy
gpg_key=
allow_unsigned=0
keep=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) [[ $# -ge 2 ]] || fail 'missing --repo-root value'; repo_root=$2; shift 2 ;;
    --bundle) [[ $# -ge 2 ]] || fail 'missing --bundle value'; bundle=$2; shift 2 ;;
    --app-id) [[ $# -ge 2 ]] || fail 'missing --app-id value'; app_id=$2; shift 2 ;;
    --gpg-key) [[ $# -ge 2 ]] || fail 'missing --gpg-key value'; gpg_key=$2; shift 2 ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    --keep) [[ $# -ge 2 ]] || fail 'missing --keep value'; keep=$2; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$repo_root" ]] || fail '--repo-root is required'
[[ -d "$repo_root" ]] || fail "repo root not found: $repo_root"
repo_root=$(CDPATH= cd -- "$repo_root" && pwd)
[[ "$keep" =~ ^[0-9]+$ && "$keep" -ge 1 ]] || fail '--keep must be a positive integer'
command -v flatpak >/dev/null 2>&1 || fail 'flatpak is missing (install flatpak)'
command -v ostree >/dev/null 2>&1 || fail 'ostree is missing (install ostree)'

flatpak_dir="$repo_root/public/flatpak"
repodir="$flatpak_dir/repo"
mkdir -p "$flatpak_dir"

if [[ ! -d "$repodir/objects" ]]; then
  printf 'update-flatpak-repo: initializing empty OSTree repo\n'
  ostree init --repo="$repodir" --mode=archive
fi

# ostree signs through gpg-agent (gpgme); unlike gpg itself it has no
# --passphrase-fd path. When a passphrase is configured, seed the agent's
# cache for this session so signing works without a pinentry (CI has none).
preset_agent_passphrase() {
  local preset conf grip grips
  preset=/usr/lib/gnupg/gpg-preset-passphrase
  [[ -x "$preset" ]] || preset=$(command -v gpg-preset-passphrase 2>/dev/null || true)
  [[ -n "$preset" && -x "$preset" ]] || fail 'gpg-preset-passphrase is missing (install gpg-agent)'
  conf="${GNUPGHOME:-$HOME/.gnupg}/gpg-agent.conf"
  mkdir -p "$(dirname "$conf")"
  chmod 700 "$(dirname "$conf")"
  grep -qs '^allow-preset-passphrase' "$conf" || printf 'allow-preset-passphrase\n' >> "$conf"
  gpg-connect-agent reloadagent /bye >/dev/null
  mapfile -t grips < <(gpg --batch --with-colons --with-keygrip --list-secret-keys "$gpg_key" \
    | awk -F: '$1 == "grp" {print $10}')
  [[ ${#grips[@]} -gt 0 ]] || fail "no secret key material for $gpg_key"
  for grip in "${grips[@]}"; do
    printf '%s' "$TIPSY_GPG_PASSPHRASE" | "$preset" --preset "$grip"
  done
}

sign_args=()
if [[ -n "$gpg_key" ]]; then
  sign_args+=(--gpg-sign="$gpg_key")
  [[ -z "${TIPSY_GPG_PASSPHRASE:-}" ]] || preset_agent_passphrase
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

# Regenerate summary + static deltas (needed after every import) and prune
# commits older than the newest --keep per ref, all in one signed rewrite.
# (Objects are content-addressed and shared between versions; only ostree
# knows which are still referenced.)
flatpak build-update-repo --title="Tipsy" --generate-static-deltas \
  --prune --prune-depth="$((keep - 1))" "${sign_args[@]}" "$repodir"

# The repo must advertise the application ref once a bundle was imported.
if [[ -n "$bundle" ]]; then
  if ! ostree refs --repo="$repodir" | grep -q "$app_id"; then
    ostree refs --repo="$repodir" >&2 || true
    fail "expected ref for $app_id is missing after bundle import"
  fi
fi

[[ -f "$repodir/summary" ]] || fail 'repo summary was not generated'
ostree summary --repo="$repodir" --view >/dev/null || fail 'repo summary is invalid'
if [[ -n "$gpg_key" ]]; then
  [[ -s "$repodir/summary.sig" ]] || fail 'repo summary.sig was not generated'
fi

printf 'update-flatpak-repo: done (%s)\n' "$repodir"

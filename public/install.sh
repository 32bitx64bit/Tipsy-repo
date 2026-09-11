#!/usr/bin/env bash
# Copyright 2026 The Tipsy Authors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Tipsy installer: detect the distribution, add the official signed package
# repository, and install Tipsy.
#
# One-liner:
#   curl -fsSL https://32bitx64bit.github.io/Tipsy-repo/install.sh | sudo bash
#
# Options (piped form: curl -fsSL ... | sudo bash -s -- --dry-run):
#   --method apt|dnf|pacman|flatpak   skip detection and force a package manager
#   --dry-run                         print every command, change nothing
#   --no-install                      add the repository but do not install tipsy
#   -h, --help                        this text
#
# Environment overrides (mainly for tests):
#   TIPSY_REPO_BASE   Pages base URL (default https://32bitx64bit.github.io/Tipsy-repo)
#   TIPSY_OS_RELEASE  path to an os-release file (default /etc/os-release)
#
# Tipsy does not include Roblox and this script never downloads it. After the
# install, open "Tipsy - Settings" and run the setup assistant: it downloads
# and cryptographically verifies an official Android x86-64 client before
# extracting anything.
set -euo pipefail

repo_base=${TIPSY_REPO_BASE:-https://32bitx64bit.github.io/Tipsy-repo}
os_release=${TIPSY_OS_RELEASE:-/etc/os-release}
dry_run=0
do_install=1
method_override=

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Tipsy installer: detect the distribution, add the official signed package
repository, and install Tipsy.

Usage (piped form: curl -fsSL ... | sudo bash -s -- [options]):
  curl -fsSL https://32bitx64bit.github.io/Tipsy-repo/install.sh | sudo bash

Options:
  --method apt|dnf|pacman|flatpak   skip detection and force a package manager
  --dry-run                         print every command, change nothing
  --no-install                      add the repository but do not install tipsy
  -h, --help                        this text

Environment overrides (mainly for tests):
  TIPSY_REPO_BASE   Pages base URL
                    (default https://32bitx64bit.github.io/Tipsy-repo)
  TIPSY_OS_RELEASE  path to an os-release file (default /etc/os-release)

Tipsy does not include Roblox and this script never downloads it. After the
install, open "Tipsy - Settings" and run the setup assistant: it downloads
and cryptographically verifies an official Android x86-64 client before
extracting anything.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) [[ $# -ge 2 ]] || die 'missing --method value'; method_override=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --no-install) do_install=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[[ "$method_override" =~ ^(apt|dnf|pacman|flatpak|)$ ]] || die 'invalid --method (apt, dnf, pacman, or flatpak)'

# Print the command instead of running it under --dry-run.
run() {
  if (( dry_run )); then
    printf '+ %s\n' "$*"
    return 0
  fi
  "$@"
}

# Download to a temporary file beside the destination, then rename: an
# interrupted download can never leave a truncated key or repo file behind.
fetch() {
  local url=$1 dest=$2 tmp
  if (( dry_run )); then
    printf '+ curl -fsSL --proto =https --tlsv1.2 %s -o %s\n' "$url" "$dest"
    return 0
  fi
  tmp=$(mktemp "${dest}.XXXXXX") || die "cannot create a temp file next to $dest"
  if ! curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --max-time 300 "$url" -o "$tmp"; then
    rm -f -- "$tmp"
    die "failed to download $url"
  fi
  chmod 0644 "$tmp"
  mv -- "$tmp" "$dest"
}

detect_method() {
  local id="" id_like=""
  if [[ -r "$os_release" ]]; then
    # shellcheck disable=SC1090
    . "$os_release"
    id=${ID:-}
    id_like=${ID_LIKE:-}
  fi
  local tag=" $id $id_like "
  case "$tag" in
    *" arch "*|*" cachyos "*|*" endeavouros "*|*" manjaro "*|*" garuda "*)
      if command -v pacman >/dev/null 2>&1; then echo pacman; return; fi ;;
  esac
  case "$tag" in
    *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*|*" elementary "*)
      if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi ;;
  esac
  case "$tag" in
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" alma "*|*" nobara "*|*" bazzite "*)
      if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi ;;
  esac
  if command -v flatpak >/dev/null 2>&1; then echo flatpak; return; fi
  echo none
}

install_apt() {
  command -v apt-get >/dev/null 2>&1 || die 'apt-get is unavailable'
  local arch=amd64
  (( dry_run )) || arch=$(dpkg --print-architecture)
  run install -d -m 0755 /etc/apt/keyrings
  fetch "$repo_base/keys/tipsy-signing-key.asc" /etc/apt/keyrings/tipsy.asc
  if (( dry_run )); then
    printf '+ write /etc/apt/sources.list.d/tipsy.list (%s, signed-by=/etc/apt/keyrings/tipsy.asc)\n' "$arch"
  else
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/tipsy.asc] %s/apt stable main\n' \
      "$arch" "$repo_base" > /etc/apt/sources.list.d/tipsy.list
  fi
  run apt-get update
  (( do_install )) || return 0
  run apt-get install -y tipsy
}

install_dnf() {
  command -v dnf >/dev/null 2>&1 || die 'dnf is unavailable'
  fetch "$repo_base/rpm/tipsy.repo" /etc/yum.repos.d/tipsy.repo
  (( do_install )) || return 0
  run dnf install -y tipsy
}

install_pacman() {
  command -v pacman >/dev/null 2>&1 || die 'pacman is unavailable'
  if ! command -v gpg >/dev/null 2>&1; then
    run pacman -Sy --needed --noconfirm gnupg
  fi
  if (( dry_run )); then
    printf '+ curl -fsSL --proto =https --tlsv1.2 %s/keys/tipsy-signing-key.asc -o <temp keyfile>\n' "$repo_base"
    printf '+ pacman-key --add <temp keyfile>\n'
    printf '+ pacman-key --lsign-key <fingerprint from tipsy-signing-key.asc>\n'
  else
    local keyfile fpr
    keyfile=$(mktemp "${TMPDIR:-/tmp}/tipsy-key.XXXXXXXX")
    fetch "$repo_base/keys/tipsy-signing-key.asc" "$keyfile"
    run pacman-key --add "$keyfile"
    fpr=$(gpg --with-colons --show-keys "$keyfile" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    rm -f -- "$keyfile"
    [[ -n "$fpr" ]] || die 'could not read the signing key fingerprint'
    run pacman-key --lsign-key "$fpr"
  fi
  fetch "$repo_base/pacman/tipsy.conf" /etc/pacman.d/tipsy.conf
  if (( dry_run )); then
    printf '+ append "Include = /etc/pacman.d/tipsy.conf" to /etc/pacman.conf if absent\n'
  elif ! grep -qF 'Include = /etc/pacman.d/tipsy.conf' /etc/pacman.conf; then
    printf '\n# Tipsy official repository (added by install.sh)\nInclude = /etc/pacman.d/tipsy.conf\n' >> /etc/pacman.conf
  fi
  run pacman -Sy
  (( do_install )) || return 0
  run pacman -S --needed --noconfirm tipsy
}

install_flatpak() {
  command -v flatpak >/dev/null 2>&1 || die 'flatpak is unavailable'
  run flatpak remote-add --if-not-exists --system tipsy "$repo_base/flatpak/tipsy.flatpakrepo"
  (( do_install )) || return 0
  run flatpak install --system -y tipsy io.github.tipsy_linux.Tipsy
}

if (( ! dry_run )) && [[ "$(id -u)" -ne 0 ]]; then
  die "run as root: curl -fsSL $repo_base/install.sh | sudo bash"
fi

if [[ -n "$method_override" ]]; then
  method=$method_override
else
  method=$(detect_method)
fi
command -v curl >/dev/null 2>&1 || die 'curl is required'

case "$method" in
  apt) printf 'install.sh: Debian/Ubuntu detected; using APT.\n'; install_apt ;;
  dnf) printf 'install.sh: Fedora/RPM detected; using DNF.\n'; install_dnf ;;
  pacman) printf 'install.sh: Arch-based system detected; using pacman.\n'; install_pacman ;;
  flatpak) printf 'install.sh: no native repository detected; using Flatpak.\n'; install_flatpak ;;
  none) die "unsupported distribution; see $repo_base/ and docs/INSTALL.md, or use the AppImage" ;;
esac

printf '\n'
if (( do_install )); then
  printf 'Tipsy is installed and updates through your system package manager.\n'
else
  printf 'The Tipsy repository was added (--no-install): install with your package manager when ready.\n'
fi
printf 'Next: open "Tipsy - Settings" and run the setup assistant to install an\n'
printf 'official Android x86-64 Roblox client. Roblox is never bundled: the\n'
printf 'assistant downloads and verifies it before extracting anything.\n'

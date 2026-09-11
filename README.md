# Tipsy-repo

Official Linux package hosting for [Tipsy](https://github.com/32bitx64bit/Tipsy)
(an open-source Linux compatibility runtime for the official Roblox Android client).

This repository contains **no application source code**. It hosts the files that
let Linux package managers update Tipsy natively:

| Path | What it is |
| --- | --- |
| `public/install.sh` | One-command installer (detects the distribution) |
| `public/apt/` | APT repository (Debian / Ubuntu), suite `stable` |
| `public/rpm/` | DNF/RPM repository (`x86_64`) |
| `public/pacman/` | pacman repository (Arch / CachyOS / EndeavourOS) and `tipsy.conf` |
| `public/flatpak/repo/` | Flatpak/OSTree repository |
| `public/flatpak/tipsy.flatpakrepo` | Flatpak remote definition |
| `public/rpm/tipsy.repo` | DNF `.repo` definition |
| `public/latest.json` (+ `.sig`) | AppImage updater manifest (signed) |
| `public/keys/` | Public repository signing keys |

GitHub Pages serves `public/` at:

```text
https://32bitx64bit.github.io/Tipsy-repo/
```

Standalone release artifacts (AppImage, `.deb`, `.rpm`, Flatpak bundle,
`SHA256SUMS`) live permanently as **Tipsy-repo GitHub Release assets**.
Pages keeps only the latest 2–3 releases of installable repository files so
normal update/rollback works; old release assets are never deleted when Pages
is pruned.

## Install

One command detects your distribution, adds the signed repository, and
installs Tipsy:

```bash
curl -fsSL https://32bitx64bit.github.io/Tipsy-repo/install.sh | sudo bash
```

Supported automatically: **Debian/Ubuntu** (APT), **Fedora/RHEL** (DNF),
**Arch/CachyOS/EndeavourOS** (pacman), and **Flatpak** (when installed) on any
other distribution. Every method below also has a manual equivalent if you
would rather review each step first; full details:
[`docs/INSTALL.md`](docs/INSTALL.md).

Tipsy does **not** include Roblox. After installing Tipsy itself, use the
in-app setup assistant to install an official Android x86-64 Roblox client.

### Debian / Ubuntu (APT)

```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://32bitx64bit.github.io/Tipsy-repo/keys/tipsy-signing-key.asc \
  | sudo tee /etc/apt/keyrings/tipsy.asc > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/tipsy.asc] \
https://32bitx64bit.github.io/Tipsy-repo/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/tipsy.list
sudo apt update
sudo apt install tipsy
```

Updates: `sudo apt update && sudo apt upgrade`.

### Fedora / compatible RPM systems (DNF)

```bash
sudo dnf install -y 'dnf-command(config-manager)'
sudo curl -fsSL -o /etc/yum.repos.d/tipsy.repo \
  https://32bitx64bit.github.io/Tipsy-repo/rpm/tipsy.repo
sudo dnf install -y tipsy
```

Updates: `sudo dnf upgrade`.

### Arch / CachyOS / EndeavourOS (pacman)

```bash
sudo curl -fsSL -o /etc/pacman.d/tipsy.conf \
  https://32bitx64bit.github.io/Tipsy-repo/pacman/tipsy.conf
keyfile=$(mktemp)
curl -fsSL -o "$keyfile" https://32bitx64bit.github.io/Tipsy-repo/keys/tipsy-signing-key.asc
sudo pacman-key --add "$keyfile"
sudo pacman-key --lsign-key "$(gpg --with-colons --show-keys "$keyfile" | awk -F: '/^fpr:/{print $10; exit}')"
rm -f "$keyfile"
grep -q 'Include = /etc/pacman.d/tipsy.conf' /etc/pacman.conf || \
  echo 'Include = /etc/pacman.d/tipsy.conf' | sudo tee -a /etc/pacman.conf
sudo pacman -Sy && sudo pacman -S tipsy
```

The signing key must be locally trusted (`pacman-key --lsign-key`); without it
pacman rejects the signed packages as unknown trust. Updates: `sudo pacman -Syu`.

### Flatpak

```bash
flatpak remote-add --if-not-exists tipsy \
  https://32bitx64bit.github.io/Tipsy-repo/flatpak/tipsy.flatpakrepo
flatpak install tipsy io.github.tipsy_linux.Tipsy
```

Updates: `flatpak update`. Never update a Flatpak install from inside Tipsy.

### AppImage

```bash
# Download Tipsy-<version>-x86_64.AppImage from:
# https://github.com/32bitx64bit/Tipsy-repo/releases/latest
chmod +x Tipsy-*-x86_64.AppImage
./Tipsy-*-x86_64.AppImage
```

AppImage is the one format Tipsy updates itself, via its in-app updater and
`latest.json`. All other formats are updated by the system package manager.

## How releases get here

1. A `v*` tag on `32bitx64bit/Tipsy` builds and signs the AppImage
   (existing `release.yml`, Sigstore keyless).
2. `publish-repo.yml` in the Tipsy repository builds `.deb`/`.rpm`/pacman
   packages, creates the matching Tipsy-repo Release, regenerates all
   repository metadata plus `latest.json`, verifies everything, and pushes here.
3. This workflow (`pages.yml`) republishes `public/` to GitHub Pages.

Details: [`docs/RELEASE-PROCESS.md`](docs/RELEASE-PROCESS.md).
Signing and secrets: [`docs/SIGNING.md`](docs/SIGNING.md).

## Design rule

- APT owns `.deb` updates (`apt upgrade`).
- DNF owns `.rpm` updates (`dnf upgrade`).
- pacman owns `.pkg.tar.zst` updates (`pacman -Syu`).
- Flatpak owns Flatpak updates (`flatpak update`).
- Tipsy owns **AppImage** updates only (in-app updater via `latest.json`).

Tipsy never installs `.deb`, `.rpm`, pacman, or Flatpak updates itself.

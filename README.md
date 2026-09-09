# Tipsy-repo

Official Linux package hosting for [Tipsy](https://github.com/32bitx64bit/Tipsy)
(an open-source Linux compatibility runtime for the official Roblox Android client).

This repository contains **no application source code**. It hosts the files that
let Linux package managers update Tipsy natively:

| Path | What it is |
| --- | --- |
| `public/apt/` | APT repository (Debian / Ubuntu), suite `stable` |
| `public/rpm/` | DNF/RPM repository (`x86_64`) |
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

Tipsy does **not** include Roblox. After installing Tipsy itself, use the
in-app setup assistant to install an official Android x86-64 Roblox client.

> Until the first release is published here, the APT/DNF/Flatpak repositories
> are empty — install the AppImage instead. Afterwards, updates arrive through
> your normal system package manager. Full details: [`docs/INSTALL.md`](docs/INSTALL.md).

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
2. `publish-repo.yml` in the Tipsy repository builds `.deb`/`.rpm`,
   creates the matching Tipsy-repo Release, regenerates all repository
   metadata plus `latest.json`, verifies everything, and pushes here.
3. This workflow (`pages.yml`) republishes `public/` to GitHub Pages.

Details: [`docs/RELEASE-PROCESS.md`](docs/RELEASE-PROCESS.md).
Signing and secrets: [`docs/SIGNING.md`](docs/SIGNING.md).

## Design rule

- APT owns `.deb` updates (`apt upgrade`).
- DNF owns `.rpm` updates (`dnf upgrade`).
- Flatpak owns Flatpak updates (`flatpak update`).
- Tipsy owns **AppImage** updates only (in-app updater via `latest.json`).

Tipsy never installs `.deb`, `.rpm`, or Flatpak updates itself.

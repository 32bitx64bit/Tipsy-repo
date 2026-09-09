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

See [`docs/INSTALL.md`](docs/INSTALL.md) for per-format instructions
(APT, DNF/RPM, Flatpak, AppImage).

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

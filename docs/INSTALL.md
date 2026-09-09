# Install Tipsy on Linux

Official packages are hosted in this repository via GitHub Pages:

```text
https://32bitx64bit.github.io/Tipsy-repo/
```

Tipsy still does **not** include Roblox. After installing Tipsy itself, use the
in-app setup assistant to install an official Android x86-64 Roblox client.

## Debian / Ubuntu (APT)

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

Updates arrive through APT like any other package:

```bash
sudo apt update
sudo apt upgrade
```

> Note: the signing key appears under `keys/` after the first signed release
> (see `SIGNING.md`). Until then, the `curl` step will 404; install the
> AppImage below instead.

## Fedora / compatible RPM systems (DNF)

```bash
sudo dnf install -y 'dnf-command(config-manager)'
sudo curl -fsSL -o /etc/yum.repos.d/tipsy.repo \
  https://32bitx64bit.github.io/Tipsy-repo/rpm/tipsy.repo
sudo dnf install -y tipsy
```

Updates arrive through DNF:

```bash
sudo dnf upgrade
```

## Flatpak

```bash
flatpak remote-add --if-not-exists tipsy \
  https://32bitx64bit.github.io/Tipsy-repo/flatpak/tipsy.flatpakrepo
flatpak install tipsy io.github.tipsy_linux.Tipsy
```

Updates arrive through Flatpak:

```bash
flatpak update
```

Do not update a Flatpak install from inside Tipsy; the sandbox forbids it and
Flatpak owns updates.

## AppImage

1. Download the latest `Tipsy-<version>-x86_64.AppImage` from the
   [Tipsy-repo releases](https://github.com/32bitx64bit/Tipsy-repo/releases/latest).
2. Make it executable and run it:

```bash
chmod +x Tipsy-*-x86_64.AppImage
./Tipsy-*-x86_64.AppImage
```

AppImage is the one format Tipsy updates itself: the in-app updater checks
`https://32bitx64bit.github.io/Tipsy-repo/latest.json`, verifies its signature,
and atomically replaces the AppImage file. All other formats are updated by
the system package manager.

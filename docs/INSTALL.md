# Install Tipsy on Linux

Easiest: one command detects the distribution, adds the signed repository, and
installs Tipsy:

```bash
curl -fsSL https://32bitx64bit.github.io/Tipsy-repo/install.sh | sudo bash
```

It handles Debian/Ubuntu (APT), Fedora/RHEL (DNF), Arch/CachyOS/EndeavourOS
(pacman), and falls back to Flatpak (when installed) elsewhere. `--dry-run`
prints every command without changing anything, `--method` forces one package
manager, and `--no-install` adds the repository only.

Prefer to inspect each step? The manual commands are below.

Tipsy still does **not** include Roblox. After installing Tipsy itself, use the
in-app setup assistant to install an official Android x86-64 Roblox client.

Official packages are hosted in this repository via GitHub Pages:

```text
https://32bitx64bit.github.io/Tipsy-repo/
```

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

## Arch / CachyOS / EndeavourOS (pacman)

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

`pacman-key --lsign-key` marks the Tipsy signing key as locally trusted;
without it pacman refuses the signed packages as unknown trust. Updates arrive
through pacman:

```bash
sudo pacman -Syu
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

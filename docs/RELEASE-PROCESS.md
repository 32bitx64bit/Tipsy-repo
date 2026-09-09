# Release process

Minimal maintainer flow:

```text
tag/release Tipsy  →  GitHub Actions does everything else
```

## Prerequisites (one time)

1. Create the `Tipsy-repo` GitHub repository under `32bitx64bit`
   (see below) and push this directory to `main`.
2. Enable GitHub Pages: repository Settings → Pages → Source: **GitHub
   Actions**. The `pages.yml` workflow deploys `public/` on every push to
   `main`. This step cannot be done from the command line; enable it in the
   browser once.
3. Configure secrets in the **Tipsy** repository (`TIPSY_REPO_TOKEN`,
   `TIPSY_GPG_PRIVATE_KEY`, `TIPSY_GPG_KEY_ID`, `TIPSY_GPG_PASSPHRASE`) as
   described in `SIGNING.md`.
4. Publish the GPG public key to `public/keys/tipsy-signing-key.asc`.

## Publishing a version

```bash
# In the Tipsy source repository:
git tag v1.2.3
git push origin v1.2.3
```

That is the whole manual process. Automation takes over:

1. `release.yml` (Tipsy) builds the AppImage, signs it keylessly (Sigstore),
   and publishes the Tipsy GitHub Release.
2. `publish-repo.yml` (Tipsy, trigger: release `published`) then:
   - rejects prereleases for the stable channel (stable repos only advance on
     full releases);
   - builds `tipsy_1.2.3_amd64.deb` and `tipsy-1.2.3-1.x86_64.rpm`;
   - downloads the AppImage from the Tipsy release;
   - creates/updates the matching `v1.2.3` Tipsy-repo Release and uploads all
     artifacts plus `SHA256SUMS` (`gh release upload --clobber` so reruns
     replace same-named assets intentionally);
   - checks out Tipsy-repo with `TIPSY_REPO_TOKEN`, runs
     `update-apt-repo.sh`, `update-rpm-repo.sh`, `update-flatpak-repo.sh`
     (bundle import when a Flatpak bundle exists), prunes Pages history to the
     newest 3 (Releases keep everything), regenerates `latest.json` from the
     real files, signs metadata, runs `verify-repositories.sh --strict`, and
     pushes to `main`.
3. `pages.yml` (here) deploys `public/` to Pages.

Any failure in building, signing, validation, or manifest generation fails
the publish run before pushing, so a broken repository is never published and
`latest.json` never advances early.

## Idempotent reruns

Re-running `publish-repo.yml` for the same version is safe: pool/RPM copies
skip identical files, metadata is regenerated from scratch (not appended),
`latest.json` is rewritten deterministically, and existing Release assets are
clobbered only with identical rebuilt content. APT/RPM/Flatpak metadata is
never duplicated or corrupted by a rerun.

## Prereleases

GitHub prereleases never touch the stable APT/RPM/Flatpak repos or
`latest.json`. The manifest schema carries a `channel` field so `beta`/`nightly`
channels can be added later without breaking the AppImage updater.

## AppImage updater contract (for the future in-app implementation)

Only AppImage installs self-update. Detection: the `APPIMAGE` environment
variable exists (set by the AppImage runtime to the path of the running
file). All other installs must show "Updates for this installation are
managed by your system package manager" and change nothing.

Flow: fetch `https://32bitx64bit.github.io/Tipsy-repo/latest.json`, verify
`latest.json.sig` against `public/keys/tipsy-signing-key.asc`, compare
semantic versions, download the matching `linux-<arch>-appimage` asset URL,
verify its SHA-256, write to a temporary file beside the current AppImage,
`chmod +x`, quit, atomically rename over the old file, restart. Never touch
`.deb`/`.rpm`/Flatpak installs.

## Creating the GitHub repository (one time)

The `gh` CLI was not available when this directory was prepared, so the
remote repository may not exist yet. Create it and push:

```bash
cd /home/gavin/Desktop/Tipsy-repo
gh repo create 32bitx64bit/Tipsy-repo --public --source=. --remote=origin --push
# Without gh: create an empty public repo named Tipsy-repo under 32bitx64bit
# in the browser, then:
git push -u origin main
```

Then enable Pages (Settings → Pages → Source: GitHub Actions) and make a first
push; the deployment URL is `https://32bitx64bit.github.io/Tipsy-repo/`.

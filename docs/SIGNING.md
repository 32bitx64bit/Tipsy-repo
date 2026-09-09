# Signing

One GPG release-signing key signs everything the system package managers
trust: the APT `Release` file, RPM packages plus `repomd.xml`, the Flatpak
summary, and the `latest.json` detached signature. AppImage artifacts keep
their existing keyless Sigstore signatures from the Tipsy `release.yml`
workflow; this key does not replace that.

## Secrets to configure

Configure these in the **Tipsy source repository**
(`https://github.com/32bitx64bit/Tipsy` → Settings → Secrets and variables →
Actions). Nothing secret is ever committed here or exposed through Pages.

| Secret | Purpose |
| --- | --- |
| `TIPSY_REPO_TOKEN` | Fine-grained PAT scoped to **only** `32bitx64bit/Tipsy-repo` with `Contents: read and write`. Lets the Tipsy `publish-repo.yml` workflow create Releases, upload assets, and push repository metadata. Migrate to a GitHub App later without changing the workflow (only the token source changes). |
| `TIPSY_GPG_PRIVATE_KEY` | ASCII-armored private key (`gpg --armor --export-secret-keys KEYID`). Imported with `gpg --import` during publish; never logged. |
| `TIPSY_GPG_KEY_ID` | Key ID / fingerprint of the release-signing key (also the APT/RPM/Flatpak signer). |
| `TIPSY_GPG_PASSPHRASE` | Passphrase for the private key (empty if the key has none, but a passphrase is recommended). Passed via file descriptor / `--pinentry-mode loopback` with stdin, never as a CLI argument. |

The publish workflow fails closed with an actionable error when any of these
is missing, so a release can never silently publish unsigned metadata.

## Creating the key (one time, on a trusted machine)

```bash
# 1. Generate an RSA-4096 signing key (no encryption subkey needed).
gpg --full-generate-key
#    Kind: RSA (sign only). Expiry: 2y is reasonable.

# 2. Note the key ID.
gpg --list-secret-keys --keyid-format LONG

# 3. Export the PUBLIC key into this repo and push it:
gpg --armor --export KEYID > public/keys/tipsy-signing-key.asc
git add public/keys/tipsy-signing-key.asc
git commit -m "keys: publish Tipsy release-signing public key"
git push

# 4. Export the PRIVATE key into the Tipsy repo secret TIPSY_GPG_PRIVATE_KEY:
gpg --armor --export-secret-keys KEYID
#    Paste the full output (all lines) as the secret value.
```

Then set `TIPSY_GPG_KEY_ID` (the fingerprint) and `TIPSY_GPG_PASSPHRASE` in the
Tipsy repository secrets.

## Rotation

1. Generate the new key as above with a later expiry.
2. Append (do not replace) the new public key next to the old one, or rotate
   `tipsy-signing-key.asc` and keep the old file as
   `tipsy-signing-key-YYYY.asc` so existing installs keep verifying.
3. Update the three `TIPSY_GPG_*` secrets in the Tipsy repository.
4. The next publish re-signs all live metadata with the new key.

## Verification by users

- APT verifies `InRelease` against `/etc/apt/keyrings/tipsy.asc` on every
  `apt update` (see `INSTALL.md`).
- DNF verifies RPM and repodata signatures via the `gpgkey=` line in
  `public/rpm/tipsy.repo`.
- Flatpak verifies the summary against the key embedded in
  `public/flatpak/tipsy.flatpakrepo`.
- The AppImage updater verifies `latest.json.sig` against the public key
  shipped at `public/keys/tipsy-signing-key.asc` (or bundled with Tipsy).

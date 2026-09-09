# Release-signing public keys

`tipsy-signing-key.asc` is the ASCII-armored GPG public key that signs the
APT `InRelease`, the RPM packages and `repomd.xml`, the Flatpak repository
summary, and `latest.json.sig`. Setup and rotation: `docs/SIGNING.md`.

Fingerprint: `1968 CDD0 147E 08C0 D378 74F2 275A 340F 7181 FBDA`

APT (`signed-by=`), DNF (`gpgkey=`), Flatpak (`GPGKey=` in
`flatpak/tipsy.flatpakrepo`), and the AppImage updater all verify against
this key and fail closed if a signature is missing or does not match.

# Release-signing public keys

The ASCII-armored GPG public key will live here as
`tipsy-signing-key.asc` after the one-time signing setup
(see `docs/SIGNING.md`).

Until the first signed release, this directory intentionally contains no key:
APT (`signed-by=`), DNF (`gpgkey=`), Flatpak (`GPGKey=`), and the AppImage
updater (`latest.json.sig` verification) all fail closed rather than trust an
unsigned repository.

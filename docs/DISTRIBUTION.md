# Sharing a build

The output is `dist/Zero-K.app`, for Apple Silicon Macs running macOS 26 or
newer. KosmicKrisp uses Metal 4. The app bundles its ARM64 engine, native Steam
helper, .NET runtime, graphics libraries, fonts, AI and lobby resources. End
users do not need Homebrew, Mono, .NET or Rosetta installed.

Maps and the Zero-K game are downloaded into Application Support as needed.
Steam sign-in requires the ordinary Steam client to be installed and running;
ordinary Zero-K account/offline play does not require Steam. No Steam account
or client installation is copied into the application.

The owner intentionally distributes without Developer ID or notarization.
Build scripts apply only ad-hoc signatures after relocating native code.
These require no certificate and do not establish an Apple-verified publisher.

For a downloaded copy you trust, macOS may require approval under **System
Settings → Privacy & Security → Open Anyway** after the first launch attempt.
Alternatively, for that specific trusted copy only:

```sh
xattr -dr com.apple.quarantine "/Applications/Zero-K.app"
```

Do not disable Gatekeeper globally. The build does not change security settings.

Create a disk image with `./scripts/build-dmg.sh` after building the app. It
contains `Zero-K.app` and an Applications shortcut for drag-to-install. The
read-only DMG includes only the audited app,
not Application Support, source worktrees, logs or developer caches. Do not
copy personal data into the app before sharing it. The same app should work
after being renamed or moved.

A local relocation/dependency audit is not a substitute for testing on another
Mac. Record the OS and hardware used for validation, and keep known limitations
explicit. Publish the matching fork revisions, build scripts, dependency pins
and third-party notices with a public binary release.

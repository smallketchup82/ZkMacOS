# Sharing a build

The output is `dist/Zero-K.app`, for Apple Silicon Macs running macOS 26 or
newer. KosmicKrisp uses Metal 4. The app bundles its ARM64 engine, native Steam
helper, .NET runtime, graphics libraries, fonts, AI and lobby resources. End
users do not need Mono, .NET or Rosetta installed. Homebrew is needed only for
the cask installation method.

Maps and the Zero-K game are downloaded into Application Support as needed.
Steam sign-in requires the ordinary Steam client to be installed and running;
ordinary Zero-K account/offline play does not require Steam. No Steam account
or client installation is copied into the application.

Published DMGs can be installed manually or through this repository's Homebrew
tap. Publishing a non-prerelease GitHub release with the DMG and its checksum
triggers `.github/workflows/update-homebrew.yml`, which verifies the download
and commits a versioned cask. See the README for installation and upgrade
commands. Homebrew upgrades replace the app and preserve
Application Support. Sparkle provides in-app updates for both installation
methods. The generated cask declares `auto_updates true`; Homebrew retains its
own receipt and an explicit upgrade may reinstall an already self-updated app.
Do not run Homebrew upgrades during a game or an active Sparkle installation.

Sparkle reads the signed `appcast.xml` from the latest GitHub release and
fetches its DMG using an exact versioned release URL. Both are release assets;
no independent feed hosting is needed. The release workflow requires the
`SPARKLE_PUBLIC_ED_KEY` repository variable and `SPARKLE_PRIVATE_ED_KEY` secret;
see the README for key generation and backup. The app verifies feed and archive
signatures before extraction. It defers installation/relaunch until its helper
and engine processes exit. Users can check manually or disable automatic checks
from the ZK menu-bar item. Existing installations need one manual/Homebrew
upgrade to receive this updater.

Local builds without a public key leave updating disabled. The Sparkle
framework is copied intact, including its universal binaries, symlinks and
upstream signatures. It is not thinned or relocated with engine dependencies.
The enclosing app remains ad-hoc signed without Hardened Runtime Library
Validation; Sparkle signing does not change initial Gatekeeper approval.

For an automated build, run **Actions → Build and publish macOS release → Run
workflow** on `main`. It allocates the next Toronto-date CalVer tag, builds and
audits the app, publishes the completed artifacts, and calls the cask workflow
directly. It caches dependencies and compiler results between runs. The
workflow's own release event does not trigger another run with `GITHUB_TOKEN`.
See the README for version allocation and attached metadata.

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
uses `create-dmg` to arrange `Zero-K.app` and an Applications shortcut with an
install arrow. `app/dmg-background.swift` generates the Retina background.
Building the image requires a logged-in desktop session and Finder automation
permission when prompted for the normal interactive build. With `CI=true`,
the script uses pinned `dmgbuild` 1.6.7 to write the same layout metadata
without Finder automation. This does not rebuild the engine. The interactive build applies
`patches/create-dmg-finder-timing.patch` to a temporary copy of the tool
(tested with create-dmg 1.3.0) so Finder finishes applying the view and saves
it without reopening into tab defaults on macOS 27. The installed Homebrew
tool is unchanged.

Fresh profiles start with windowed lobby and game, Retina text and UI, Low
graphics, three-finger tilt disabled, and cursor locking disabled. Saved user
preferences take precedence; updating the app does not reset them.

The read-only DMG contains the audited app and installer artwork, without
Application Support, source worktrees, logs or developer caches. Do not
copy personal data into the app before sharing it. The same app should work
after being renamed or moved.

A local relocation/dependency audit is not a substitute for testing on another
Mac. Record the OS and hardware used for validation, and keep known limitations
explicit. Publish the matching fork revisions, build scripts, dependency pins
and third-party notices with a public binary release.

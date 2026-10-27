# ZkMacOS

An unofficial native Apple Silicon macOS build of Zero-K, with its own Chobby
and Recoil forks. Requires **macOS 26 or newer**: the current Mesa KosmicKrisp
renderer uses Metal 4.

The final app includes the ARM64 engine, Steam helper, .NET runtime, renderer,
fonts and AI. Players do not need Homebrew, Mono, .NET or Rosetta. Steam login
uses the player's installed Steam client; ordinary account/offline play is
also available.

## Build

Developers need Xcode/its command-line tools and the dependencies in `Brewfile`:

```sh
brew bundle
./scripts/build-app.sh
./scripts/run-app.sh
```

The legacy shared launcher assemblies are compiled as AnyCPU with Mono MSBuild
during development; the native helper is published with .NET SDK 10.0.403 and
a bundled ARM64 .NET 10.0.14 runtime. Mono/Rosetta are build-tool requirements,
not requirements of the resulting app. The engine uses GCC 16; Mesa 26.3.0-rc1,
libclc and Steamworks.NET 2025.164.1 sources are checksum-pinned.

The build script fetches the exact source revisions in `sources.lock.json`,
prepares assets from `assets.lock.json`, builds the components, creates
`dist/Zero-K.app` and audits its native dependencies, architecture and ad-hoc
signatures. Logs are in `build/logs/`. Close the running app before replacing
it with a new build.

Engine builds are incremental: edits recompile affected source files and relink.
The script reuses the configured build directory. Use
`RECONFIGURE_ENGINE=1 ./scripts/build-app.sh` when changing toolchain options;
Ninja also detects changes to the engine's CMake files automatically. Lobby,
helper and packaging edits do not require a clean engine rebuild.

Create the drag-to-install disk image separately:

```sh
./scripts/build-dmg.sh
```

The result is `dist/Zero-K-macOS-arm64.dmg` with the app and an Applications
shortcut, an install arrow, and a Retina background. The script uses
[create-dmg](https://github.com/create-dmg/create-dmg), installed by the Brewfile,
to save the Finder layout. Run it in a logged-in macOS desktop session and allow
Finder automation if macOS asks. The DMG does not contain development files or user data.

## Repository layout

| Location | Purpose |
| --- | --- |
| `app/` | Native bootstrap and clean first-launch defaults |
| `scripts/` | Fetch, build, bundle, audit, test and distribution commands |
| `tests/` | Public test scripts and settings-contract checks |
| `patches/` | Version-specific CircuitAI ARM64 fix |
| `docs/` | Migration, engine updates, distribution and third-party notices |
| `sources.lock.json`, `assets.lock.json` | Exact source and download pins |
| `external/` | Ignored separate Git checkouts of the forks |
| `build/`, `dist/`, `.cache/`, `.local/` | Ignored generated files and private development state |

This repo does not vendor copies of Recoil, Chobby or the launcher. Their
macOS changes belong in:

- [RecoilEngine](https://github.com/smallketchup82/RecoilEngine), branch `macos/2026.07.04`.
- [Chobby](https://github.com/smallketchup82/Chobby), branch `macos-port`.
- [Zero-K-Infrastructure](https://github.com/smallketchup82/Zero-K-Infrastructure), branch `macos-port`, for the Steam helper.

The initial engine is based on the actual upstream July release. See
[engine updates](docs/ENGINE-UPDATES.md) before moving to another version;
relabeling a different simulation is not a compatibility fix.

## Application data and controls

Static code, libraries, fonts, lobby and AI resources stay inside the app.
Maps, game downloads, accounts, settings, saves, replays, logs and caches live
in `~/Library/Application Support/Zero-K`. First launch copies only missing
clean defaults. The app does not import any developer's account or content.

The optional [migration script](docs/MIGRATION.md) imports the original local
experiment separately; its detailed hash report remains private under `.local/`.

Retina modes are Standard, Retina text/UI and Full Retina. Choose them in the
lobby's Graphics settings or the in-game Graphics/Display settings, then quit
and reopen the app. Text/UI mode is the default. VSync is forced on for this
port, and the native FPS counter is available in game.

Trackpad controls use two-finger movement to pan, pinch to zoom, and
Option–two-finger movement to tilt; swipe down to tilt up. Three-finger tilt is
off by default to avoid palm gestures. Enable it under the in-game
Settings/Camera/Trackpad options when macOS does not reserve that gesture.
Taps and secondary clicks follow macOS settings.

## Verify and contribute

```sh
luajit tests/check-settings.lua
luajit tests/check-display-sync.lua
luajit tests/check-trackpad-settings.lua
uv run --python python3 scripts/audit-app.py
uv run --python python3 scripts/smoke-app.py --seconds 90
uv run --python python3 scripts/smoke-download.py
```

The smoke test builds the app first, copies it to a different path, runs a
bounded skirmish through the app entry point and checks that the app's contents
remain unchanged. It uses existing downloads from Application Support; they
are not bundled. It caps engine unified memory at 8 GiB and records results
under `.local/relocation-test/`.
The separate download check exercises the packaged helper's local protocol and
downloads a public map into `.local/download-test/`, without opening a game or
using the player's account/settings files.

For display changes, also test Fairyland at Medium and High water quality in
all three Retina modes. Pan past the cliffs and trees, zoom, tilt and resize
the window; check water refraction/reflections and that UI text stays aligned.
Settings and camera changes in an isolated test should not alter the player's
normal Application Support profile.

Edit a fork under `external/` for engine, lobby or helper changes; edit this
repo for orchestration and packaging. Source preparation preserves existing
local work. Commit validated fork changes and update the lock file for a
release. Share the matching source revisions with distributed binaries.

The app intentionally has no Developer ID signature or notarization. Only
certificate-free ad-hoc signatures are applied to modified native binaries.
See [distribution and macOS approval](docs/DISTRIBUTION.md). Another-Mac testing
and multiplayer synchronization checks remain necessary before broader release.

These macOS changes and build tools were developed with OpenAI Codex assistance.
Upstream copyrights and licenses are preserved; see [third-party notices](docs/THIRD-PARTY.md).

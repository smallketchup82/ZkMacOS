# ⚠️ READ BEFORE PLAYING ⚠️ 

> 1. **DO NOT send ZkMacOS bug reports to the official Zero-K developers. [File issues in this repository](https://github.com/smallketchup82/ZkMacOS/issues) instead.**
> 2. **ZkMacOS is a third-party client. It is not endorsed by or officially supported by the Zero-K developers.**
> 3. **This port is built on experimental technology and has not been thoroughly tested. Bugs and breakage are to be expected. Understand that risk before putting Elo on the line in a ranked game. If you choose to play using ZkMacOS and your client crashes during a game, that is entirely your fault. You accept responsibility for the resulting loss or rating change.**

# ZkMacOS

Play [Zero-K](https://zero-k.info/) on Apple Silicon Macs with GPU acceleration,
native trackpad gestures, and crisp Retina text. ZkMacOS packages custom Recoil,
Chobby, and launcher builds into a self-contained `Zero-K.app`.

## What this adds to Zero-K

| Feature | What you get |
| --- | --- |
| Native Apple Silicon support | ARM64 engine, AI, and launcher helper. No Wine, Rosetta, Mono, or separately installed .NET runtime needed to play. |
| GPU acceleration on macOS | An experimental Mesa graphics stack runs the engine's OpenGL rendering through Zink and KosmicKrisp to Metal 4, rather than software rendering. |
| Trackpad camera controls | Two-finger pan, pinch zoom, Option + two-finger tilt, and optional three-finger tilt, with sensitivity and momentum settings. |
| Retina rendering modes | Choose standard resolution, crisp text and UI with a lower-resolution world, or full-resolution Retina rendering. |
| Native performance display | An FPS counter showing frame interval and the active Retina mode. |
| macOS application packaging | A drag-to-install DMG, a self-contained app with the Zero-K icon, and writable data kept in Application Support. |
| Native Steam login integration | A bundled ARM64 helper connects the lobby to your installed Steam client. Ordinary account login and offline play are also available. |
| macOS graphics and input fixes | Changes for water rendering, reflections, Retina sizing, window behavior, and trackpad input in the custom engine and lobby. |

This keeps Zero-K's own Chobby lobby, multiplayer, spectating, downloads, and AI
skirmishes. Those are existing Zero-K features; this project makes them usable
through this macOS port. Multiplayer synchronization and long-session stability
still need broader testing. Connecting to a server is not proof of compatibility.
See [known limitations and remaining testing](docs/TODO.md).

## Download and run

### Requirements

- An **Apple Silicon Mac**; Intel Macs are not supported by these builds.
- **macOS 26 or newer**, because the current renderer requires Metal 4.
- Internet access to download the Zero-K game and maps, and for online play.
- Steam installed and running **only if you want Steam login**.

You do not need developer tools, Mono, .NET, Wine, or Rosetta to run a prebuilt
app. Homebrew is needed only for Method 1.

### Method 1: Homebrew (recommended)

Install [Homebrew](https://brew.sh/) if you do not have it, then add this
repository as a tap and install the cask:

```sh
brew tap smallketchup82/zkmacos https://github.com/smallketchup82/ZkMacOS.git
brew trust --cask smallketchup82/zkmacos/zkmacos
brew install --cask smallketchup82/zkmacos/zkmacos
```

The trust command authorizes this third-party cask specifically, rather than
every package in the tap. Review this repository before granting trust. If
your older Homebrew version does not provide `brew trust`, omit that line.

Open **Zero-K.app** from Applications. You may still need to approve the app
in macOS using the instructions below.

To update, quit Zero-K, then run:

```sh
brew update
brew upgrade --cask smallketchup82/zkmacos/zkmacos
```

The release workflow updates the tap's version and checksum automatically;
Homebrew then downloads and replaces the app when you upgrade. It does not
silently update a running game. Your Application Support data is preserved.

If you installed manually before, move the old `Zero-K.app` out of Applications
before installing the cask, so Homebrew can manage its own copy. Keep your
Application Support folder. To remove the Homebrew-managed app later:

```sh
brew uninstall --cask smallketchup82/zkmacos/zkmacos
```

Uninstalling the cask also leaves your Application Support data in place.

### Method 2: Manual

1. Open the [latest ZkMacOS release](https://github.com/smallketchup82/ZkMacOS/releases/latest)
   and download `Zero-K-macOS-arm64.dmg` and its `.sha256` checksum file.
2. Open the DMG and drag **Zero-K** onto **Applications** using the arrow.
3. Eject the disk image and open **Zero-K.app** from Applications.
4. Approve the app in macOS if needed, then sign in or choose offline play.
   The lobby downloads the game and required maps as needed; these are not
   included in the DMG.

Place the checksum file beside the DMG and verify it in Terminal from that
directory:

```sh
shasum -a 256 -c Zero-K-macOS-arm64.dmg.sha256
```

### macOS approval

The app is **not Developer ID signed or notarized**. Its ad-hoc signatures do
not identify an Apple-verified publisher, so downloaded copies may be blocked.
Only approve a copy whose source you trust.

After attempting to open it, use **System Settings → Privacy & Security →
Open Anyway** if available. Alternatively, remove quarantine from that specific
trusted copy:

```sh
xattr -dr com.apple.quarantine "/Applications/Zero-K.app"
```

See [distribution and macOS approval](docs/DISTRIBUTION.md) for more detail.

### Updating a manual installation

At launch, the app checks GitHub for a newer published release in the
background. If one is available, a native macOS dialog shows the installed
and available versions, package-manager update instructions, and an **Open
GitHub Releases** button. **Later** dismisses it until the next launch.
Offline or failed checks are silent and do not delay startup. The app checks
once per launch and does not download or install updates itself.

Quit Zero-K completely, then replace the app in Applications with the new one
from the DMG. Your downloaded content and saved preferences remain in
Application Support. New defaults apply to fresh profiles; updating the app
does not overwrite your existing choices.

### macOS Game Mode

The app declares its game category and opts into macOS Game Mode. To use it,
put Zero-K in macOS full-screen mode and keep it in the foreground. The default
windowed mode does not activate Game Mode.

On macOS 26, press **Command-Esc** while in full screen, then open Game Overlay
settings to check Game Mode. If you previously turned it off for Zero-K, turn it
back on there; macOS remembers that choice across launches. See
[Apple's Game Mode instructions](https://support.apple.com/en-us/105118).

## Settings, controls, and application data

### First-launch defaults

Before the lobby starts for the first time on each app version, a native
dialog repeats the warnings above and links to this project's issue tracker.
Choose **I Understand** to continue. Acknowledgments are
saved in `startup-warning-versions.json` in your Application Support data.

| Setting | Default |
| --- | --- |
| Lobby and game display | Windowed |
| Graphics preset | Low |
| Retina mode | Retina text and UI |
| Trackpad camera controls | Enabled |
| Three-finger tilt | Disabled; use Option + two fingers |
| Lock Cursor to Window | Disabled |
| Native FPS counter | Enabled |
| VSync | Forced on |

### Where your data lives

The app's code and bundled resources stay inside `Zero-K.app`. Your accounts,
settings, downloaded games and maps, replays, saves, logs, and caches live in:

```text
~/Library/Application Support/Zero-K
```

In Finder, press **⌘⇧G** and paste that path to open it.

| File or folder, relative to that directory | Purpose |
| --- | --- |
| `springsettings.cfg` | Engine settings, including Retina mode and native trackpad settings |
| `LuaMenu/Config/IGL_data.lua` | Saved lobby configuration |
| `LuaUI/Config/ZK_data.lua` | Saved in-game UI and widget options, including cursor locking |
| `games/`, `maps/`, `packages/`, `pool/`, `rapid/` | Downloaded content and content-management data |
| `infolog.txt`, `log/` | Engine and launcher logs |
| `demos/`, `saves/` | Replays and saved games |

Prefer changing settings through the lobby or in-game menus. Quit the app
before editing configuration files manually. Back up this directory if you
want to preserve your setup. It can contain account information and other
personal data: do not upload the whole directory with a bug report. Review logs
and redact credentials, authentication tickets, and personal information before
sharing them.

### Steam integration

Start the normal macOS Steam client and sign in before opening Zero-K. Use the
lobby's Steam login option; the bundled helper handles the connection to Steam.
You do not need a macOS Zero-K installation from the Steam store, and the app
does not bundle the Steam client or anyone else's account.

Steam is optional. Use ordinary Zero-K account login or offline play if you do
not want Steam integration. If Steam login does not respond, check that Steam
is running and signed in, then fully quit and reopen Zero-K.

### Trackpad gestures

Open the **in-game Settings → Camera → Trackpad** menu.

| Gesture | Action |
| --- | --- |
| Two-finger movement | Pan the camera |
| Pinch | Zoom |
| Option + two-finger movement | Tilt; swipe down to tilt the camera up |
| Three-finger movement | The same tilt direction, when Three-finger tilt is enabled |
| Tap/click | Normal selection, following macOS trackpad settings |
| Two-finger tap/secondary click | Right-click commands, following macOS trackpad settings |

Three-finger tilt is off by default to avoid accidental palm gestures. Enable
it with **Three-finger tilt** if you want it. macOS may reserve that gesture
for system actions; Option + two fingers is the fallback and does not require
three-finger tilt to be enabled.

You can also adjust **Pan sensitivity**, **Pinch sensitivity**, **Tilt
sensitivity**, **Reverse camera pan**, and **Camera momentum**, or disable
**Trackpad camera controls** entirely. Three-finger tilt changes apply
immediately. Configure tap-to-click and secondary click in macOS Trackpad
settings. There is no custom Option + three-finger gesture.

### Retina and FPS settings

Choose **Retina / High-DPI** in the **lobby's Graphics settings**, directly below
**Graphics Driver Selected**, or use **in-game Settings → Graphics → Display**.
The setting is shared between the lobby and game.

| Mode | Effect |
| --- | --- |
| Standard | Standard-resolution world and UI; lowest rendering bandwidth |
| Retina text and UI | Crisp UI and text with the world at standard resolution; the default balance |
| Full Retina | Renders the world at Retina resolution too; costs more GPU time and bandwidth |

**Quit Zero-K completely and reopen it after changing Retina mode.** Starting
another battle is not enough.

Toggle **MetalFX spatial upscaling** below the Retina setting in the lobby's
Graphics settings, or in **in-game Settings → Graphics → Display**. It applies
immediately to the lower-resolution world in **Retina text and UI** mode on a
Retina display; text and UI still draw at native resolution. Standard and Full
Retina modes do not use it. If MetalFX is unavailable or fails, the engine logs
the reason and uses the existing bilinear scaling.

MetalFX is off by default. The bundled Mesa bridge can share GPU textures with
MetalFX and present the finished frame directly through Metal. This experimental
path is opt-in and still incurs synchronization costs. See
[validation and measurements](docs/METALFX.md).
To configure it manually, quit Zero-K and set these values in
`~/Library/Application Support/Zero-K/springsettings.cfg`:

```ini
MacRetinaMode = 1
MacMetalFXSpatial = 1
```

Set `MacMetalFXSpatial = 0` to disable it. The lobby reads this shared engine
setting, so an older saved lobby selection does not override manual edits.

Set `MacGPUSharing = 1` in `springsettings.cfg` to test GPU sharing in any display
mode. It is disabled by default. Set it back to `0` to use the CPU staging
compatibility path. Older or incompatible Mesa libraries fall back
automatically and log a `[MacGPUSharing]` warning. That fallback can cost more
bandwidth and GPU/CPU synchronization time.

Toggle **Show native FPS counter** in the same in-game Display menu, or use
`/fps`. It displays FPS, average frame interval, and the current Retina mode,
which helps compare UI-only and Full Retina performance.

### Graphics, windows, and cursor locking

Use the lobby's Graphics settings to choose a quality preset. Fresh profiles
start at **Low**; higher presets and optional effects may expose rendering
bugs or reduce performance. VSync is forced on in this port, and the lobby's
frame-limiter setting is hidden on macOS.

The lobby settings provide separate display choices for the menu and game;
both start windowed. To change mouse capture, use **in-game Settings → Interface
→ Mouse Cursor → Lock Cursor to Window**. It starts disabled.

### Support

Feel free to email me at [ketchup@smkt.ca](mailto:ketchup@smkt.ca) for any questions or concerns. If you're experiencing something that clearly looks wrong, read the section below instead.

### Reporting problems

[Open an issue here](https://github.com/smallketchup82/ZkMacOS/issues), with your
Mac model, macOS version, app release, graphics preset, Retina mode, and steps
to reproduce the problem. Attach relevant logs after reviewing them for
personal information. Do not send port-specific bugs to the official Zero-K
issue tracker or ask the upstream developers to support this client.

## Build locally

### Developer requirements

Use an Apple Silicon Mac running macOS 26 or newer, Xcode/its command-line
tools, [Homebrew](https://brew.sh/), and Git. The build dependencies are listed
in [Brewfile](Brewfile), including the .NET SDK, Mono MSBuild, GCC, Mesa build
tools, and create-dmg. The legacy Mono build toolchain also needs Rosetta on
the build machine; the resulting app does not.

The helper uses the .NET SDK selected by [global.json](global.json). The engine
uses GCC 16. Renderer and Steamworks downloads are checksum-pinned in
[assets.lock.json](assets.lock.json), and fork revisions are pinned in
[sources.lock.json](sources.lock.json).

### Clone, build, and run

```sh
git clone https://github.com/smallketchup82/ZkMacOS.git
cd ZkMacOS
brew bundle
./scripts/build-app.sh
./scripts/run-app.sh
```

The build fetches the fork checkouts and dependency inputs, builds the renderer,
engine, AI and launcher, and packages **`dist/Zero-K.app`**. It also audits the
bundle's native architecture, library dependencies, and ad-hoc signatures.
Build logs are under `build/logs/`. Close the running app before replacing it
with a new build.

Engine builds are incremental: a source edit recompiles affected files and
relinks. Lobby, helper, defaults, and packaging changes do not require a clean
engine rebuild. When changing toolchain options, force CMake configuration with:

```sh
RECONFIGURE_ENGINE=1 ./scripts/build-app.sh
```

### Making changes and checking them

This repository holds the bootstrap, clean defaults, build scripts, packaging,
tests, patches, and version pins. The engine, lobby, and helper are separate
fork checkouts under the ignored `external/` directory. Edit the relevant fork
there, rebuild, and commit validated fork changes before updating the release
pins. Source preparation preserves local checkout changes.

```sh
luajit tests/check-settings.lua
luajit tests/check-display-sync.lua
luajit tests/check-trackpad-settings.lua
uv run --python python3 tests/check-cask.py
uv run --python python3 scripts/audit-app.py
uv run --python python3 scripts/smoke-app.py --seconds 90
uv run --python python3 scripts/smoke-download.py
```

The relocation smoke test rebuilds the app, runs a bounded AI skirmish from a
moved copy, and checks bundle writes and host dependencies. It uses existing
game/map downloads without bundling them, limits engine unified memory to
8 GiB, and writes results under `.local/relocation-test/`. The downloader test
uses a private profile under `.local/download-test/`.

For graphics changes, test water reflections and refraction at Medium and High
quality, all Retina modes, camera gestures, and window resizing. Keep test
profiles separate from your normal Application Support data. See
[engine updates](docs/ENGINE-UPDATES.md) before changing the engine version;
changing its reported version alone does not make a different simulation
compatible with Zero-K's servers.

Generated builds, downloads, external source checkouts, and private test data
are ignored by Git. Keep personal data and compiled applications out of source
commits. [Migration notes](docs/MIGRATION.md) describe the original port's layout
and where its changes now live.

## Package a release

### Automatic release from GitHub Actions

Open **Actions → Build and publish macOS release → Run workflow**, select
`main`, and click **Run workflow**. No version input or signing secrets are
needed. The workflow builds the pinned sources on an Apple Silicon macOS 26
runner, runs the settings checks and app audit, creates the styled DMG without
Finder automation, and publishes a GitHub release with the DMG, SHA256 checksum,
source locks, dependency inventory, and audit metadata. It then calls the
Homebrew cask workflow to update the tap.

CalVer is automatic: `YYYYMM.DD.PATCH` uses the date in **America/Toronto** when
the run starts. The first release of a day uses `.0`; later releases increment
the highest matching patch found across all releases and tags. Failed builds
do not consume a version. Release runs are serialized, and an existing release
is never replaced. The selected version is embedded in the app; the workflow
run number supplies its build number.

The workflow caches Homebrew downloads, checksum-verified source archives,
Python and NuGet packages, compiled Mesa libraries, and C/C++ compiler results.
Mesa and compiler caches account for native toolchain changes. App packaging,
auditing, and DMG creation run fresh. Build logs are uploaded even on failure.
The first run has cold caches and takes longer.

CI checks do not replace GPU playtesting, multiplayer synchronization testing,
or installation testing on another Mac. Review the workflow logs and keep the
known limitations in release notes current.

### Manual release from a local build

1. Commit and push the matching fork changes, then update `sources.lock.json`.
   Use clean checkouts matching those pins for a release.
2. Build and audit the app:

   ```sh
   ./scripts/build-app.sh
   uv run --python python3 scripts/audit-app.py
   ```

3. Run the settings and smoke tests above. Test installation from the DMG on
   another supported Mac without developer dependencies, and test multiplayer
   synchronization against the matching Windows/Linux engine. Record the
   hardware, macOS version, and known limitations with the release.
4. Create the DMG separately, in a logged-in macOS desktop session:

   ```sh
   ./scripts/build-dmg.sh
   ```

   Allow Finder automation if prompted. The script uses
   [create-dmg](https://github.com/create-dmg/create-dmg) to save the background,
   arrow, icon positions, and Applications shortcut. It produces:

   ```text
   dist/Zero-K-macOS-arm64.dmg
   dist/Zero-K-macOS-arm64.dmg.sha256
   ```

5. Create a CalVer release tag using `YYYYMM.DD.PATCH` (for example
   `202610.27.0`). Use a two-digit day, start the patch at `0`, and increment it
   for additional releases on the same day. Reset it to `0` on a new date.
   Attach both files to a **draft** GitHub release before publishing it.
   Publish it as a non-prerelease to update the Homebrew channel, with the
   matching source revisions, patches, build instructions, and third-party
   notices. The app
   should contain only static resources; never copy your Application Support
   profile into it. These builds use ad-hoc signing without a developer
   certificate or notarization.

The **Update Homebrew cask** workflow downloads the published DMG and checksum,
verifies them, generates `Casks/zkmacos.rb` with an exact versioned URL and
SHA256, and commits it to `main`. This repository doubles as the tap, so a
separate `homebrew-*` repository or cross-repository token is not required.
The cask requires Apple Silicon and macOS 26+, installs `Zero-K.app`, and leaves
Application Support data untouched during upgrades and uninstallations.

The automatic release workflow invokes this workflow directly because a
release published using GitHub's built-in Actions token does not trigger a
second workflow through the release event.

Drafts and prereleases do not update the cask. An older release cannot downgrade
it, and a changed binary under an existing version is rejected: publish a new
version instead. If publishing happened before both assets were attached,
upload the missing assets and run **Actions → Update Homebrew cask → Run
workflow**, supplying the release tag. You can also prepare the cask locally
with an authenticated GitHub CLI:

```sh
uv run --python python3 scripts/update-cask.py --tag 202610.27.0
```

GitHub Actions needs permission to write repository contents and push the cask
commit to `main`. If branch rules prevent that push, commit the generated cask
through your normal review process instead. The cask becomes available to
players after its commit reaches `main` and their tap is refreshed.

The inputs are version-pinned; byte-for-byte identical DMGs are not currently
claimed. See [distribution details](docs/DISTRIBUTION.md) for the trust process
and packaging constraints.

## AI disclosure

ZkMacOS's macOS port changes, build tooling, and documentation were developed
with substantial AI assistance using **OpenAI Codex**. AI-assisted code is not a
guarantee of correctness. Local tests and manual playtesting have been done,
but the port has not been thoroughly validated across hardware, long games,
and multiplayer conditions. The warning at the top applies to every build.

This disclosure concerns this port's changes; it does not attribute the
upstream Zero-K projects or their contributors' work to AI.

## Licensing and third-party projects

Unless a file states otherwise, all original ZkMacOS source code, scripts,
documentation, configuration defaults, and artwork are licensed under the
[GNU General Public License, version 2 or any later version](LICENSE)
(`GPL-2.0-or-later`), following Zero-K's GPL v2 licensing.

Upstream projects, libraries, assets, and ported files retain their own
copyrights and licenses. This includes the infrastructure launcher's GPL v3
license and the separate licenses of bundled dependencies; this grant does
not relicense third-party work. See
[third-party notices](docs/THIRD-PARTY.md). The app also carries notices under
`Zero-K.app/Contents/Resources/licenses/` and records native dependencies and
source revisions under `Contents/Resources/`.

### Forks used by this port

| Component | ZkMacOS fork | Upstream |
| --- | --- | --- |
| Recoil engine | [smallketchup82/RecoilEngine](https://github.com/smallketchup82/RecoilEngine), `macos/2026.07.04` | [RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine) |
| Chobby lobby and macOS game widgets | [smallketchup82/Chobby](https://github.com/smallketchup82/Chobby), `macos-port` | [ZeroK-RTS/Chobby](https://github.com/ZeroK-RTS/Chobby) |
| Launcher and native Steam helper | [smallketchup82/Zero-K-Infrastructure](https://github.com/smallketchup82/Zero-K-Infrastructure), `macos-port` | [ZeroK-RTS/Zero-K-Infrastructure](https://github.com/ZeroK-RTS/Zero-K-Infrastructure) |

The exact commits are in `sources.lock.json`. The central repository does not
vendor full copies of these projects.

### Other tooling and dependencies

- **Mesa, Zink, and KosmicKrisp:** the experimental GPU rendering stack;
  [Mesa upstream](https://gitlab.freedesktop.org/mesa/mesa).
- **CircuitAI and its dependencies:** the engine's bundled skirmish AI, with a
  version-specific Apple ARM64 patch in this repository.
- **Steamworks.NET and Valve's Steam API:** Steam integration;
  [Steamworks.NET](https://github.com/rlabrecque/Steamworks.NET). The binding's
  license and Valve's binary redistribution terms are separate.
- **.NET, Mono MSBuild, and managed dependencies:** the native helper's runtime
  and the shared launcher's build tools. Mono is a build dependency only.
- **SDL/sdl2-compat, OpenAL Soft, DevIL, FreeType, fontconfig, and FreeSans:**
  windowing/input, audio, image loading, and fonts, along with their dependencies.
- **GCC, CMake, Ninja, Meson, LLVM, libclc, Python/uv, Swift/AppKit, and Homebrew:**
  compilation, dependency preparation, native bootstrap, and packaging tools.
- **[create-dmg](https://github.com/create-dmg/create-dmg):** DMG creation and
  Finder layout. A build-local compatibility patch prevents Finder from
  resetting the layout on macOS 27; the installed tool is left unchanged.

Zero-K game content and maps are downloaded separately and retain their own
licenses. Preserve upstream attribution and include the corresponding source,
build instructions, and notices when redistributing a build.

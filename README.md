# ZkMacOS

Play [Zero-K](https://zero-k.info/) on Apple Silicon Macs with GPU acceleration,
native trackpad gestures, and crisp Retina text. ZkMacOS packages custom Recoil,
Chobby, and launcher builds into a self-contained `Zero-K.app` for **macOS 26
or newer**.

**[Download the DMG](https://github.com/smallketchup82/ZkMacOS/releases/latest)** ·
[Installation guide](https://github.com/smallketchup82/ZkMacOS/wiki/Installation) ·
[Wiki](https://github.com/smallketchup82/ZkMacOS/wiki)

# ⚠️ READ BEFORE PLAYING ⚠️ 
> 1. **DO NOT send ZkMacOS bug reports to the official Zero-K developers. [File issues in this repository](https://github.com/smallketchup82/ZkMacOS/issues) instead.**
> 2. **ZkMacOS is a third-party client. It is not endorsed by or officially supported by the Zero-K developers.**
> 3. **This port is built on experimental technology and has not been thoroughly tested. Bugs and breakage are to be expected. Understand that risk before putting Elo on the line in a ranked game. If you choose to play using ZkMacOS and your client crashes during a game, that is entirely your fault. You accept responsibility for the resulting loss or rating change.**

## What this adds to Zero-K

| Feature | What you get |
| --- | --- |
| Native Apple Silicon support | ARM64 engine, AI, and launcher helper. No Wine, Rosetta, Mono, or separately installed .NET runtime needed to play. |
| GPU acceleration on macOS | An experimental Mesa graphics stack runs the engine's OpenGL rendering through Zink and KosmicKrisp to Metal 4, rather than software rendering. |
| Trackpad camera controls | Two-finger pan, pinch zoom, Option + two-finger tilt, and optional three-finger tilt, with sensitivity and momentum settings. |
| Optional macOS HDR output | Preserves the game's existing bright lighting for HDR displays, with normal-brightness UI. Toggle it in Graphics settings. |
| Retina rendering modes | Choose standard resolution, crisp text and UI with a lower-resolution world, or full-resolution Retina rendering. |
| Native performance display | An FPS counter showing frame interval and the active Retina mode. |
| macOS application packaging | A drag-to-install DMG, a self-contained app with the Zero-K icon, and writable data kept in Application Support. |
| Native Steam login integration | A bundled ARM64 helper connects the lobby to your installed Steam client. Ordinary account login and offline play are also available. |
| macOS graphics and input fixes | Changes for water rendering, reflections, Retina sizing, window behavior, and trackpad input in the custom engine and lobby. |
| Optional MetalFX spatial upscaling | Upscales the world in Retina text and UI mode while keeping the UI at native resolution. |
| Optional GPU resource sharing | Shares Mesa textures with MetalFX/Metal presentation; falls back to CPU transfers when unavailable. |
| Experimental DisplayLink pacing | A live on/off graphics setting for display-driven frame pacing; off by default because a general improvement has not been established. |
| Optional notchful fullscreen | Covers the camera-housing area and adapts the resource bar to the active notch; ordinary fullscreen/windowed layouts remain available. |
| Native in-app updates | Sparkle verifies signed updates hosted on GitHub and defers installation until the game exits. |
| Configurable start announcements | Separate toggles for an all-chat ZkMacOS notice and a shared marker at your commander's spawn. |
| Optional macOS-port reporting | A Telemetry tab with automatic crash/error controls, optional attachments, manual bug reports and a restart-required master switch. Development builds never upload to Sentry. |

This keeps Zero-K's own Chobby lobby, multiplayer, spectating, downloads, and AI
skirmishes. Those are existing Zero-K features; this project makes them usable
through this macOS port. Multiplayer synchronization and long-session stability
still need broader testing. Connecting to a server is not proof of compatibility.
See [known issues](https://github.com/smallketchup82/ZkMacOS/wiki/Known-Issues) and the [validation backlog](https://github.com/smallketchup82/ZkMacOS/wiki/Development-Validation).

The list describes the current source. Older published releases may not include
every option. Optional rendering features do not guarantee higher FPS or lower
power use.

## Documentation

The [wiki](https://github.com/smallketchup82/ZkMacOS/wiki) contains the player
and developer guides. The DMG is the primary installation method; Homebrew is
an optional convenience covered below it in the installation guide.

| Playing Zero-K | Developing ZkMacOS |
| --- | --- |
| [Install the app](https://github.com/smallketchup82/ZkMacOS/wiki/Installation) | [Set up the development environment](https://github.com/smallketchup82/ZkMacOS/wiki/Development-Setup) |
| [Configure graphics, trackpad and game settings](https://github.com/smallketchup82/ZkMacOS/wiki/Configuration) | [Build and test a local app](https://github.com/smallketchup82/ZkMacOS/wiki/Development-Build-and-Test) |
| [Troubleshoot problems](https://github.com/smallketchup82/ZkMacOS/wiki/Troubleshooting) | [Create a release locally](https://github.com/smallketchup82/ZkMacOS/wiki/Development-Releases) |
| [Get help](https://github.com/smallketchup82/ZkMacOS/wiki/Getting-Help) | [Contribute code or documentation](https://github.com/smallketchup82/ZkMacOS/wiki/Contributing) |
| [Report a bug](https://github.com/smallketchup82/ZkMacOS/wiki/Reporting-Bugs) | [Update the engine version](https://github.com/smallketchup82/ZkMacOS/wiki/Development-Engine-Updates) |

## Privacy

The macOS port adds Sentry error and crash logging. **Automatic crash reporting
is enabled by default in release builds; automatic error reporting is off by
default.** Telemetry is used **only to fix bugs and crashes**.

You can customize reporting and optional attachments in **Settings → Telemetry**,
or fully disable it with **Disable All Telemetry** (requires restarting the app).
Local development builds never upload to Sentry. See the
[Telemetry guide](https://github.com/smallketchup82/ZkMacOS/wiki/Telemetry) for
collected data, attachment choices, and privacy details.

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
[third-party notices](docs/THIRD-PARTY.md) and [licensing/credits](https://github.com/smallketchup82/ZkMacOS/wiki/Licensing-and-Credits). The app also carries notices under
`Zero-K.app/Contents/Resources/licenses/` and records native dependencies and
source revisions under `Contents/Resources/`.

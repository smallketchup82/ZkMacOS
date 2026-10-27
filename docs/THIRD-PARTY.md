# Third-party software

This application is an unofficial macOS build of Zero-K. Copyright remains
with the respective authors. The application does not contain a player's
account, saved login, maps, game downloads, replays or logs.

Unless a file states otherwise, original ZkMacOS code, scripts, documentation,
configuration defaults, and artwork are licensed under the GNU General Public
License, version 2 or any later version (GPL-2.0-or-later). This follows the
Zero-K game repository's GPL v2 licensing. Upstream and third-party works
retain their existing licenses, including the infrastructure launcher's GPL v3;
the ZkMacOS license does not replace those terms.

The distribution includes Recoil and Chobby (GPL v2 or later), the Zero-K
launcher code (GPL v3), Mesa/Zink/KosmicKrisp (MIT and notices in the Mesa
source tree), SDL/sdl2-compat (zlib), FreeType (FTL/GPL), fontconfig (MIT),
OpenAL Soft (LGPL), DevIL (LGPL), GCC runtime libraries (GPL with the GCC
Runtime Library Exception), and their dependencies. Preserve each component's
copyright and license. Native dependency inventory and build revisions are
included alongside this file.

The ARM64 helper includes the .NET runtime, whose MIT license and third-party
notices are included from the self-contained publish output. Managed launcher
dependencies retain their original licenses; package notices are collected
from the restored NuGet artifacts during the build.

The Steamworks.NET binding is MIT licensed. The accompanying Steam API binary
is Valve's redistributable from the official Steamworks.NET release, thinned
and re-signed for this application;
Valve's rights and Steamworks terms are separate from the binding's license.
Steam is optional for ordinary Zero-K account/offline play and required for
Steam sign-in. No Steam client, account credentials or authentication tickets
are included in the application.

FreeSans font notices are included separately. Lobby art/music and AI scripts
retain the notices and attribution in their source repositories and assets.
Game content and maps are downloaded separately by the user.

Publish corresponding source and build instructions with a public release.
The exact fork revisions and dependency sources are listed in the lock files.
Do not publish a binary release without publishing the matching source,
patches and notices.

Upstreams:

- https://github.com/beyond-all-reason/RecoilEngine
- https://github.com/ZeroK-RTS/Chobby
- https://github.com/ZeroK-RTS/Zero-K-Infrastructure
- https://gitlab.freedesktop.org/mesa/mesa
- https://github.com/rlabrecque/Steamworks.NET/releases/tag/2025.164.1
- https://github.com/dotnet/runtime

# Migration from the portable experiment

The portable folder is not a build input. Its downloaded content and personal
settings are imported separately into `~/Library/Application Support/Zero-K`.
The migration script verifies copied files with SHA-256 and keeps conflicting
older settings under that directory's `migration-backup/` folder. Its detailed
report is private under `.local/`, never tracked or bundled.

| Previous change/data | Canonical destination |
| --- | --- |
| macOS ARM64 graphics integration | Recoil fork, July macOS branch |
| Grey selection panel fix | Chobby fork, `macos/game-data/LuaUI/ctrlpanel.txt` |
| Native trackpad events and camera controls | Recoil input/platform code |
| Trackpad settings widget | Chobby fork, `macos/game-data/LuaUI/Widgets` |
| Retina surfaces, UI fonts, viewports and pixel capture | Recoil renderer/font/Lua code |
| Native FPS counter | Recoil game UI code |
| CAS Full Retina capture | Chobby fork's macOS game widget resources |
| Lobby Retina dropdown and restart notice | Chobby graphics settings source |
| In-game Retina dropdown/restart notice | Chobby macOS game widget resources |
| Forced VSync and one Dock entry | Recoil macOS presenter/platform code |
| Steam login and explicit engine/resource/data paths | Infrastructure fork's ARM64 helper |
| CircuitAI Apple ARM64 calling convention fix | Version-specific central patch over the pinned submodule |
| Bundle construction, dependency relocation, icons and audits | Central `app/` and `scripts/` |
| Maps, game archives, packages, pool, missions and downloads | Application Support |
| Accounts, user keys/preferences, saves, replays and logs | Application Support, never the app |
| Software-rendering/Rosetta engine experiments and foreign executables | Superseded; excluded from build inputs |

The portable audit found no October source-code edits there; recent changes
were downloaded content and Finder metadata. The active macOS tweaks had been
made in the engine sources and isolated `native-data` directory. Their source
implementations are now in the projects listed above. Old AI configuration
and scripts are retained privately during migration; shipped AI profiles are
composed from the pinned public Chobby defaults and freshly built ARM64 AI.

`scripts/migrate-data.py` is an optional developer migration tool. The app never
reads a developer workspace or imports somebody else's data on a friend's
machine. First launch seeds only clean defaults shipped inside the bundle.

The original workspace's portable directory has been removed after verifying
19,129 portable data files, the packaged app and AI, and the absence of active
processes or Application Support symlinks depending on it. Old development
checkouts and metadata remain privately under `.local/legacy-workspace/`.

When importing a different portable install, delete its source directory only
after the migration report verifies and the packaged app works independently.

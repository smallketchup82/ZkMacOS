# Remaining validation and polish

The current target is Apple Silicon with macOS 26+ and Metal 4. The app is
built from version-pinned source and dependency inputs; byte-for-byte identical
DMGs are not currently claimed.

- Test a downloaded DMG on another Apple Silicon Mac with no developer tools,
  Mono, .NET or Homebrew installed, including the normal macOS trust process.
- Validate a full multiplayer match against the matching Windows/Linux engine;
  reporting the correct version and connecting are not synchronization proof.
- Test multiple displays, changing Retina density, menu bar/notch placement and
  cursor capture on more hardware. macOS fullscreen now avoids redundant window
  resizing and framebuffer readbacks when hiding/restoring the persistent Mesa
  context. Still validate repeated lobby/game transitions, Command-Tab, native
  titlebar fullscreen and display disconnection during a real match.
  Run `uv run --no-project --python python3 python tests/check-fullscreen.py`
  for transition/geometry regression checks; add `--native` for a short real
  SDL/Cocoa fullscreen and window restoration probe (opens a temporary window).
- Validate automatic notch-HUD switching on more MacBook models, external
  monitors and UI scales. The gap follows the active display's native camera
  boundaries. Native Spaces fullscreen, notch-covering fullscreen and windowed
  restoration have local probes; multi-display disconnection and full-match
  transitions still need broader testing. Run `luajit tests/check-notch-spacing.lua`
  and `luajit tests/check-notch-settings.lua` for layout/settings regressions.
  Native coverage probe: compile `tests/check-notch.mm` with the engine's Mac
  WindowManagerHelper, SDL2 and AppKit, then run with and without `custom`.
- Investigate intermittent missing Chili panel backgrounds after joining a
  multiplayer match. The owner requested deferring this while packaging proceeds.
- Optional graphics effects still need individual compatibility work, including
  geometry-shader selection, Xray glow, nightvision and a deferred widget's
  shutdown path. Do not advertise complete GL 4.6 feature support.
- Measure long-game memory, frame pacing and power use with shared GPU textures
  and the CPU compatibility path. GPU sharing still waits at API boundaries;
  investigate GPU event synchronization after validating the shared path.
- Revisit the legacy AnyCPU shared-library build so developers no longer need
  Mono MSBuild. The distributed ARM64 app already bundles its native .NET runtime.
- Keep upstream source/third-party notices and exact build pins current when
  updating the game-compatible engine branch or helper runtime.

# Remaining validation and polish

The current target is Apple Silicon with macOS 26+ and Metal 4. The app is
built from version-pinned source and dependency inputs; byte-for-byte identical
DMGs are not currently claimed.

- Test a downloaded DMG on another Apple Silicon Mac with no developer tools,
  Mono, .NET or Homebrew installed, including the normal macOS trust process.
- Validate a full multiplayer match against the matching Windows/Linux engine;
  reporting the correct version and connecting are not synchronization proof.
- Test multiple displays, changing Retina density, fullscreen, focus changes,
  menu bar/notch placement and cursor capture on more hardware.
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

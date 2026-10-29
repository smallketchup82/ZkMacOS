# MetalFX spatial upscaling

OpenAI Codex assisted with the MetalFX bridge, settings integration, packaging
patches and validation described here.

`MacMetalFXSpatial = 1` replaces the world-color bilinear blit in
`MacRetinaMode = 1` with Apple's `MTLFXSpatialScaler`. The world still renders
at logical window resolution, normally half the width and height of a Retina
framebuffer. Depth and stencil retain their existing nearest-neighbor blit;
UI draws afterward at backing resolution. The toggle is off by default, is
shared by lobby and game settings, and applies on the next world frame.

This does not reduce the world resolution further. Standard mode, Full Retina,
non-Retina displays, lobby screens and loading screens do not need this upscale.
Unsupported devices or scaler failures fall back to the existing bilinear
path and produce a `[MacMetalFX]` warning. Toggle off and on to retry a failure.
Changing Retina mode still requires a full app restart.

With `MacGPUSharing = 1`, the bundled Mesa build exposes a small,
versioned interface for the current GL read framebuffer. Zink returns its
Vulkan image and device; KosmicKrisp returns the underlying Metal texture and
device. These are borrowed handles, valid only while GL owns the allocation.
The interface accepts single-plane, non-multisampled 2D color resources with
one level and layer, and rejects other drivers and unsupported allocations.

MetalFX reads the world texture directly. KosmicKrisp currently allocates
shared heaps, while MetalFX requires a private output texture, so a GPU blit
copies the upscaled private output into GL's destination. GL then composites
the world and draws native-resolution UI. A small Metal presentation pass
samples the completed pbuffer directly. Zink's native Metal texture is already
oriented for presentation, unlike its CPU readback. Neither MetalFX integration
nor final presentation copies the frame through CPU memory on this path.
Screenshots and explicit GL readback
APIs still read pixels when requested.

GPU sharing is experimental and off by default. The bundled Mesa interface now
flushes GL and waits for CPU submission, then signals a Metal shared event on
KosmicKrisp's queue. The Metal consumer waits on that event and signals another
event before GL reuses the textures. These dependencies run on the GPU instead
of calling `glFinish` and waiting for each Metal command buffer on the CPU.
Resize, mode changes and resource destruction still drain outstanding work.
Older Mesa libraries without the event exports retain synchronous sharing.

Set `MacGPUSharing = 0` to force the compatibility path. Missing export entry
points, unsupported framebuffers, or Metal errors also fall back automatically.
The compatibility path reads the world into CPU memory, scales in MetalFX,
uploads the result back into GL, and uses the existing PBO presentation.
Toggle GPU sharing off/on to retry after a sharing failure. Switching back to
PBO presentation discards queued frames from before sharing was enabled.

The default PBO path now copies mapped pixels into three reusable Metal upload
textures and presents them directly. Each texture is reused only after its
previous GPU command completes. This avoids SDL's per-frame upload-buffer
allocation and buffer-to-texture GPU blit. The CPU copy from the mapped PBO is
still required. Pixel rows are inverted for presentation, while the shared GL
texture path retains its original orientation. Unsupported textures or Metal
errors fall back to the previous SDL upload path; resizing permits a retry.

The small Objective-C++ file compiles with Apple Clang and links only to system
AppKit/Metal/MetalFX/QuartzCore frameworks. It builds with `-O2` and the same macOS
26 minimum as the app. GCC still builds the engine and synchronized code.
Scalers and textures are reused until input/output dimensions change, and
resources are released with the GL context. The ordinary SDR input is display-referred
RGBA8, so MetalFX uses perceptual processing without an additional sRGB
conversion. The CPU compatibility readback stride is padded to 256 bytes.

Engine and lobby changes live in checksum-verified patches in `patches/` so
clean source checkouts receive them through `scripts/fetch-sources.py`.
`patches/mesa-gpu-sharing.patch` is checksum-pinned in `assets.lock.json` and
applied by `scripts/build-mesa.sh`. A build-input fingerprint prevents an old
unpatched Mesa installation from being silently reused. The release cache key
already includes the asset lock and Mesa build script.

[macOS HDR output](HDR.md) adds a floating-point world and composition path.
The existing MetalFX scaler preserves these float values when enabled; HDR
adds no separate world color-grading or bloom pass. GPU resource sharing now
has a live toggle in both the lobby Graphics and in-game Display settings.

## Automated checks

```sh
luajit tests/check-metalfx-settings.lua
luajit tests/check-display-sync.lua
luajit tests/check-settings.lua

xcrun clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=26.0 -DMAC_EGL_ZINK \
  -I external/recoil/rts tests/check-metalfx.mm \
  external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  -framework AppKit -framework Foundation -framework Metal -framework MetalFX -framework QuartzCore \
  -o /tmp/zk-check-metalfx
MTL_DEBUG_LAYER=1 /tmp/zk-check-metalfx

xcrun clang -mmacosx-version-min=26.0 -I external/recoil/rts/lib \
  -c external/recoil/rts/lib/glad/glad.c -o /tmp/zk-sharing-glad.o
xcrun clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=26.0 -DMAC_EGL_ZINK \
  -I external/recoil/rts -I external/recoil/rts/lib \
  -I build/mesa-work/mesa-26.3.0-rc1/include \
  tests/check-gpu-sharing.mm external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  /tmp/zk-sharing-glad.o -framework AppKit -framework Foundation -framework Metal \
  -framework MetalFX -framework QuartzCore \
  -Wl,-rpath,/opt/homebrew/opt/vulkan-loader/lib -o /tmp/zk-check-gpu-sharing
MTL_DEBUG_LAYER=1 /tmp/zk-check-gpu-sharing "$PWD/build/mesa"
```

The native test needs GPU access. It checks actual GPU output across odd and
even sizes, color preservation, orientation, row padding, resizing and resource
recreation. Lua checks cover platform gating, manual config precedence over a
stale lobby save, persistence, game/lobby synchronization, invalid messages,
and absence of a restart prompt when toggling MetalFX. The sharing test renders
its input in Mesa, scales using the exported textures, and validates the result
through GL across repeated writes and allocation recreation. The asynchronous
pass queues repeated overwrites without intermediate CPU readbacks. It also
checks reusable pixel uploads across odd widths and texture recreation. Its readbacks
exist only to assert the GPU output. It also checks export of the presentation
pbuffer and verifies orientation in the actual Metal presentation drawable.

For an isolated skirmish smoke test, copy `tests/widget_metalfx_probe.lua` to
that profile's `LuaUI/Widgets/`. It captures MetalFX-on and off screenshots,
toggles the feature, resizes the window to an odd logical size, captures another
screenshot, exercises GPU-sharing off/on, logs minimap geometry, and exits after
28 seconds of widget runtime. Do not install this probe into a normal playing
profile.

The local validation on 2026-10-27 passed the engine build, Lua settings checks,
native Metal API validation and app bundle audit (53 ARM64 binaries). Isolated
skirmishes passed in Standard, UI Retina and Full Retina modes. The UI Retina
run shared 1280×800 → 2560×1600 textures, toggled MetalFX, resized to
1023×701 → 2046×1402, switched through CPU staging, then resumed sharing at
1101×733 → 2202×1466. Each mode exited with status 0 and no sharing fallback
warning. Screenshots confirmed the minimap remained populated after resizing
and switching paths. The presentation shader has an orientation regression
check. The shared upscale deliberately avoids an unnecessary GL memory barrier
that caused the minimap to go black after resizing on this driver.

The UI pass now explicitly resets viewport and scissor bounds from logical
window geometry. Carrying the previous rendering viewport into Full Retina
could shrink and displace the HUD. Fullscreen screenshots were checked after
this correction in both Full Retina and shared MetalFX modes.

The game still logs existing shutdown errors from unsupported deferred-effect
widgets; this change does not address those effects. Physical mixed-display
testing and long-session stability and power measurements remain manual.

## Performance comparison

`tests/benchmark-metalfx.py` creates isolated profiles and runs six
configurations with the same fullscreen output, fixed camera, commander
selection and fresh game profiles using identical app defaults. Each run warms
up for 15 seconds and records rendered frame intervals for 30 seconds. Two
passes use opposite case order. The harness rejects unexpected UI viewport
bounds at the start or end of sampling. Screenshots are taken after sampling.
VSync remains enabled, as required by this port. The original four cases compare
CPU-transfer MetalFX, Full Retina, UI Retina and shared MetalFX. Two additional
cases test shared presentation without MetalFX in UI Retina and Full Retina.
Results include median, standard deviation, p95, p99, maximum frame interval
and the percentage over 16.67 ms. These are rendered frame intervals; actual
display cadence needs a Metal trace.

```sh
uv run tests/benchmark-metalfx.py --app /path/to/Zero-K.app \
  --content /path/to/profile-with-maps-and-games \
  --output build/benchmarks/metalfx --repeats 2
```

Use a new output directory for each invocation. Raw per-frame CSV files, logs,
screenshots and a JSON summary remain there. Average FPS is total rendered
intervals divided by their total duration. This static skirmish measures the
rendering paths; it does not predict FPS in a large battle. Avoid other GPU
workloads while collecting measurements.

### Earlier local results: 2026-10-27

Apple M3, 8 CPU cores, 16 GiB RAM. All cases used a 3024×1898 fullscreen backing
framebuffer and 1512×949 logical coordinates, VSync enabled on the built-in
120 Hz display, Fairyland 1.31, Zero-K v1.14.10.3 and one selected commander.
The TA camera stayed at map center, height 2500, angle 0.6 and FOV 45. These
were fresh game profiles with the app's defaults, launched directly into the
skirmish. No lobby graphics preset was applied. Metal API validation was
disabled during measurement.

Each case has two 30-second samples after its own 15-second warm-up. Settings
below are `MacRetinaMode / MacMetalFXSpatial / MacGPUSharing`. The first three
cases use CPU presentation; the sharing case also uses direct Metal presentation.

| Configuration | Settings | Average FPS | FPS in each pass | Mean frame time | 95th percentile |
| --- | --- | ---: | --- | ---: | ---: |
| MetalFX, CPU transfers | 1 / 1 / 0 | 62.1 | 59.8, 64.4 | 16.10 ms | 20.64 ms |
| Full Retina | 2 / 0 / 0 | 90.3 | 89.2, 91.4 | 11.07 ms | 15.27 ms |
| UI-only Retina, MetalFX off | 1 / 0 / 0 | 114.7 | 116.7, 112.7 | 8.72 ms | 13.20 ms |
| MetalFX, GPU sharing | 1 / 1 / 1 | 76.6 | 76.3, 76.9 | 13.06 ms | 18.34 ms |

The shared path removed CPU staging copies and averaged about 23% higher FPS
than CPU-transfer MetalFX in this scene. It was still about 15% slower than
Full Retina. The measured build retained `glFinish` and Metal command
completion waits. GPU sharing remains experimental and opt-in. These numbers
measure this static rendering workload; they do not predict large-battle FPS
or establish power savings.

Both sample boundaries passed the UI viewport check in all eight retained runs.
Completed-frame screenshots confirmed HUD placement and a populated minimap
in each configuration. The sequence with the broken Full Retina UI was discarded.
The first pair of sharing samples was also excluded after one capture showed a
different commander selection state. Both sharing samples were repeated with
selection enforced and verified unchanged throughout sampling; the six baseline
captures retained their expected selection. The repeat used a rebuild whose
only engine change was making GPU sharing opt-in. Every case explicitly sets
that option. These are indicative local measurements, not a controlled lab test.

The consolidated results and measured engine checksums are recorded locally in
`build/benchmarks/metalfx-2026-10-27-report/summary.json`. Its run entries point to
the raw CSV, logs and screenshots. Original data is preserved in the `-final`
and `-sharing-selection` profile directories. `tests/benchmark-metalfx.py` now
enforces commander selection in every case; `--case` can repeat one configuration.

### Presentation and pacing follow-up: 2026-10-27

The same M3 and static scene were used to check GPU events and reusable uploads.
The default remains UI Retina, MetalFX off and GPU sharing off. A fresh,
unprofiled original sample averaged 111.7 FPS; two reusable-upload samples
averaged 111.8 FPS. This change does not establish an average rendered-FPS gain.
Rendered p95/p99 intervals were 13.68/15.67 ms before and 14.47/16.91 ms after.
Rendering-loop intervals alone therefore do not establish smoother display output.
The first exploratory baseline sample overlapped tracing and was excluded from
this comparison.

Actual display intervals were then collected with eight-second Metal System
Trace captures after the scene warmed up. The comparison was repeated in
reverse order. The first second and final half-second of each displayed-frame
sequence were excluded. Both runs used the same Mesa libraries; the original
app used the saved original engine. Instruments adds overhead, so these
displayed-FPS values must not be compared with the unprofiled FPS above.

| Capture | Original SDL upload | Reusable Metal upload |
| --- | ---: | ---: |
| Pass 1: displayed FPS | 93.0 | 98.7 |
| Pass 1: display-interval standard deviation | 4.11 ms | 3.46 ms |
| Pass 1: median present-request-to-display latency | 10.72 ms | 8.48 ms |
| Pass 1: p95 present-request-to-display latency | 34.17 ms | 12.94 ms |
| Reverse pass: displayed FPS | 87.1 | 93.9 |
| Reverse pass: display-interval standard deviation | 4.19 ms | 3.85 ms |
| Reverse pass: median present-request-to-display latency | 10.66 ms | 8.93 ms |
| Reverse pass: p95 present-request-to-display latency | 16.58 ms | 13.62 ms |

These traces support retaining reusable uploads, but are short instrumented
samples. They measure presentation latency, not end-to-end input latency, and
do not establish sustained performance, power savings or large-battle behavior.
The presentation's visible p95 interval remained about 16.67 ms.

Shared MetalFX with GPU events averaged 89.6 FPS versus the earlier synchronous
shared result of 76.6 FPS. Its p95 improved from 18.34 to 17.62 ms, while p99
worsened from 19.23 to 21.58 ms. Shared UI Retina without MetalFX averaged
101.1 FPS. GPU sharing therefore remains experimental and off by default.
One preliminary synchronous-sharing sample changed selection and was rejected.
The GPU-event performance samples preceded the reusable-upload implementation.

Use `--require-reusable-uploads` to reject a benchmark run that falls back to
SDL, or `--require-gpu-events` to require the new shared synchronization path.
The new `--case ui_retina_shared` and `--case full_retina_shared` cases isolate
presentation from MetalFX. Per-frame CSV, screenshots, trace exports and engine
hashes are retained locally; the combined report is
`build/benchmarks/frame-pacing-report-2026-10-27/summary.json`. Display captures
are in the `frame-pacing-display-2026-10-27` and `frame-pacing-display-repeat-2026-10-27`
directories. The final build adds only an upload-slot error check, a named ring
size and header-comment cleanup relative to the measured presentation build.

The final app passed the bundle audit, Lua display/settings checks, fullscreen
regressions and native GPU tests with Metal API validation. Isolated live probes
passed in Standard, UI Retina and Full Retina, toggling MetalFX and GPU sharing,
switching through reusable PBO uploads, resizing twice and exiting with status 0.
Screenshots retained populated minimaps and the expected UI viewport. Existing
unsupported-effect shader and deferred-widget shutdown messages remain.

### Experimental CAMetalDisplayLink: 2026-10-27

`MacDisplayLink = 1` enables a display-driven wait before SDL polls input and
the engine updates and renders. It is off by default: the initial measurements
below did not establish a pacing improvement. This does not move simulation or
rendering to another thread, and does not change recorded simulation commands.

The link belongs to the presenter's `CAMetalLayer`. Its delegate supplies the
drawable; presentation does not also call `nextDrawable` while the link is active.
It requests the current display's refresh rate and a two-frame latency budget.
Callbacks during input polling are discarded while a frame is in progress, so
SDL's nested run loop cannot consume the drawable pool. The explicit frame wait
wakes on a callback and times out after 50 ms if the window is occluded. Hidden
and minimized windows pause the link. Disabling the setting or destroying the
context invalidates it and restores the existing presentation path.

The leading explanation for the regression is additional waiting before the
engine's serial simulation/render work, followed by the existing transfer and
synchronization costs. A display-link update has a CPU presentation deadline;
it does not make that work cheaper. CPU/GPU timeline captures are still needed
to distinguish missed deadlines from other scheduling effects. See Apple's
[CAMetalDisplayLink documentation](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)
and [update deadline](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink/update/targettimestamp).

Initial single-pass measurements on the same M3, UI Retina at 3024 x 1898,
MetalFX off and GPU sharing off:

| Scene | Existing presenter FPS | DisplayLink FPS | Existing p95 / p99 | DisplayLink p95 / p99 |
| --- | ---: | ---: | ---: | ---: |
| Static Fairyland scene | 105.2 | 100.8 | 15.50 / 17.49 ms | 17.23 / 18.13 ms |
| Normal long game, battle 2531374 | 63.5 | 58.6 | 27.04 / 30.26 ms | 27.84 / 30.88 ms |
| Stress replay, battle 2531656 | 36.4 | 36.6 | 37.94 / 45.86 ms | 38.96 / 43.73 ms |

These are rendered frame intervals from 30-second samples after 15 seconds of
warm-up, using fresh isolated Mesa caches. They do not measure displayed frame
intervals or end-to-end input latency. The normal replay starts at ten minutes;
the samples cover roughly 611-641 seconds and 612-628 units. Results are local
and preliminary, with no sustained-performance or power claim. The final build
changes the default to off and resets the requested rate if SDL cannot report
a display refresh rate; these branches were not exercised by the measured runs.
The stress samples cover roughly 1211-1240 game seconds and 599-625 units.
This heavier rendering scene does not establish the replay's peak unit count.
Its small throughput difference and mixed tails do not establish a pacing win.
Raw data is in `build/benchmarks/display-link-light-final-{off,on}`,
`build/benchmarks/display-link-normal-{off,on}` and
`build/benchmarks/display-link-stress-{off,on}`. The combined report is
`build/benchmarks/display-link-report-2026-10-27/summary.json`.

The replay harness requests `forcestart` on its local replay server, then `skip`
as soon as LuaUI initializes. It retries during pregame and starts the warm-up
only after reaching the selected game time. Fast-forwarding still has to execute
the recorded simulation. DisplayLink is temporarily disabled during fast-forward
in both cases, then restored before warm-up. Incidental selection and keyboard
input are intercepted to keep the scene stable.
The final stress run began skipping at pregame frame -1, about six seconds after
LuaUI initialized; it reached frame 36000 before starting the warm-up.

For example, compare the same replay with `--display-link 0` and `1`, using a
different output directory for each run:

```sh
uv run --python python3 python tests/benchmark-metalfx.py \
  --app dist/Zero-K.app --content "$HOME/Library/Application Support/Zero-K" \
  --output build/benchmarks/replay-display-link-off --case ui_retina --repeats 1 \
  --replay /absolute/path/to/replay.sdfz --replay-start 600 \
  --display-link 0 --require-reusable-uploads
```

Use `--extra-maps /path/to/maps` when a benchmark map is outside the normal game
profile. Each run logs its sampled simulation frames, unit counts, engine hash
and replay hash. Battle 2531656 at twenty minutes is an extreme unit-count stress
test, separate from the normal long-game benchmark.

The native lifecycle probe exercises callbacks, hidden-window waits, resize,
disable and recreation. Run it with Metal API validation:

```sh
xcrun clang++ -std=c++17 -O2 -fobjc-arc -mmacosx-version-min=26.0 \
  -DMAC_EGL_ZINK -I external/recoil/rts tests/check-display-link.mm \
  external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  -framework AppKit -framework Metal -framework MetalFX -framework QuartzCore \
  -o build/check-display-link
MTL_DEBUG_LAYER=1 build/check-display-link
```

For a manual check, enable `MacDisplayLink` in an offline game, confirm its log
entry, then minimize, restore, resize and switch fullscreen. Disable it and
confirm rendering continues. Move the window between displays with different
refresh rates when that hardware is available. Compare visible pacing and input
response with both settings; a successful lifecycle probe alone is not evidence
of improved performance.

The earlier local validation run passed its bundle audit, source patch verification, display/settings
Lua checks and fullscreen regressions. The native probe passed with Metal API
validation, including the unknown-refresh-rate branch. An isolated UI Retina
game with DisplayLink enabled also passed MetalFX/GPU-sharing toggles and two
resizes with API validation, reusable uploads active and no presentation fallback.
Its logs and screenshots are in `build/display-link-live-final`. External-display
transitions and actual displayed-frame timing remain unverified for DisplayLink.

## Manual validation

1. Build with `scripts/build-app.sh`. Launch an offline skirmish on a Retina
   display in Retina text and UI mode.
2. Enable MetalFX in the in-game Display menu. Check for a `[MacMetalFX] spatial
   upscale` log entry with the expected logical and backing sizes. Compare
   world edges, colors and orientation; confirm UI and text remain sharp.
3. Toggle off and on while playing. Resize the window and switch fullscreen;
   check that the world fills the viewport and UI clipping remains correct.
4. Return to the lobby. Confirm the Graphics toggle matches the game setting.
   Restart with the opposite `MacMetalFXSpatial` value in `springsettings.cfg`
   and confirm the lobby honors it.
5. Repeat in Standard and Full Retina modes. MetalFX should be bypassed.
   Check non-Retina and mixed-density displays when hardware is available.
6. Compare frame intervals with the MetalFX toggle off and on, and with
   `MacGPUSharing` set to 0/1. Check for shared-texture scaling and presentation
   log entries, and verify that switching to the compatibility path does not
   briefly show an old frame. Measure on the hardware you intend to use.

API reference: [Apple's MetalFX spatial scaler](https://developer.apple.com/documentation/metalfx/mtlfxspatialscaler).

### Experimental DisplayLink frame pacing

DisplayLink is available in the lobby graphics settings and in-game under
Settings / Graphics / Display. It defaults to off (`MacDisplayLink = 0`) and
applies immediately. It works with shared GPU textures, HDR output, and the
reusable Metal upload path. SDL upload remains the fallback if Metal presentation
fails.

Initial measurements regressed, so this remains an opt-in experiment. The
GPU-event synchronization and reusable Metal uploads are integrated alongside
HDR color handling and the SDL compatibility fallback.

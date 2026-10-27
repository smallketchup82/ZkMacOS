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

GPU sharing is experimental and off by default. The initial synchronization
is conservative: GL finishes before Metal accesses
its textures, and Metal command completion is awaited before GL reuses them.
This avoids resource races without changing the Vulkan driver's queue model.
It removes CPU staging transfers but retains CPU/GPU waits. The local benchmark
below improved on CPU-transfer MetalFX, but remained slower than Full Retina.
Moving these waits to GPU events is separate work.

Set `MacGPUSharing = 0` to force the compatibility path. Missing export entry
points, unsupported framebuffers, or Metal errors also fall back automatically.
The compatibility path reads the world into CPU memory, scales in MetalFX,
uploads the result back into GL, and uses the existing PBO presentation.
Toggle GPU sharing off/on to retry after a sharing failure. Switching back to
PBO presentation discards queued frames from before sharing was enabled.

The small Objective-C++ file compiles with Apple Clang and links only to system
Metal/MetalFX/QuartzCore frameworks. GCC still builds the engine and synchronized code.
Scalers and textures are reused until input/output dimensions change, and
resources are released with the GL context. The input is display-referred
RGBA8, so MetalFX uses perceptual processing without an additional sRGB
conversion. The CPU compatibility readback stride is padded to 256 bytes.

Engine and lobby changes live in checksum-verified patches in `patches/` so
clean source checkouts receive them through `scripts/fetch-sources.py`.
`patches/mesa-gpu-sharing.patch` is checksum-pinned in `assets.lock.json` and
applied by `scripts/build-mesa.sh`. A build-input fingerprint prevents an old
unpatched Mesa installation from being silently reused. The release cache key
already includes the asset lock and Mesa build script.

## Automated checks

```sh
luajit tests/check-metalfx-settings.lua
luajit tests/check-display-sync.lua
luajit tests/check-settings.lua

xcrun clang++ -std=c++17 -fobjc-arc -DMAC_EGL_ZINK \
  -I external/recoil/rts tests/check-metalfx.mm \
  external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  -framework Foundation -framework Metal -framework MetalFX -framework QuartzCore \
  -o /tmp/zk-check-metalfx
MTL_DEBUG_LAYER=1 /tmp/zk-check-metalfx

xcrun clang -I external/recoil/rts/lib \
  -c external/recoil/rts/lib/glad/glad.c -o /tmp/zk-sharing-glad.o
xcrun clang++ -std=c++17 -fobjc-arc -DMAC_EGL_ZINK \
  -I external/recoil/rts -I external/recoil/rts/lib \
  -I build/mesa-work/mesa-26.3.0-rc1/include \
  tests/check-gpu-sharing.mm external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  /tmp/zk-sharing-glad.o -framework Foundation -framework Metal \
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
through GL across repeated writes and allocation recreation. Its readbacks
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

`tests/benchmark-metalfx.py` creates isolated profiles and runs the four requested
configurations with the same fullscreen output, fixed camera, commander
selection and fresh game profiles using identical app defaults. Each run warms
up for 15 seconds and records rendered frame intervals for 30 seconds. Two
passes use opposite case order. The harness rejects unexpected UI viewport
bounds at the start or end of sampling. Screenshots are taken after sampling.
VSync remains enabled, as required by this port. The first three
configurations force `MacGPUSharing = 0` to represent the original CPU transfer
path; the fourth enables shared MetalFX and direct Metal presentation.

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

### Local results: 2026-10-27

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
Full Retina. This implementation retains `glFinish` and Metal command
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

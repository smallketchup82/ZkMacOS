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

The Mesa GL framebuffer cannot currently be passed directly to MetalFX. The
world is read into CPU memory, uploaded to a shared Metal texture, scaled into
a private Metal texture, copied to a shared buffer, then uploaded back to GL
before UI drawing. That synchronous transfer can reduce performance. Treat
this as an optional image-quality setting; no FPS improvement is claimed.
The existing final-frame presentation readback also remains.

The small Objective-C++ file compiles with Apple Clang and links only to system
Metal/MetalFX frameworks. GCC still builds the engine and synchronized code.
Scalers and textures are reused until input/output dimensions change, and
resources are released with the GL context. The input is display-referred
RGBA8, so MetalFX uses perceptual processing without an additional sRGB
conversion. The readback stride is padded to 256 bytes.

Engine and lobby changes live in checksum-verified patches in `patches/` so
clean source checkouts receive them through `scripts/fetch-sources.py`.

## Automated checks

```sh
luajit tests/check-metalfx-settings.lua
luajit tests/check-display-sync.lua
luajit tests/check-settings.lua

xcrun clang++ -std=c++17 -fobjc-arc -DMAC_EGL_ZINK \
  -I external/recoil/rts tests/check-metalfx.mm \
  external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  -framework Foundation -framework Metal -framework MetalFX \
  -o /tmp/zk-check-metalfx
MTL_DEBUG_LAYER=1 /tmp/zk-check-metalfx
```

The native test needs GPU access. It checks actual GPU output across odd and
even sizes, color preservation, orientation, row padding, resizing and resource
recreation. Lua checks cover platform gating, manual config precedence over a
stale lobby save, persistence, game/lobby synchronization, invalid messages,
and absence of a restart prompt when toggling MetalFX.

For an isolated skirmish smoke test, copy `tests/widget_metalfx_probe.lua` to
that profile's `LuaUI/Widgets/`. It captures MetalFX-on and off screenshots,
toggles the feature, resizes the window to an odd logical size, captures another
screenshot, and exits after 20 seconds of widget runtime. Do not install this
probe into a normal playing profile.

The local validation run on 2026-10-27 passed the engine build, Lua settings
checks, native Metal API validation and app bundle audit. An isolated skirmish
upscaled 1488×813 to 2976×1626, toggled off/on, then recreated the scaler at
1023×701 → 2046×1402 and 1441×766 → 2882×1532. It captured three screenshots,
logged no MetalFX fallback warning, and exited with status 0. The game still
logged existing shutdown errors from unsupported deferred-effect widgets;
this change does not address those effects. Physical mixed-display testing,
fullscreen testing and long-session performance measurements remain manual.

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
6. Compare frame intervals with the toggle off and on. The extra transfers can
   cost more than the scaler itself; measure on the hardware you intend to use.

API reference: [Apple's MetalFX spatial scaler](https://developer.apple.com/documentation/metalfx/mtlfxspatialscaler).

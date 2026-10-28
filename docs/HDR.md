# macOS HDR display output

OpenAI Codex assisted with the macOS HDR output implementation, settings and tests.

Enable **macOS HDR display output** in the lobby's **Graphics** settings or
**Settings → Graphics → Display** in game. It is off by default, applies
immediately, and works in all three Retina modes. The engine setting is
`MacHDR = 1`; use `0` for SDR output.

This option preserves the game's existing lighting for an HDR display. It adds
no color grading, saturation boost, highlight expansion or bloom. Ordinary
scene values and opaque UI white keep their existing levels. Values above SDR
white produced by the game can use the display's extra brightness. Effects
that already clamp their own brightness cannot recover lost detail.

## Existing game lighting

Zero-K's **Graphics → HDR (experimental)** menu belongs to its legacy deferred
lighting widget. That widget accumulates point and beam lights in an RGB32F
buffer and provides its own bloom. Recent Zero-K versions also have a GL4
lighting renderer which supersedes that legacy widget when available. The
macOS output path accepts the resulting world image from either renderer.
It does not add or replace weapon-light definitions.

Deferred lighting requires `AllowDeferredMapRendering = 1` and
`AllowDeferredModelRendering = 1` before the game loads. The lobby's normal
Compatibility Mode Off/On profiles enable these buffers; Extreme disables
them. Changing these engine prerequisites requires starting another game.
The macOS output toggle itself remains live. Lighting and bloom choices
belong to the game's renderer and are independent of the output toggle.

The initial direct-to-skirmish tests used engine defaults without these
buffers enabled. Later isolated tests enabled both buffers and confirmed that
the game's GL4 lighting initialized. A short local weapon test completed, but
sampling that particular region did not establish above-SDR weapon peaks.
Actual weapon appearance and brightness still need gameplay evaluation.

## Output and performance

The macOS bridge renders the world to RGBA16F. It resolves to an RGBA16F UI
composition target without changing its colors. With MetalFX off, this is a
GL floating-point blit: there is no extra Metal world-effects pass or bloom
allocation. With MetalFX on in Retina text and UI mode, the existing spatial
scaler resolves the float world while preserving superwhite values. A scaler
failure falls back to floating-point bilinear scaling.

Existing GL UI draws over the resolved world. A final Metal pass decodes the
completed display-referred frame into extended linear sRGB and compresses only
superwhite peaks to current display headroom, preserving linear RGB ratios.
The CAMetalLayer uses RGBA16Float and EDR. Disabling HDR restores the original
SDR layer format and color space. Loading screens and the lobby use SDR.

This is native HDR output for a legacy renderer, not a conversion of all game
lighting and materials to a physically based, scene-linear pipeline. The game
continues to define light colors, brightness and effects.

HDR requires macOS EDR support and shared Mesa textures. Unsupported displays
or presentation failures use SDR and log the reason. Toggle HDR off/on to
retry a presentation failure. Available brightness is read each frame; logs
report `[MacHDR] display brightness headroom …x SDR white`. A value of `1.00x`
means no extra brightness is currently available. Physical display brightness
and power conditions can change this headroom.

**GPU resource sharing** is a separate live toggle in both Display/Graphics
menus, backed by `MacGPUSharing`. It enables shared textures for ordinary
MetalFX and SDR presentation. HDR always uses sharing even when that switch
is off. Unsupported ordinary sharing falls back to CPU transfers. Both paths
retain synchronization waits; no speedup is promised.

The completed float frame remains readable by game effects and screenshots.
PNG screenshots clamp superwhite values and cannot show the display's peak
HDR brightness. The engine handles the opposite native orientations of the
pbuffer and offscreen framebuffer. GL initializes shared composition textures
before Metal writes them, preventing their first UI draw from discarding
external writes.

Apple reference: [EDR tone mapping](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping).

## Checks

```sh
luajit tests/check-hdr-settings.lua
luajit tests/check-gpu-sharing-settings.lua
luajit tests/check-metalfx-settings.lua
luajit tests/check-display-sync.lua

xcrun clang++ -std=c++17 -fobjc-arc -DMAC_EGL_ZINK \
  -I external/recoil/rts tests/check-hdr.mm \
  external/recoil/rts/Rendering/GL/MacMetalFX.mm \
  -framework AppKit -framework Metal -framework MetalFX -framework QuartzCore \
  -o /tmp/zk-check-hdr
MTL_DEBUG_LAYER=1 /tmp/zk-check-hdr
```

The native check verifies unchanged SDR colors, unexpanded SDR white,
preserved original superwhite values, UI white, changing headroom, float
MetalFX scaling, resizing and SDR restoration. The extended GPU-sharing test
in [METALFX.md](METALFX.md) verifies actual GL float resolves and SDR/HDR
presentation orientation with an asymmetric image.

The revised engine compiled and linked on an Apple M3 on 2026-10-27. Native
GPU tests, settings checks and the 60-binary ARM64 bundle audit passed.
Earlier isolated tests exercised toggling and resizing in all Retina modes;
the revised path also initialized actual GL4 game lighting. Long battles and
physical mixed-display testing remain unverified.

`tests/widget_hdr_probe.lua` is only for isolated profiles. It exercises HDR,
MetalFX, screen copies and resizing, takes screenshots and exits. It draws no
visible test overlay and is not packaged in the playable client.

## Map-edge opacity regression

HDR retains legacy vertex-color clamping while allowing fragment-shader RGB
and additive accumulation above SDR white. The old map-edge extension writes
fade alpha outside 0–1 to `gl_FrontColor`; disabling vertex clamping caused its
grid to blend into black. Keeping the legacy clamp restores its SDR opacity
behavior without clamping HDR fragment colors.

`tests/check-gpu-sharing.mm` exercises both clamping states with a vertex-only
shader and checks that a fragment shader can still output RGB 2.0 with the fix.
`tests/widget_hdr_map_edge_probe.lua` explicitly selects the game's grid
exterior, fixes the camera at the right map edge, captures SDR and HDR, and
exits. Run it only in an isolated profile. On 2026-10-27, All That Glitters v1.2
in Full Retina reproduced the broken grid with the old build and showed the
complete grid in HDR with the fix. The engine recompiled and linked, and the
native GPU regression test passed with Metal API validation.

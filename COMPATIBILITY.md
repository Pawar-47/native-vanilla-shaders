# Compatibility

## Minecraft

| | |
|---|---|
| Supported | **Minecraft Java Edition 26.3** only |
| Declared format | `min_format: 97`, `max_format: 97` in `pack.mcmeta` |
| Not supported | 26.2 and earlier, 26.4 snapshots |

The version is pinned for real reasons, not caution:

- **26.3 reordered the `Globals` and `DynamicTransforms` uniform blocks.** A
  hand-written copy of either from an earlier version silently reads the wrong
  values. The pack includes the vanilla `.glsl` files for both rather than
  declaring them, so it follows the layout wherever it goes — but the pipelines
  and defines it targets are 26.3's.
- **`#moj_import` was removed in 26.3** and replaced by `#include` with a
  namespace.
- **Every varying needs a `layout(location)`** since 26.3, and both sides of a
  link must agree on the base type and the `flat` qualifier.
- **26.3 renamed programs**: `rendertype_clouds` became `clouds` and
  `rendertype_world_border` became `world_border`. `post/transparency.fsh` was
  removed. The pack relies on the new names.
- **The 26.4 snapshots rename the game's full-screen vertex program.** The pack
  ships its own in `assets/nvs/shaders/post/fullscreen.vsh` precisely so this
  cannot break it.

## Graphics backends

The pack uses only what 26.3 itself uses: SPIR-V-compiled GLSL 330 with explicit
locations, std140 uniform blocks, and the restricted set of sampler types
(`sampler2D`, `isamplerBuffer`). Both of the game's backends should accept every
file:

- **OpenGL** — the game translates the SPIR-V back to GLSL 330 through
  SPIRV-Cross before handing it to the driver. The pack avoids constructs that
  survive that round trip poorly: no plain uniforms, no `layout(component)`, no 1D
  or 3D samplers, and no dynamic indexing of anything except the vanilla arrays
  that vanilla itself indexes that way.
- **Vulkan** — the SPIR-V is used directly.

The one place where the backends could differ in *appearance* rather than
correctness is the `flat` varying in `sky.vsh` and `position_tex.vsh`. Both are
written so that every vertex of a primitive carries the same value, which is the
condition under which `flat` is specified to be dependable. `FLAT` varyings in
`clouds.vsh` (`nvsCloudUp`) are per-face constants for the same reason.

## Hardware

Tuned by default for an **Intel HD Graphics 5500 / i3-5005U** class machine: 24
execution units, no dedicated VRAM, DDR3 shared with the CPU, two cores.

What that decided:

- **No ray marching anywhere.** The sky is analytic; there is no scattering
  integral per pixel.
- **No screen-space reflections or shadows.** Both cost a full-resolution pass
  plus the data bus.
- **The bloom target is fixed at 480×270.** Its cost does not grow with the
  window size.
- **No water geometry displacement.** It would cost vertices and break glass.
- **Three post passes at most**, and the whole chain can be removed by deleting
  one JSON file.
- **The heaviest per-pixel cost is deliberately bounded**: the cloud field is 4+3
  octaves, the cloud shadow 3, the wave normal 3 sines plus 3 noise lookups.

On faster hardware, raise `NVS_CLOUD_OCTAVES`, `NVS_NEBULA_OCTAVES`,
`NVS_POST_BLOOM` and `NVS_SKY_HAZE_POWER`'s companions in
[config.glsl](assets/nvs/shaders/include/config.glsl); nothing else needs to
change to spend the extra headroom.

## Graphics settings that matter

| Setting | Effect |
|---|---|
| **Graphics: Fancy** | Required for the cloud volume and translucent terrain pass. Use Fancy, not Fabulous, for the complete above-water screen-space water effect. |
| **Clouds: Fancy** | As above. The pack works with Fast clouds but has less to work with. |
| **Improved Transparency** | The native OIT branches and cloud discard parity are preserved, but above-water water markers are written only in the non-OIT colour pass. Turn Improved Transparency off for reliable water SSR/refraction; with it on, other transparent geometry retains the OIT path but water effects may fall back. |
| **Render distance** | Unchanged. The pack does not alter fog distances, only the curve between them. |
| **Brightness / gamma** | Still works: `LightmapInfo.BrightnessFactor` still drives the blend, at 85% of vanilla's strength so the image is less washed out. Set `NVS_GAMMA_STRENGTH 1.0` for vanilla's response. |
| **Fullscreen vs windowed** | Irrelevant; nothing in the pack depends on resolution except the dither, which is per-pixel. |

## Mods

| Mod | Status |
|---|---|
| **Iris / OptiFine / Oculus** | Not used and not compatible. Do not enable a shaderpack alongside this. |
| **Sodium** | **Not supported by this pack.** Sodium replaces the terrain, cloud and sky programs with its own and ships its own `assets/sodium/shaders/` set. Overriding those would need Sodium's exact shader source for 26.3, which could not be verified while building this. With Sodium installed, expect the sky, lighting, fog and post-processing to keep working and the **water, cloud detail and cloud shadows to be absent**, because terrain and clouds are drawn by Sodium's shaders. If that matters to you, run without Sodium. |
| **Any mod that replaces core shaders** (some performance and rendering mods do) | Last one wins, and the pack's changes to that program are lost. If a mod replaces `terrain.fsh` or `sky.fsh`, the corresponding feature disappears rather than erroring. |
| **Datapacks that change the clock, weather or dimensions** | Fully compatible, by design: the pack reads the colours the game derives from all of those rather than computing its own time of day. |
| **Texture packs, connected textures, CIT** | Fully compatible. The pack ships no textures at all, so it cannot conflict with one. |
| **Other shader resource packs** | Only one can be selected; if two are, the higher one in the list wins per file, which can mix two packs' includes and break them. Select this one alone. |

## Known interactions inside the game

- **Blindness and the darkness effect** collapse the game's fog and sky distances
  to almost nothing. The pack keeps vanilla's `apply_fog` call and arguments
  everywhere, so both still work as they should.
- **Spectating a creeper, spider or enderman** adds that mob's post effect after
  the pack's. The pack's grade runs first, so the spectated effect applies on top
  of it, which is the correct order.
- **The first-person hand** is included in the pack's post-processing, because
  `end_of_frame` runs after the hand is drawn. That is what the hook does; the
  grade is applied to it exactly as it is to the world.
- **A very large FOV** (sprinting, flying, Speed effects) does not affect anything
  in the pack, because nothing reconstructs a projection. The sky gradient uses
  the direction of each vertex, which is correct at any FOV.

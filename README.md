# Native Vanilla Shaders

A complete shader for **Minecraft Java Edition 26.3** that ships as an ordinary
resource pack. No Iris, no OptiFine, no Oculus, no Sodium: drop the folder into
`resourcepacks/`, enable it, done.

It works because 26.3 lets a resource pack replace the game's own **core
shaders** (`assets/minecraft/shaders/core/`) and its **rendering includes**
(`assets/minecraft/shaders/include/`), and run its own full-screen passes
through the **`minecraft:end_of_frame` post effect**. That is the whole
architecture — see [ARCHITECTURE.md](ARCHITECTURE.md) for exactly which programs
are replaced and why, and [LIMITATIONS.md](LIMITATIONS.md) for what that
architecture genuinely cannot do.

Phase 1 source work is in final review. CI builds an installable Minecraft Java 26.3 pack, but no in-game rendering or performance result is claimed yet. Phase 2 is the Minecraft runtime and visual-validation stage; see [TESTING.md](TESTING.md) for its checklist.

## What it does

| | |
|---|---|
| **Sky** | Graded sky from the horizon to the zenith, a warm sunrise and sunset band, a sun and moon corona, a night sky with a nebula and a procedural star field. Dithered, so it does not band. |
| **Clouds** | The game's cloud volumes carved and shaded with a procedural multiscale field: cumulus masses, torn edges, lit tops, shaded undersides, and soft shadows on the ground. Nothing tiles. |
| **Water** | Warped, pixel-filtered waves; Fresnel; screen-space reflections of visible terrain; distorted refraction; reflected sun disc/glint and procedural sky/cloud fallback; absorption and whitecaps. |
| **Lighting** | A rewritten lightmap: sky and block light response curves, warm block light, deeper caves, and blacks that do not crush. All colours still come from the game. |
| **Weather and fog** | Sky-coloured aerial perspective, soft world-edge haze, rain-aware sun reflections, and dimension colouring that follows the game's own sky/fog values. |
| **Post** | Bloom, a highlight shoulder, contrast, saturation, sharpen, vignette and dither on the world, before the HUD. Optional FXAA as a separate effect. |
| **Plants** | Cutout plants sway — only the ones the native vertex data can actually identify. |

Ordinary gameplay paths are preserved: the end portal, beacon beams, lightning,
item glint, entity emissive and eyes pipelines retain their vanilla implementations.
The OIT pipeline branches remain intact; water-marker completeness with Improved
Transparency enabled is a known runtime test item (see [LIMITATIONS.md](LIMITATIONS.md)).

## Install

See [INSTALLATION.md](INSTALLATION.md). Short version: the pack is `pack.mcmeta`
plus `assets/`, so cloning this repository gives you a clean tree. Build the
installable folder or `.zip` with `python3 tools/package.py --zip`, put it in
`.minecraft/resourcepacks/`, enable it in **Options → Resource Packs**, and set
**Graphics: Fancy** and **Clouds: Fancy** so the cloud and water work has the
geometry it expects.

The user-supplied Minecraft 26.3 vanilla source archive and its extracted,
read-only tree are retained under `reference/vanilla-stock/` as the compatibility
baseline; they are excluded from the installable resource pack. The
`reference/carlodrift/` folder contains our own pointer README, not upstream code.
The external benchmark shaderpack is not bundled. See
[MANIFEST/licensing.md](MANIFEST/licensing.md).

## Requirements and expectations

Written for **Minecraft 26.3** (`pack_format` 97, `min_format`/`max_format`).
It will not load as intended on earlier versions: the 26.3 shader format replaced
`#moj_import`, requires a `layout(location)` on every varying, and reordered the
`Globals` and `DynamicTransforms` uniform blocks.

Tuned by default for a **low-end integrated GPU** (Intel HD Graphics 5500 class:
24 execution units, shared DDR3, a dual-core CPU). Every quality knob is a
`#define` in one file, [config.glsl](assets/nvs/shaders/include/config.glsl) —
there is no shader options menu in vanilla, so documented defines and the ability
to delete one JSON file are the options mechanism. See
[COMPATIBILITY.md](COMPATIBILITY.md).

## Honest status

CI runs the static pipeline checks in [`tools/check_pack.py`](tools/check_pack.py)
and a real GLSL syntax/type check with `glslangValidator` through
[`tools/compile_glsl.py`](tools/compile_glsl.py), including selected terrain and
OIT variants. It also builds the installable ZIP. This is stronger than static
inspection, but it is **not** Minecraft's exact ShaderC pipeline and does not
prove the pack loads or looks right in-game. Those still need Minecraft 26.3;
see [TESTING.md](TESTING.md).

## Documentation

- [INSTALLATION.md](INSTALLATION.md) — install, uninstall, per-feature switches.
- [ARCHITECTURE.md](ARCHITECTURE.md) — the replaced programs, the include
  library, the post chain, and the design rules.
- [FEATURE_MATRIX.md](FEATURE_MATRIX.md) — every requested feature and its real
  status, including the ones that are not possible.
- [COMPATIBILITY.md](COMPATIBILITY.md) — versions, backends, mods, hardware.
- [LIMITATIONS.md](LIMITATIONS.md) — the exact technical reason for each thing
  this architecture cannot do, and the closest valid alternative used instead.
- [TESTING.md](TESTING.md) — what was verified statically, how, and what you
  should check in game.
- [CHANGELOG.md](CHANGELOG.md)
- [MANIFEST/licensing.md](MANIFEST/licensing.md) — the origin of every third-party
  asset and idea.

## Licence

The NVS shader integration and procedural assets are authored for this pack. The
eight-wave water spectrum adapts the CC0 algorithm and parameters from the
`carlodrift/minecraft-vanilla-shaders` water-reflections example, rewritten for
NVS's data bus, filtering and performance budget. The external Complementary-based
benchmark was consulted visually only; it is not bundled and contributes no code,
textures or noise assets. See [MANIFEST/licensing.md](MANIFEST/licensing.md).

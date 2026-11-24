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

Two reference folders that the documentation mentions — the vanilla 26.3 shader
source and the benchmark shaderpack — are deliberately **not** in this repository,
because neither may be redistributed. See
[MANIFEST/licensing.md](MANIFEST/licensing.md). `tools/check_pack.py` runs without
them and checks more with them.

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

This pack was built without the ability to run Minecraft or compile GLSL. What
has been checked is written down in [TESTING.md](TESTING.md): structure, include
resolution, uniform and sampler availability against the 26.3 reference, varying
pairing across every linked partner, and post-effect validity — all through
[`tools/check_pack.py`](tools/check_pack.py). What has **not** been checked is
that it compiles in shaderc and that it looks right: that needs your game. Please
read [TESTING.md](TESTING.md) before deciding something is broken.

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

The shader code in this pack is original. It is derived from no shaderpack. The
one external shaderpack in this repository (`Good working shader/`) was used as a
visual benchmark only and no code, texture or noise asset from it appears here;
see [MANIFEST/licensing.md](MANIFEST/licensing.md).

# Testing

## What could be verified, and how

Minecraft and its exact `shaderc` pipeline cannot run in this CI environment.
However, CI now installs `glslangValidator`, expands the pack's and vanilla 26.3's
shader includes, and compiles every pack-owned core/post stage plus supported
multi-draw, OIT and end-portal variants with a real GLSL compiler. Run the same check locally with:

```sh
python3 tools/check_pack.py
sudo apt-get install glslang-tools
python3 tools/compile_glsl.py
```

The user-provided Minecraft 26.3 stock shader archive is retained under
`reference/vanilla-stock/Vanilla-stock /` for include resolution, partner-stage
checks and GLSL compilation. It is excluded from the installable pack by
`tools/package.py`. `tools/manifest.py` uses this same extracted reference
folder when checking the vanilla hashes.

| Check | What it proves |
|---|---|
| **structure** | `pack.mcmeta` parses and declares format 97. Every required file exists. **No file that only exists for a loader does**: no `*.properties`, no `gbuffers_*`, no `shadow`/`deferred`/`composite`/`final`/`prepare` at the shaders root, no `world0`/`world1`/`world-1` folders. A vanilla resource pack cannot use any of those, and their presence would mean the pack is not what it claims. |
| **declarations** | Every `uniform` block and every sampler in every replaced program is one the program's pipelines actually provide — checked against the 26.3 reference — **and** every conditional one is declared under exactly the guard its variant requires (`Sampler2` and `ChunkSection` in terrain, under `#ifndef OIT_ALPHA_ONLY` and `#ifndef MULTIDRAW_TERRAIN`). Declaring an unprovided uniform is the most common way a pack like this gets every resource pack disabled, so this is the check that matters most. |
| **include** | Every `#include <ns:path>` resolves, to a file in the pack or to vanilla. No include contains `#version`. The replaced `fog.glsl` still declares every function the vanilla one declares, because other programs call them. |
| **varyings** | For every replaced fragment program, every `in` has an `out` at the same location in **every** vertex program the game links with it, with the same base type and the same `flat` qualifier. This is what keeps `position_color.fsh` valid when it is linked with `debug_point.vsh` as well as `position_color.vsh`. |
| **post effects** | Each post-effect JSON parses, every declared output and input target exists, every referenced shader exists, no two inputs share a sampler name, each pass's shaders declare only their own inputs' samplers plus the two blocks a post pass is given, and no effect names a game target other than `minecraft:main`. A broken post effect is compiled on first use and then disables every selected pack mid-game, so this is the check that second-most matters. |
| **glsl hygiene** | `#version` is first, the separate-shader-objects extension is present, no `#moj_import`, braces/parens/brackets balance, preprocessor conditions nest, no plain non-block uniforms, and every varying has a `layout(location)`. |
| **GLSL compiler** | `tools/compile_glsl.py` recursively expands includes and runs `glslangValidator` on pack-owned core/post stages, including `MULTIDRAW_TERRAIN`, OIT depth-bounds/transmittance/accumulation variants, both OIT coefficient layouts and both end-portal layer counts. This catches actual syntax and type errors, but is not Minecraft ShaderC. |

`tools/manifest.py --check` (or `--write` first) verifies the SHA-256 manifests
against the vanilla reference folder and the pack files.

## What has **not** been verified

Be aware of these before concluding something is broken, and equally before
concluding it works:

1. **That Minecraft ShaderC accepts every program.** `glslangValidator` is a
   separate compiler and cannot reproduce Minecraft's exact preprocessing,
   backend settings or pipeline linking.
2. **That every pipeline variant compiles.** CI checks every pack-owned core/post
   stage plus supported multi-draw, OIT depth-bounds/transmittance/accumulation and
   end-portal layer variants. Minecraft still builds additional combinations and
   links stages against its own pipeline definitions.
3. **Any framerate figure.** The water pass uses a bounded 24-step screen-space ray
   march plus four refinements; cloud shadows use reduced octaves and bloom uses a
   fixed small target. None of this has been measured on the Intel HD 5500 target.
4. **That it looks right.** Every colour decision is a judgement.

## What to check in game, in this order

If something is wrong, this order finds it fastest.

1. **Does the pack enable at all?** Options → Resource Packs. If it is listed as
   incompatible, the game version is not 26.3.
2. **Read `logs/latest.log`.** If the pack enabled and then vanished, look for
   `Caught error loading resourcepacks, removing all selected resourcepacks`. The
   lines just before it name the program and the line number. That message means a
   core shader failed and the game dropped every selected pack — not just this one.
3. **Sky, at noon** (`/time set 6000`): a gradient from a pale horizon to a deeper
   zenith, no banding across the open sky, and no seam where distant terrain meets
   the sky.
4. **Sunrise and sunset** (`/time set 12800` and `/time set 23000`): a warm band
   low in the sky that is strongest around the sun, a soft radial glow rather than
   a hard disc, and a corona around the sun that fades smoothly to nothing.
5. **Night** (`/time set 18000`): a nebula and a star field, brighter toward the
   zenith than the horizon, and the game's own stars still visible on top.
6. **Clouds, at noon**: torn edges instead of rectangular cells, bright tops and
   darker undersides, no visible grid as the camera moves.
7. **Water**: first check that the surface is continuous and not striped. Look for
   reflected islands/shoreline geometry, the sun disc and cloud shapes; rotate the
   camera to check that screen-space reflections fade cleanly at screen edges.
   Look down into the water for distorted refraction and a blue-green depth tint;
   check distant water against the horizon for dark bands, aliasing or a black edge.
   Check wave highlights and foam for temporal jumps at `/time set 0`.
8. **Underwater** (`/execute as @s run tp @s ~ ~ ~` into an ocean, then look
   around): water fog, and the surface reading as a surface rather than a mirror.
9. **A cave with a torch**: warm light that falls off, and dark that is dark but
   not crushed to pure black.
10. **Rain** (`/weather rain 600`): a dimmer sky, a dimmer sun and moon, and fog
    that fades in rather than starting at a line.
11. **The Nether and the End**: their own colours, intact. The End's sky is a
    different pipeline and should look exactly as vanilla.
12. **The GUI**: the HUD, chat and inventory must be **unaffected** by the grade.
    If they are graded, the post chain is running at the wrong time and something
    is badly wrong.
13. **Improved Transparency on** (graphics preset must be "custom"): compare
    water tagging/reflections with OIT off and on. The terrain OIT branches are
    preserved, but water markers are emitted only in the final colour pass, so
    incomplete SSR tagging is a known risk. Glass and clouds must remain intact.

## If it is too slow

Delete `assets/minecraft/post_effect/end_of_frame.json` only as a last-resort
compatibility/performance fallback: it disables the data-bus sky/fog reconstruction,
water reflections/refraction, bloom and the final grade together. First lower
`NVS_WATER_SSR_STEPS` to 16 and `NVS_WATER_SSR_REFINE_STEPS` to 3, then lower
`NVS_CLOUD_OCTAVES` to 3 and `NVS_CLOUD_SHADOW_OCTAVES` to 2. The full order is
in [INSTALLATION.md](INSTALLATION.md).

## Regression discipline

Any change to a shader should be followed by:

```sh
python3 tools/check_pack.py        # must print PASS
python3 tools/manifest.py --write  # refresh the hashes
python3 tools/manifest.py --check  # must print PASS
python3 tools/compile_glsl.py      # supported GLSL variants must compile
```

On pushes to `main`, CI refreshes and commits the two manifest JSON files
automatically after the checks. Pull requests run `manifest.py --check` and fail
if their hashes or reason entries are stale. The numbered in-game checks remain
necessary for the features a change touches.

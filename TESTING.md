# Testing

## What could be verified, and how

Minecraft cannot run here, and neither can `shaderc`, so **no GLSL in this pack
has been compiled**. What has been done instead is every static check that stands
in for a compile, through [`tools/check_pack.py`](tools/check_pack.py):

```sh
python3 tools/check_pack.py
```

The vanilla 26.3 shader source is not distributed with this repository, because it
is Mojang's. Every check runs without it; two of them — include resolution against
vanilla's includes, and varying pairing against a vanilla partner such as
`screenquad.vsh` — are weaker, and the tool prints a note saying so. Put your own
copy of the vanilla `shaders/` tree in a folder named `Vanilla-stock /` beside the
pack to get the full set. `tools/manifest.py` needs that folder and will refuse to
run without it.

| Check | What it proves |
|---|---|
| **structure** | `pack.mcmeta` parses and declares format 97. Every required file exists. **No file that only exists for a loader does**: no `*.properties`, no `gbuffers_*`, no `shadow`/`deferred`/`composite`/`final`/`prepare` at the shaders root, no `world0`/`world1`/`world-1` folders. A vanilla resource pack cannot use any of those, and their presence would mean the pack is not what it claims. |
| **declarations** | Every `uniform` block and every sampler in every replaced program is one the program's pipelines actually provide — checked against the 26.3 reference — **and** every conditional one is declared under exactly the guard its variant requires (`Sampler2` and `ChunkSection` in terrain, under `#ifndef OIT_ALPHA_ONLY` and `#ifndef MULTIDRAW_TERRAIN`). Declaring an unprovided uniform is the most common way a pack like this gets every resource pack disabled, so this is the check that matters most. |
| **include** | Every `#include <ns:path>` resolves, to a file in the pack or to vanilla. No include contains `#version`. The replaced `fog.glsl` still declares every function the vanilla one declares, because other programs call them. |
| **varyings** | For every replaced fragment program, every `in` has an `out` at the same location in **every** vertex program the game links with it, with the same base type and the same `flat` qualifier. This is what keeps `position_color.fsh` valid when it is linked with `debug_point.vsh` as well as `position_color.vsh`. |
| **post effects** | Each post-effect JSON parses, every declared output and input target exists, every referenced shader exists, no two inputs share a sampler name, each pass's shaders declare only their own inputs' samplers plus the two blocks a post pass is given, and no effect names a game target other than `minecraft:main`. A broken post effect is compiled on first use and then disables every selected pack mid-game, so this is the check that second-most matters. |
| **glsl hygiene** | `#version` is first, the separate-shader-objects extension is present, no `#moj_import`, braces/parens/brackets balance, preprocessor conditions nest, no plain non-block uniforms, and every varying has a `layout(location)`. |

`tools/manifest.py --check` (or `--write` first) verifies the SHA-256 manifests
against the vanilla reference folder and the pack files.

## What has **not** been verified

Be aware of these before concluding something is broken, and equally before
concluding it works:

1. **That the GLSL compiles.** Only shaderc can answer that, and it is part of the
   game. The specific things most likely to be wrong are ordinary typos, a missing
   include guard, or a type mismatch the static checks cannot see.
2. **That every define variant compiles.** The game compiles a program once per
   pipeline: `terrain` in 14 variants, `entity` in 37, `clouds` in 8. The pack
   keeps vanilla's `#ifdef` structure deliberately, and the declaration check
   covers the conditional uniforms, but a variant-specific mistake cannot be
   disproved without the compiler.
3. **Any framerate figure.** The performance tuning is reasoned (no ray marching,
   fixed small bloom target, bounded octaves) but unmeasured.
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
7. **Water**: waves visible as moving highlights, strong reflection at a grazing
   angle and clear water when looking down, and a distinctly different look from
   under the surface. Check a seashore for no gaps at chunk borders and no
   sparkling at block seams.
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
13. **Improved Transparency on** (graphics preset must be "custom"): water, glass
    and clouds should look the same as with it off, only sorted better.

## If it is too slow

Delete `assets/minecraft/post_effect/end_of_frame.json` first. It removes three
full-screen passes and no visual feature except bloom, the grade and the vignette.
Then lower `NVS_CLOUD_OCTAVES` to 3 and set `NVS_CLOUD_CUTOFF` to `0.38`. The
full order is in [INSTALLATION.md](INSTALLATION.md).

## Regression discipline

Any change to a shader should be followed by:

```sh
python3 tools/check_pack.py        # must print PASS
python3 tools/manifest.py --write  # refresh the hashes
python3 tools/manifest.py --check  # must print PASS
```

and by the numbered in-game checks above for the features the change touches.

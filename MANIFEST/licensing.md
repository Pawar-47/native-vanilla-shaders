# Licensing manifest

Recorded so that the origin of every third-party asset and idea is traceable.
Nothing in `assets/` comes from another shader pack.

## What this repository contains

Only the pack and its tooling: `pack.mcmeta`, `assets/`, the documentation,
`tools/` and `MANIFEST/`. Three folders named throughout this document are **not**
in the repository, and are excluded by `.gitignore`, because two of them cannot
lawfully be redistributed:

| Folder | Why it is not here |
|---|---|
| `Good working shader/` | The Complementary License 1.8 forbids redistribution. |
| `Vanilla-stock /` | Mojang's own client shader source, for the same reason as the game. Supply your own copy beside the pack to run `tools/check_pack.py` (it degrades to a note without it) and `tools/manifest.py` (it needs it). |
| `.research/` | Copies of another repository's experiment definitions, kept locally as build-time reference. |

Everything below therefore describes material that was read while building the
pack, not material the repository distributes.


## What this pack ships

Every file under `assets/` is original code written for this pack, with one
exception class: the files that **replace** a vanilla 26.3 program or include.
Those are derived from Minecraft's own shader source (the `Vanilla-stock /`
folder in this repository) and are listed, one by one with the reason for each, in
[modified-files.json](modified-files.json). They remain subject to the Minecraft
End User Licence Agreement and Mojang's Usage Guidelines; they are not licensed by
the author of this pack.

The pack ships **no textures, no noise images, no fonts and no audio**. Every
pattern it draws is arithmetic — hashes, value noise and sine waves — so there is
nothing to attribute and nothing that can conflict with a texture pack.

## `Good working shader/` — benchmark only, no code taken

`Good working shader/License.txt` is the **Complementary License Agreement 1.8**
(the pack inside is a Complementary Reimagined-based Iris shaderpack). That licence
forbids redistributing parts of the pack and modifying its code, and this project's
own instruction is stricter still: no copying, porting, translating or
redistributing its GLSL, textures or noise assets, including into another shader
architecture.

**Nothing from that folder appears in this pack.** Specifically:

- no GLSL file, function, constant or comment was copied, ported or translated;
- no texture or noise image was used (`textures/cloud-water.png`,
  `noise.png`, `cucumber.png` are untouched and unreferenced);
- no shaderpack metadata was used — this pack has no `shaders.properties`,
  `block.properties`, `entity.properties`, `item.properties`,
  `dimension.properties` or `colorwheel.properties`, all of which are loader
  features that do not exist in vanilla;
- the pack's include library, its cloud field, its wave model and its sky model
  are written from the physics and from the vanilla interfaces, not from that
  code.

It was used for one thing only: as a visual and feature benchmark, to decide *what
the result should look and feel like* — how deep the sky should grade, how much of
the cloud edge should be torn, how strong Fresnel should read on water, how much
bloom. Those are judgements about an outcome, and the implementations that achieve
them here are original and constrained by a completely different architecture
(there is no G-buffer to read, no buffer to allocate, and no shadow map).

The folder is not in this repository: the licence does not permit redistribution,
so it was never committed. It is recorded here as the benchmark it was, not as
part of the deliverable, and it is not inside the pack's `assets/`. **Do not
distribute it with the pack.**

## `carlodrift/minecraft-vanilla-shaders` — technical reference

That repository is licensed: **tools MIT, documentation CC BY 4.0, example and
experiment shader code CC0**. It was used as the technical reference for what the
26.3 vanilla architecture actually permits, because it is the only source of
verified, in-game-checked facts about it. The specific facts this pack relies on:

- that `assets/minecraft/post_effect/end_of_frame.json` is the hook a resource pack
  can use to post-process every frame, and that it runs after the world and the
  hand and before the GUI;
- the post-effect JSON schema: `targets` with `width`/`height`/`persistent`/
  `clear_color`, `passes` with `vertex_shader`/`fragment_shader`/`inputs`/`output`,
  the `<sampler_name>Sampler` naming, the rule that a pass may only read the
  `minecraft:main` game target, and that a failing post effect removes every
  selected resource pack;
- that a post pass is given only `Globals`, `SamplerInfo` and its own input
  samplers, plus the blocks its JSON lists;
- the 26.3 `pack.mcmeta` format (`min_format`/`max_format` 97);
- `#include` rules, the `#moj_import` removal, the `layout(location)` requirement,
  the `GL_ARB_separate_shader_objects` requirement, and that `terrainglobals.glsl`
  has a typo in its include guard so it must be included only once;
- that the sky disc is drawn with the camera rotation alone and that
  `normalize(Position).y` is its elevation, while the below-horizon dark disc is
  the same program translated 12 blocks down;
- that `core/position_tex` is the celestial pipeline only, that the sun's quad is
  scaled by 30 and the moon's by 20, that the celestial blend is additive as
  `source * alpha + dest`, and that rain brightness arrives in `ColorModulator.a`;
- that the sunrise and sunset glow is a fixed fan of 18 vertices drawn by
  `core/position_color`, and that its pipeline blends with `(one, one)` so alpha
  has no effect;
- that water textures have a uniform alpha of 180/255, that slime shares it, and
  that the raw pre-lighting vertex colour is what separates them;
- that cutout plants can be identified by cutout + biome tint + off-grid position,
  and that neither end of a plant is identifiable;
- that the environmental fog end is at most 96 in water and 768 or more in air;
- that `core/lightmap` is drawn once per frame with `LightmapInfo`, and the
  meaning of each of its members.

The four JSON files in `.research/` are copies of that repository's experiment
definitions, kept as the reference they are. They are **not** part of the pack,
they are not inside `assets/`, and the checks and assets they describe are that
repository's, not this pack's.

Attribution for the documentation, as CC BY 4.0 requires:

> Documentation and reference material from **carlodrift/minecraft-vanilla-shaders**
> (https://github.com/carlodrift/minecraft-vanilla-shaders), © carlodrift,
> licensed CC BY 4.0. Example and experiment shader code under CC0. No code from
> that repository is included in this pack; the facts listed above are used as
> technical reference and the implementations here are original.

## `Vanilla-stock /` — the vanilla 26.3 shader source

Mojang's own shader source for Minecraft Java Edition 26.3, 89 files (63 under
`core/`, 9 under `post/`, 17 under `include/`). It is the technical foundation: the
pack preserves its interfaces, uniforms, samplers, vertex attributes, varyings,
version declarations, conditional guards, its reversed-depth convention and its
OIT paths, and overrides only the programs a feature actually needs.

Its files are Mojang's. The pack does not redistribute them; it replaces 15 of them
with modified versions and adds 2 post-effect files, all listed in
[modified-files.json](modified-files.json). Hashes in
[vanilla-hashes.json](vanilla-hashes.json).

## `../Ref-Shader/MakeUp-UltraFast-9.6a` — not used

Another project's folder, reachable from this one. It was **not** used: no code,
no idea and no constant from it appears in this pack. Recorded here only so that
the absence is explicit.

## Summary table

| Source | Licence | Used for | Code or assets taken |
|---|---|---|---|
| This pack's own code | © the pack's author | everything in `assets/nvs/` | — |
| `Vanilla-stock /` (Mojang, MC 26.3) | Minecraft EULA / Usage Guidelines | the 15 replaced programs and includes | replaced files only, listed |
| `carlodrift/minecraft-vanilla-shaders` | docs CC BY 4.0, code CC0 | verified architectural facts | none |
| `Good working shader/` | Complementary License Agreement 1.8 | visual benchmark | **none** |
| `../Ref-Shader/MakeUp-UltraFast-9.6a` | — | nothing | none |

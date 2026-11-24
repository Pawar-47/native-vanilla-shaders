# External technical reference: carlodrift/minecraft-vanilla-shaders

Repository: https://github.com/carlodrift/minecraft-vanilla-shaders

This project is an active technical reference for Minecraft Java 26.3 native core shaders and post effects. It is used alongside the exact vanilla 26.3 source archive in `reference/vanilla-stock/`.

## How this reference is used

- **Vanilla source archive in this repository:** authoritative starting point for the exact shader interfaces, uniform blocks, samplers, vertex attributes, include layouts and pipeline variants shipped with our target game version. Where we replace a vanilla shader, preserve its pipeline contract and adapt the original source rather than inventing inputs.
- **carlodrift reference:** implementation research and evidence for 26.3 behavior. Consult its generated core-shader and pipeline references, writing/porting documentation, post-effect guide, experiments and focused examples.
- **Our implementation:** original NVS code and design. Reference examples inform techniques and constraints; they are not blindly copied. Every adopted technique must be reconciled with our own vanilla 26.3 archive, current pack architecture, performance target and license.

## High-value reference areas

- [Writing shaders for 26.3](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/writing-shaders.md) — ShaderC compilation, locations, varyings, vertex inputs, uniform/sampler contracts and variants.
- [Generated core shader reference](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/reference/core-shaders.md) — pipeline partners, defines, inputs and available resources.
- [Generated pipeline reference](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/reference/pipelines.md) — the actual pipeline matrix.
- [Post effects](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/post-effects.md) — end-of-frame chains, targets, depth and sampler rules.
- [Techniques](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/techniques.md) — verified native rendering techniques.
- [Water reflections example](https://github.com/carlodrift/minecraft-vanilla-shaders/tree/main/examples/water-reflections) — screen-space water marking, depth-based reflection/refraction and Fresnel; use as a design study, not a drop-in patch.
- [Scattered sky example](https://github.com/carlodrift/minecraft-vanilla-shaders/tree/main/examples/scattered-sky) — atmospheric scattering, sky reconstruction and fog integration; evaluate carefully against the low-end GPU target.
- [Sun lighting example](https://github.com/carlodrift/minecraft-vanilla-shaders/tree/main/examples/sun-lighting) — post-process lighting reconstruction and its trade-offs.
- [Sodium compatibility](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/docs/sodium.md) — separate terrain pipeline requirements if Sodium support is added.

## Licensing and provenance

The upstream repository documents its tools as MIT, documentation as CC BY 4.0, and example/experiment shader code as CC0 (see its [LICENSE.md](https://github.com/carlodrift/minecraft-vanilla-shaders/blob/main/LICENSE.md)). Preserve attribution where required for documentation, retain applicable notices for any reused material, and record provenance in the change that adopts it. Do not assume every external asset or dependency shares the example-code license.

## Engineering rule

Do not mark a feature complete because a reference demonstrates it. First verify that its inputs and pipeline assumptions exist in the vanilla 26.3 archive, adapt it to NVS, then compile every affected pipeline variant and perform an in-game visual check when available.

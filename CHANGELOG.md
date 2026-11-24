# Changelog

All notable changes to this pack. Versions follow the pack's own numbering, not
the game's.

## 1.0.0 — first release, for Minecraft 26.3

The first complete version. Built against the vanilla 26.3 shader source in
`Vanilla-stock /`, as a plain resource pack with no shader loader.

### Added

**Sky and celestial**
- Graded sky built from the game's own `ColorModulator` and `FogColor`, along an
  elevation curve that reaches the horizon colour exactly, so there is no flat
  gradient and no seam where fogged terrain meets the sky.
- A warm sunrise and sunset band whose strength follows how warm the game's
  horizon colour already is.
- Procedural night sky: a fractal nebula concentrated along a galactic band, an
  airglow gradient, and a two-layer star field with per-star magnitude and colour
  temperature. Gated on how dark the game's own sky colour is, so it needs no
  clock and works in every dimension.
- 4×4 ordered dithering in the sky and again in the post composite, against 8-bit
  banding.
- A corona around the sun and the moon, drawn inside the quad each body already
  occupies, where the radial distance is literally an angular distance. Fades to
  zero at the quad edge and follows rain brightness.
- Per-star colour and brightness on the game's own star points.
- A radial gradient on the sunrise and sunset glow, replacing vanilla's flat
  disc. Required overriding `debug_point.vsh` as well, because
  `position_color.fsh` is linked with it too.

**Clouds**
- A procedural multiscale cloud field — a smooth mass plus a ridged detail
  channel — that carves the game's cloud volumes into cumulus forms with torn,
  wispy edges. Nothing tiles; there is no texture and no lookup table.
- Density and orientation shading: lit tops, shaded undersides, darker creases.
- Soft cloud shadows on the ground from the same field, weighted by how lit the
  pixel already is.
- Works correctly through all three Improved Transparency passes: the discards
  happen before every OIT branch, so the passes agree.

**Water**
- Multi-scale wave normals: three directional waves plus a noise ripple that
  drifts around a circle so it loops exactly when the day does.
- Fresnel-weighted reflection of the same sky the pack draws, plus the cloud deck
  sampled where the reflected ray crosses it.
- Depth-dependent absorption over the path through the water, red first.
- Whitecaps broken up by noise.
- A distinct look from under the surface, detected from the fog distances the game
  collapses only in water.
- Water recognised by the two properties the game's textures supply: the uniform
  180/255 alpha, and a biome tint that the slime block does not have.

**Lighting**
- Rewritten lightmap: separate sky and block light response curves, a longer
  reach for block light with more of its warmth kept, and a small ambient lift so
  caves and nights do not crush to black. Every colour still comes from
  `LightmapInfo`, so the game's own sun colour, moonlight, weather and dimension
  tinting all still apply.

**Weather and fog**
- Replaced `fog.glsl`: the fog value now goes through a smoothstep between the
  same start and end, so fog fades in instead of starting at a visible line. Every
  uniform, signature and colour is unchanged, so underwater fog, blindness,
  darkness and rain fog keep the game's behaviour.

**Plants**
- Cutout plants sway, identified only from the three properties the native vertex
  data actually supplies: cutout pipeline, biome tint, and off the block grid.

**Post-processing**
- `minecraft:end_of_frame` chain: a bright-pass ring blur into a fixed 480×270
  target, a composite (sharpen, bloom, highlight shoulder, contrast, saturation,
  vignette, dither), and a copy back to the main target.
- The pack ships its own full-screen vertex program, because the game's is
  renamed in the 26.4 snapshots and a broken post effect removes every selected
  pack mid-game.
- Optional FXAA as a separate post effect, applied with
  `/posteffect add @s nvs:fxaa`.
- All tunables as `#ifndef`-guarded defines in one file, since vanilla has no
  shader options menu.

**Tooling and documents**
- `tools/check_pack.py`: structure, declarations against the 26.3 reference in
  every variant, include resolution, varying pairing across every linked partner,
  post-effect validity, and GLSL hygiene.
- `tools/manifest.py`: generates and verifies the SHA-256 manifests for the
  vanilla sources and the replaced files.
- `MANIFEST/`: vanilla source hashes, per-file provenance with reasons, and a
  licensing manifest.
- README, INSTALLATION, ARCHITECTURE, FEATURE_MATRIX, COMPATIBILITY, LIMITATIONS,
  TESTING.

### Deliberately not implemented

Documented with exact reasons in [LIMITATIONS.md](LIMITATIONS.md): refraction of
the scene behind water, caustics, a true sun-facing cloud light, cast shadows, and
HDR tone mapping. None of them is faked on the wrong inputs.

### Verified

Static checks only; no GLSL has been compiled. See [TESTING.md](TESTING.md).

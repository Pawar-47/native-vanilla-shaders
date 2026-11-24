# Architecture

## The constraint that shapes everything

26.3 gives a resource pack three, and only three, ways to change how the world is
drawn:

1. **Replace a core shader**: a file at `assets/minecraft/shaders/core/<name>.vsh`
   or `.fsh` replaces the program the game's render pipeline names. The program is
   then compiled once per pipeline that uses it, with that pipeline's `#define`s.
2. **Replace an include**: a file at `assets/minecraft/shaders/include/<name>.glsl`
   replaces the include for every program that includes it.
3. **Add a post effect**: a JSON at `assets/<ns>/post_effect/<name>.json`, with
   its own shaders. `minecraft:end_of_frame` runs every frame on the world, after
   the hand and before the GUI.

There is no buffer allocation, no G-buffer, no shadow map and no per-pass state
control. A core shader can only read the uniforms, samplers and vertex inputs its
pipeline already provides — declaring anything else fails to load, and a single
failing shader makes the game drop **every** selected resource pack.

So the pack is built on one rule: **read what the game already knows, and shape
it.** The game computes and hands over a great deal — the sky's colour, the fog's
colour, the cloud colour, the sun's light colour, the lightmap factors, the block
light tint — each already correct for the hour, the weather, the biome and the
dimension. None of the pack tries to work out what time it is or which dimension
it is in; it shapes the values it is given. That is why the Nether and the End
need no special case and why the pack survives datapacks that move the clock.

## The include library

`assets/nvs/shaders/include/` — the pack's own code, included by the replaced
programs. None of it declares a uniform, so it is safe to include anywhere.

| File | Role |
|---|---|
| `config.glsl` | Every tunable, as an `#ifndef`-guarded `#define`. |
| `noise.glsl` | Hash, value noise, and a fractal sum whose octaves are rotated before they are scaled, so no grid or direction lines up. |
| `common.glsl` | Luminance, dither, warmth, small helpers. |
| `sky.glsl` | The sky as a function of direction; the night sky; a zenith colour inferred from the horizon for programs that do not get the sky colour. |
| `clouds.glsl` | The cloud field, the shading, and the shadow the field casts on the ground. |
| `water.glsl` | Water recognition, wave normals, the reflected sky and clouds, and the water fragment shader. |

`sky.glsl`, `clouds.glsl` and `water.glsl` are shared deliberately: the same
function that shapes a cloud casts its shadow, and the same sky that is drawn is
the one the water reflects.

## Replaced programs, and why each one

### `include/fog.glsl`

Vanilla's fog is linear in distance from the start to the end, so it begins at a
visible line and ends at a wall. The replacement keeps both endpoints, every
uniform, and every function signature — other programs call these — and changes
one expression: the fog value goes through a smoothstep. `FogColor` and
`FogColor.a` are untouched, so underwater fog, blindness, the darkness effect and
rain fog keep the colours and distances the game chose.

This is the single change with the widest reach: terrain, entities, items,
particles, glint, clouds, the sky, the end portal, the beacon beam, the lightning,
leashes and text all go through it at once.

### `core/sky.vsh` / `sky.fsh`

*Only the `sky` pipeline uses this program.* The disc is drawn with the camera
rotation alone, so the direction of each vertex from the eye is a world-space
direction, and the vertex's `y` is the elevation — exactly 1 at the zenith and
about 0 at the rim.

`sky.fsh` mixes vanilla's own sky colour (`ColorModulator`) with vanilla's own
horizon colour (`FogColor`) along a curve in the elevation rather than flat. Both
colours already carry the hour, the weather and the dimension. The curve is
designed so that it reaches the horizon colour exactly at the rim, which is why
there is no seam where the sky meets fogged terrain — and why the "hard horizon
edge" of a flat sky is gone.

The night sky is gated on **how dark the game's own sky colour already is**, not
on a clock. When vanilla's sky fades out, the pack's nebula and star field fade
in, in every dimension and at every hour, without the pack knowing which is
which.

Vanilla's `apply_fog` call is kept with vanilla's arguments, which is what keeps
the sky collapsing to fog under blindness and underwater.

The program also draws the **shadow, and the below-horizon dark disc**. The
vertex shader flags the second one (its model-view matrix carries a translation)
and the fragment shader leaves it alone: it exists to hide the void, and painting
it as sky would be wrong.

### `core/stars.vsh` / `stars.fsh`

Vanilla's stars are a fixed buffer of single-pixel points drawn with
`ColorModulator` and nothing else: no per-star attribute, no texture. The
position is the only per-star input that exists, so the variation comes from a
hash of the direction, which is stable for the life of the world. The result is
magnitudes and colour temperatures instead of a field of identical dots.

The dense, soft star field is drawn by `sky.fsh` instead, where a per-pixel dot
can be given a size and a smooth falloff.

### `core/position_tex.vsh` / `position_tex.fsh`

*Only the `celestial` pipeline uses this program: the sun and the moon, and
nothing else.* That makes it the one place where the sun's exact direction is
available, because the model-view matrix's translation is the body's position on
the celestial sphere.

The pack draws a corona **inside the quad the body already occupies**, where the
radial distance from the centre is literally an angular distance: the quad's edge
is about 17 degrees out for the sun. The halo is faded to exactly zero at that
edge so it has no cut-off.

The blend is additive as `source * source alpha + dest`. The fragment shader
folds the body's own alpha into the colour and writes alpha 1, which makes the
additive result **identical to vanilla's for the body** while putting the halo
beside it. Rain brightness arrives in `ColorModulator.a` and fades both.

### `core/position_color.vsh` / `.fsh` and `core/debug_point.vsh`

The sunrise and sunset glow is a fixed fan of 18 vertices around the sun, drawn
with one flat colour, which is why vanilla's horizon glow reads as a hard-edged
disc. The vertex shader recognises the fan by geometry (a centre at `(0,100,0)`
and a ring about 120 units out, under a perspective projection, in the first 18
vertices) and computes a radial factor; the fragment shader multiplies the colour
by it. It multiplies the **colour**, not the alpha, because that pipeline blends
with `(one, one)`, where alpha is ignored.

`debug_point.vsh` is replaced only because `position_color.fsh` is linked with it
too: every fragment input needs a vertex output at the same location in every
partner. It writes a factor of 1.

### `core/clouds.vsh` / `clouds.fsh`

The game builds cloud boxes and hands over the cell coordinates, `CellSize`,
`CloudOffset` and `CloudColor`. The vertex shader passes the world-anchored XZ of
each fragment — `CloudOffset` is already in the position, so the procedural field
travels with the clouds the game moves — and which way the face points.

The fragment shader carves the volume with a field of two channels, a smooth mass
for the cumulus blocks and a ridged detail for the torn edges, and shades it by
density and orientation. Fragments below the cutoff are discarded, and **the
discard happens before every OIT branch**, so the three Improved Transparency
passes discard identical fragments and their transmittance stays consistent with
the colour pass.

All of the hour, the weather and the dimension arrive in `CloudColor`. The sun's
direction is *not* available to this program, so the shading is a key light from
above plus a thickness term rather than a true sun-facing term; see
[LIMITATIONS.md](LIMITATIONS.md).

### `core/terrain.vsh` / `terrain.fsh`

The largest change, and the one with the most care taken over the variants: the
program is compiled for 14 pipelines, with and without `MULTIDRAW_TERRAIN`,
`ALPHA_CUTOUT` at 0.1 and 0.5, and the three OIT passes. Vanilla's `#ifdef`
structure is preserved line for line.

The vertex shader adds three varyings — the absolute world position, the
camera-relative position, and the raw pre-lighting tint — and sways plants.

The fragment shader does two things, both confined to the **colour**:

- **Water.** Recognised by the two properties the game's own textures supply: every
  water texture has a uniform alpha of 180/255, and water is biome-tinted, which
  the slime block (the other 180/255 texture) is not. The tint has to be the raw
  pre-lighting vertex colour to be usable, which is why the vertex shader passes
  it.
- **Ground.** Cloud shadows, applied in proportion to how lit the pixel already is.

Neither touches the alpha, which keeps the surface translucent over whatever is
beneath it and keeps the OIT passes consistent. That is also the reason the
surface cannot be refracted: see [LIMITATIONS.md](LIMITATIONS.md).

Water shading: the geometry is left exactly where the game put it — moving it
would move glass and ice, which share the translucent pass and which the vertex
shader cannot tell apart — and the waves live in the normal. Fresnel is Schlick
with water's `F0`. The reflection is the same sky function that `sky.fsh` draws,
plus the cloud layer sampled where the reflected ray crosses it, which is
geometrically right for a flat cloud deck and cheap.

### `core/lightmap.fsh`

The 16×16 texture that every lit surface multiplies its albedo by, drawn once per
frame. Changing it changes the whole game's lighting for the cost of 256 pixels,
and no other program has to know.

Every colour still comes from `LightmapInfo`: `SkyLightColor` is already the
colour of the sunlight for the current celestial angle and weather, and
`BlockLightTint` is already the colour of torchlight in this dimension. The pack
changes the response curves, keeps more of the block light's warmth, and lifts
absolute black slightly so caves and nights do not crush. Vanilla's ordering of
the boss-overlay darkening, the darkness scale and the gamma blend is preserved.

### The post chain

`assets/minecraft/post_effect/end_of_frame.json` — three passes:

1. `nvs:post/bloom` reads `minecraft:main` and writes a fixed 480×270 target.
   Bloom is a glow, so it does not need the screen's resolution, and a fixed
   target keeps the cost identical on every display. It is a bright pass and a
   ring blur in one pass, so no separate extract pass is needed.
2. `nvs:post/composite` reads main and the bloom target and writes a swap target:
   sharpen, bloom, highlight shoulder, contrast, saturation, vignette, dither.
3. `nvs:post/copy` copies the swap target back to `minecraft:main`.

Pass 2 could read and write `minecraft:main` directly — 26.3 allows it — but a
feedback loop through the current render target is exactly the kind of thing a
low-end driver can get wrong, so the pack pays for one extra copy instead.

The pack ships its own full-screen vertex program rather than referencing the
game's, because the game renamed it in the 26.4 snapshots and a post effect that
fails to compile removes every selected resource pack mid-game.

`nvs:post_effect/fxaa.json` is a second, optional effect: not in the default
chain, applied with `/posteffect add @s nvs:fxaa`.

## Rules the code follows

- **Only declare what the pipeline provides.** Every uniform block and sampler in
  every replaced file is checked against the 26.3 reference, under the right
  `#if` guard for the variants where it only exists.
- **Preserve every variant.** No replaced program changes vanilla's `#ifdef`
  structure; the OIT paths, `MULTIDRAW_TERRAIN`, `ALPHA_CUTOUT`, `DISSOLVE` and
  the rest behave exactly as they did.
- **Derivatives before branches.** `sampleNearest` and `sampleRGSS` take
  screen-space derivatives, so they are always called unconditionally at the top
  of the fragment program.
- **Never invent a material input.** If the native vertex data does not identify
  something, the pack does not pretend it does. Where that costs a feature, it is
  listed in [LIMITATIONS.md](LIMITATIONS.md) with the reason.
- **Colour before `calculateFinalColor()`.** Translucent changes are made to
  `color`, never to `fragColor` afterwards, so they survive all three OIT passes.

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
| `noise.glsl` | 2D and 3D value noise, hash functions, and fractal sums for cloud volume, water waves and sky detail. |
| `common.glsl` | Luminance, dither, warmth, small helpers. |
| `sky.glsl` | The sky as a function of direction; the night sky; a zenith colour inferred from the horizon for programs that do not get the sky colour. |
| `clouds.glsl` | The cloud field, the shading, and the shadow the field casts on the ground. |
| `water.glsl` | Water recognition, five-wave gravity spectrum, filtered normals, foam, and reflected sky/cloud helpers. |
| `bus.glsl` / `bus_read.glsl` | Screen-column data bus and post-effect decoding of camera, sky, fog and sun values. |

`sky.glsl`, `clouds.glsl` and `water.glsl` are shared deliberately: the shared 2D cloud mass/ridge projection also drives terrain shadows, while the
visible cloud shell adds a shallow 3D density slice; and the same sky that is drawn is
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

The sky pipeline is the first writer of a reserved one-pixel screen column. Its
10-vertex triangle fan is moved onto a 38-row strip containing a marker,
projection and the 3×3 view rotation, sky/fog colours and fog distances. The lower
horizon disc is excluded so it cannot overwrite the bus. The sun's own
`position_tex` program adds its world-space direction and rain brightness to
four more rows.

The `bus_sky` post pass decodes those values and reconstructs the sky per pixel
from the world direction. It preserves the vanilla moon, stars and sunrise glow
already drawn over the clear colour. It also replaces vanilla distance fog with
a shared sky-coloured aerial-perspective curve and a soft loaded-world edge fade.
The pass does nothing when the bus is absent, so dimensions/effects that do not
draw the sky writer retain their original scene.

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
travels with the clouds the game moves — the face orientation, and the local
vertical coordinate through each box.

The fragment shader carves the native boxes with a smooth mass and ridged detail
field, then adds a shallow 3D noise slice through the box thickness. The top,
side and underside therefore no longer share one extruded 2D silhouette. It
shades by density and orientation. Fragments below the cutoff are discarded, and
**the discard happens before every OIT branch**, so the Improved Transparency
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

The terrain pass leaves above-water colour intact for the post chain,
while underwater shading remains in the terrain pass. Water fragments on even
screen columns write position-coded markers; odd columns retain vanilla water
for refraction. The post passes decode the markers, reconstruct camera-space
positions from depth, and redraw tagged water with waves, Fresnel, screen-space
reflections, refraction, absorption and sun glint. The waves remain normal-only:
moving geometry would also move glass and ice, which share the translucent pass.

The water reflection uses the same sky gradient and cloud-density field as the
visible sky/cloud system. Screen-space rays show on-screen geometry; off-screen
rays fall back to that procedural sky, cloud deck and solar disc.

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

`assets/minecraft/post_effect/end_of_frame.json` — five ordered passes:

1. `nvs:post/bus_sky` reads the main colour and depth, reconstructs the sky,
   replaces vanilla fog with the shared aerial-perspective function, and tags
   water pixels for the next pass.
2. `nvs:post/water` reads the tagged scene, the original main image and depth.
   It reconstructs surface positions, ray-marches screen-space reflections,
   applies refraction, Fresnel, absorption, foam and solar glint.
3. `nvs:post/bloom` reads the water result and writes a fixed 480×270 target.
4. `nvs:post/composite` reads the water result and bloom target and writes a
   swap target: sharpen, bloom, highlight shoulder, contrast, saturation,
   vignette and dither.
5. `nvs:post/copy` copies the swap target back to `minecraft:main`.

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

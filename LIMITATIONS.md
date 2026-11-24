# Limitations

Every entry is something this architecture cannot do, the exact technical
reason, and the closest valid alternative that is actually implemented. Nothing
here is a guess about why it is hard: each reason names the interface that is
missing.

## 1. No refraction of the scene behind water

**What is missing.** A core shader cannot read the frame it is drawing into. Its
samplers are exactly those its pipeline binds (`Sampler0` for terrain, `Sampler2`
for the lightmap), and neither is the colour or depth of `minecraft:main`.

**Why a post effect does not solve it cheaply.** A post effect *can* read
`minecraft:main` and its depth, and that is how a loader-based shader distorts
what is under the water. To do it the post pass needs the camera: the projection,
the view rotation and a way to know which pixels are water. None of those are
given to a post pass, so they have to be smuggled through reserved screen pixels
— the "data bus" technique, which requires *every* world program to discard the
pixels in one column of the screen. That is a change to a dozen programs, a
full-resolution pass, and a screen-wide discard, on a GPU with 24 execution units
and shared memory. It is not a trade worth making for this hardware.

**Alternative used.** The surface is shaded from the water's own side instead:
Fresnel-weighted reflection of the same sky the pack draws, the cloud deck
sampled where the reflected ray crosses it, and depth-dependent absorption of
what is below. The alpha is left exactly as the game set it, so the bottom is
still visible through the surface exactly as vanilla shows it — the water reads
as water, it simply does not *bend* what is underneath.

## 2. No caustics

**What is missing.** A caustic needs the normal of the underwater surface, to
project a light pattern onto it. The terrain vertex format is `Position`, `Color`,
`UV0` and `UV2`. There is no normal.

**Why the vertex colour cannot stand in for one.** Vanilla bakes the face
direction into `Color` (up 1.0, down 0.5, north/south 0.8, east/west 0.6), but
`Color` is the *same* variable that carries the biome tint. A grey-white block and
a grass block are not separable, and reading `Color.r` as "this faces up" is wrong
for every tinted block.

**Alternative used.** None. Caustics are omitted rather than faked on the wrong
faces.

## 3. The sun's direction is not available outside the sun's own program

**What is missing.** The only place the sun's position exists is the model-view
matrix of `core/position_tex`, whose translation column is the body's position on
the celestial sphere. That program draws the sun and the moon and nothing else,
and it runs before the sky, in the same frame, with no way to hand a value to
another program.

**What that costs, precisely.**

- **Cloud shading** is a key light from above plus a thickness term, not a true
  sun-facing term. Lit tops and shaded undersides are correct; which *horizontal*
  side faces the sun is not modelled. All of the colour that changes through the
  day arrives in `CloudColor`, which the game sets.
- **The water has no discrete sun glint.** The sun's warmth does reach the
  reflection, because the reflection is built from the horizon colour, which the
  game warms at sunrise and sunset.
- **Cloud shadows on the ground are not stretched along the sun.** They sit under
  the cloud.
- **The sky has no sun-anchored scattering lobe.** What it has instead is
  vanilla's own sunrise and sunset glow, which *is* anchored to the sun by the
  game's own geometry, refined in `position_color` from a flat disc into a radial
  gradient. The horizon glow therefore points the right way without the pack
  knowing where the sun is.

**Why not derive it from `GameTime`.** `Globals.GameTime` is available, and it
wraps every 24000 ticks, so a sun angle could be computed from it. The pack does
not, deliberately: if that value is the renderer's tick counter rather than the
world's time of day, every sun-derived effect would drift out of step with the
real sun — a glow in the wrong part of the sky, which looks far worse than no
glow. Colours that the game has already resolved are used instead. Nothing in the
pack guesses the time.

## 4. No volumetric, ray-marched or layer-transported clouds

**What is missing.** A volume needs either a ray march against a density field
with a camera (a post effect needs the camera, which it is not given — see 1), or
layered geometry (there is none: the game builds one box per cloud cell).

**Alternative used.** The game's boxes are kept and carved by a density field, so
there is real geometry with real depth, lit tops, shaded undersides and torn
edges. It is a shaped volume, not a marched one.

## 5. No shadow maps, and no screen-space shadows

**What is missing.** There is no shadow pass: no depth-from-the-sun target exists
to sample. Screen-space shadows would need the camera and the depth buffer in a
post pass, which is limitation 1 again, and the technique artifacts are famous
even when it works.

**Alternative used.** The lightmap. Sunlight falls off with sky light and is
tinted by the game's own sun colour, so caves and north faces darken correctly,
and cloud shadows add large-scale variation. There are no cast shadows from
blocks, entities or the player.

## 6. Tonemapping is limited to a highlight shoulder

**What is missing.** A tone map maps a high dynamic range to a display range. The
frame `end_of_frame` receives is RGBA8: it has already been clamped by the
lighting code that wrote it. There is no HDR value left to map.

**Alternative used.** A shoulder that is exactly the identity below
`NVS_POST_SHOULDER` and compresses only above it, asymptotically approaching 1
without crossing it. Headroom is reclaimed at the top without moving the
midtones, which is what a tone map is for, minus the part that needs HDR.

## 7. Cloud shadows do not drift with the clouds

**What is missing.** The drift is `CloudInfo.CloudOffset`, which is provided to
`core/clouds` and to nothing else. Terrain cannot see how far the clouds have
moved.

**Alternative used.** The shadows use the same field, three octaves of it, at no
more than 18% darkening, anchored to the world and not animated. They read as
large soft patches of shade rather than as a hard shadow that would visibly slide
against the clouds.

## 8. Foliage wind only reaches plants the vertex data can identify

**What is identifiable.** Cutout terrain (the `ALPHA_CUTOUT` 0.5 pipeline) that is
biome-tinted (its `Color` is not grey) and whose vertices are off the block grid
(cross models are inset; full blocks are not). That is grass, ferns, flowers with
a tint, and similar.

**What is not.** Leaves are cutout but their tint is not reliably separable from
the baked face shade, so they do not move. Untinted plants — sugar cane, white
flowers — do not move. Ladders, rails, torches, panes and cobwebs are cutout and
on the grid, and are deliberately excluded; guessing would move the wrong things.

**Also:** neither end of a plant can be found, so whole plants sway rather than
bending from the base, and the movement does not affect collision or the baked
vertex lighting.

## 9. Water geometry is not displaced

**What is missing.** Water shares the translucent terrain pass with glass, ice and
stained glass, and the vertex program has no texture to tell them apart. Moving the
surface would warp every window in the world.

**Alternative used.** The waves live entirely in the normal, which is where
reflection and refraction come from anyway. The surface stays exactly where the
game put it, so there are no gaps at chunk borders and no warped glass.

## 10. World-anchored patterns lose precision very far from the origin

The cloud field, the water waves and the cloud shadows are functions of absolute
world coordinates, because a camera-relative pattern would slide as you walk. At
±100 000 blocks a 32-bit float resolves about 1/128 of a block, which is plenty.
Beyond roughly ±1 000 000 blocks the fractional resolution is coarser than the
pattern and the detail visibly degrades. This is a property of the tools, not of
the design: there is no double precision in GLSL 330.

## 11. The pack is pinned to one game version

`pack.mcmeta` declares `min_format` and `max_format` 97, and the shader files are
written against 26.3's program set, its `#include` rules and its uniform layouts.
26.1 and 26.2 reordered `Globals` and `DynamicTransforms`, and older versions
still use `#moj_import`; a replacement file written for one of them silently reads
the wrong values in 26.3. See [COMPATIBILITY.md](COMPATIBILITY.md).

## 12. Nothing is graded after the GUI

`end_of_frame` runs after the world and the hand, and before the HUD. The
composite therefore never touches the hotbar, the chat or menus. That is the
correct behaviour and worth stating plainly, because it also means a pack cannot
apply its grade to the UI.

## 13. No supersampling or MSAA under the pack's control

A resource pack cannot change the framebuffer format or the sample count. The
only antialiasing available is a filter pass, which is why FXAA ships as an
optional effect rather than being part of the default chain.

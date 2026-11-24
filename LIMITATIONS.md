# Limitations

Every entry is something this architecture cannot do, the exact technical
reason, and the closest valid alternative that is actually implemented. Nothing
here is a guess about why it is hard: each reason names the interface that is
missing.

## 1. Water depth and shoreline data are not available

**What is missing.** The depth buffer gives the visible water surface, not the
thickness of the water column or the distance to the seabed. The native terrain
inputs also do not provide a reliable shoreline mask.

**What is implemented.** A screen data bus transfers the projection, view
rotation, sky/fog values and sun direction from core shaders to post effects.
The post chain identifies water with terrain markers, reads the main depth
buffer, performs screen-space reflection (24 coarse steps plus four refinements),
and shifts the recovered water/scene colour for refraction. Rays that leave the
screen fall back to the procedural reflected sky and cloud deck.

**Remaining limits.** Screen-space reflections can only show geometry present
in the current frame; off-screen and occluded objects cannot be reflected.
Refraction uses the available screen colour and is horizontally half-resolution
because of the alternating marker layout. Clouds drawn over water can cover the
marker columns; neighbour reconstruction reduces striping but cannot restore
every hidden water tag, so reflection coverage directly beneath clouds may be
incomplete. Absorption is therefore a view-angle approximation, not true
shallow/deep-water depth. Shoreline foam is not possible without a reliable
shoreline mask.

## 2. Water markers and Improved Transparency

Water tagging currently happens in the final non-accumulation terrain colour
pass. The OIT alpha-only and accumulation variants are deliberately not allowed
to write marker colours into their intermediate buffers. This preserves the
native OIT bookkeeping, but means the post water pass may not receive complete
water tags when Improved Transparency is enabled. The upstream reference also
lists this path as untested. Runtime testing must compare water with OIT enabled
and disabled before claiming parity.

## 3. No caustics

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

## 4. Sun direction is transferred only to post effects

**What is available.** The sun's direction exists in the model-view matrix of
`core/position_tex`, whose translation column is the body's position on the
celestial sphere. The sun program writes that direction and rain brightness into
the reserved screen data bus. Post effects can therefore use it for the sky disc,
water reflection disc/corona and wave glint.

**What remains unavailable.** The core cloud and terrain programs do not receive
the decoded bus values. Cloud shading is still a key light from above plus a
thickness term, not a true sun-facing term; cloud shadows are not stretched along
the sun. The water post pass can use the sun direction, but the cloud field's
`CloudOffset` is only provided to `core/clouds`, so reflected clouds do not
share the exact moving offset of the visible cloud geometry.

**Why not derive it from `GameTime`.** The renderer's tick counter is not a
safe substitute for the actual celestial transform; deriving the sun from it
could drift out of step with the game's real sun. The data bus uses the actual
matrix instead.

## 5. No volumetric, ray-marched or layer-transported clouds

**What is missing.** The visible native cloud boxes now use a shallow 3D density
field through their thickness, so the top, side and underside no longer share one
extruded 2D silhouette. This is still not a true ray-marched volume: the game
supplies one box per cloud cell, and a full-screen cloud march would add a large
cost on the target integrated GPU.

**Alternative used.** The game's boxes are kept and carved by a density field, so
there is real geometry with real depth, lit tops, shaded undersides and torn
edges. It is a shaped volume, not a marched one.

## 6. No shadow maps

**What is missing.** There is no shadow pass and no depth-from-the-sun target.
Screen-space shadows are technically possible now that the data bus supplies the
camera and the post chain reads depth, but they are not implemented: they can
produce severe screen-edge and disocclusion artifacts, and add another costly
full-screen ray-march on the target integrated GPU.

**Alternative used.** The lightmap. Sunlight falls off with sky light and is
tinted by the game's own sun colour, so caves and north faces darken correctly,
and cloud shadows add large-scale variation. There are no cast shadows from
blocks, entities or the player.

## 7. Tonemapping is limited to a highlight shoulder

**What is missing.** A tone map maps a high dynamic range to a display range. The
frame `end_of_frame` receives is RGBA8: it has already been clamped by the
lighting code that wrote it. There is no HDR value left to map.

**Alternative used.** A shoulder that is exactly the identity below
`NVS_POST_SHOULDER` and compresses only above it, asymptotically approaching 1
without crossing it. Headroom is reclaimed at the top without moving the
midtones, which is what a tone map is for, minus the part that needs HDR.

## 8. Cloud shadows do not drift with the clouds

**What is missing.** The drift is `CloudInfo.CloudOffset`, which is provided to
`core/clouds` and to nothing else. Terrain cannot see how far the clouds have
moved.

**Alternative used.** The shadows use the shared 2D mass/ridge projection of the
cloud field at three octaves, with no more than 18% darkening. The visible cloud
shell adds a shallow 3D vertical density slice, which is not part of the ground
shadow projection. Shadows remain world-anchored and do not drift with the clouds. They read as
large soft patches of shade rather than as a hard shadow that would visibly slide
against the clouds.

## 9. Foliage wind only reaches plants the vertex data can identify

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

## 10. Water geometry is not displaced

**What is missing.** Water shares the translucent terrain pass with glass, ice and
stained glass, and the vertex program has no texture to tell them apart. Moving the
surface would warp every window in the world.

**Alternative used.** The waves live entirely in the normal, which is where
reflection and refraction come from anyway. The surface stays exactly where the
game put it, so there are no gaps at chunk borders and no warped glass.

## 11. World-anchored patterns lose precision very far from the origin

The cloud field, the water waves and the cloud shadows are functions of absolute
world coordinates, because a camera-relative pattern would slide as you walk. At
±100 000 blocks a 32-bit float resolves about 1/128 of a block, which is plenty.
Beyond roughly ±1 000 000 blocks the fractional resolution is coarser than the
pattern and the detail visibly degrades. This is a property of the tools, not of
the design: there is no double precision in GLSL 330.

## 12. The pack is pinned to one game version

`pack.mcmeta` declares `min_format` and `max_format` 97, and the shader files are
written against 26.3's program set, its `#include` rules and its uniform layouts.
26.1 and 26.2 reordered `Globals` and `DynamicTransforms`, and older versions
still use `#moj_import`; a replacement file written for one of them silently reads
the wrong values in 26.3. See [COMPATIBILITY.md](COMPATIBILITY.md).

## 13. Nothing is graded after the GUI

`end_of_frame` runs after the world and the hand, and before the HUD. The
composite therefore never touches the hotbar, the chat or menus. That is the
correct behaviour and worth stating plainly, because it also means a pack cannot
apply its grade to the UI.

## 14. No supersampling or MSAA under the pack's control

A resource pack cannot change the framebuffer format or the sample count. The
only antialiasing available is a filter pass, which is why FXAA ships as an
optional effect rather than being part of the default chain.

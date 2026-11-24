# Feature matrix

Statuses used below:

- **Done** — implemented in the native architecture, using game-supplied inputs.
- **Approximated** — implemented, but with a documented deviation from what a
  loader-based shader would do, because a required input is not available. The
  reason is in [LIMITATIONS.md](LIMITATIONS.md).
- **Not possible** — the architecture cannot do it. The exact reason and the
  closest valid alternative are in [LIMITATIONS.md](LIMITATIONS.md).
- **Untested** — implemented and statically checked, but whether it *looks*
  right needs the game. Everything below is in this position at the code level;
  see [TESTING.md](TESTING.md).

## 1. Sky and celestial

| Feature | Status | Where |
|---|---|---|
| Natural graded daytime sky | Done | `bus_sky.fsh` reconstructs the sky with `nvs_skyGradient` from `sky.glsl`, using the game's sky and fog colours |
| Atmospheric-looking horizon | Done | `NVS_SKY_HAZE_POWER` curve in `sky.glsl`; converges exactly on `FogColor` at the rim |
| No flat gradient | Done | elevation curve, plus a 4×4 ordered dither against 8-bit banding |
| No hard horizon edge | Done | the post atmosphere pass blends distant terrain toward the same sky/fog gradient |
| No banding | Done | `nvs_dither` in `bus_sky.fsh` and again in the post composite |
| Sunrise / sunset colour transitions | Done | a warm band whose strength follows how warm `FogColor` already is, so noon is untouched and dusk is deepened |
| Sun-anchored sunrise glow | Done | `position_color.vsh/.fsh` give vanilla's 18-vertex glow fan a radial gradient instead of one flat colour |
| Sun disc with halo | Done | the sun direction is transferred from `position_tex` through the bus; `bus_sky.fsh` draws the disc/corona and `water.fsh` adds the reflected disc/glint |
| Moon | Done | untouched body, plus a cool corona from the same program |
| Moonlight | Done | `lightmap.fsh` — `SkyLightColor` is what the game sets for the moon |
| Stars with natural distribution | Done | a procedural field in `sky.glsl`/`bus_sky.fsh` with per-star magnitude and colour temperature, plus per-star tint on the game's own star points in `stars.fsh` |
| Night sky with nebula-like depth | Done | fractal nebula, concentrated along a galactic band, gated on how dark the game's sky colour is |
| Weather-driven sky change | Done | inherits `ColorModulator` and `FogColor`, which the game already darkens with rain; rain also fades the sun corona through `ColorModulator.a` |
| Dimension-specific sky | Done | emerges from the colours the game supplies per dimension; the pack never branches on dimension |
| Sky hidden under blindness / underwater | Preserved when the bus is present; otherwise vanilla scene is left alone | the post reconstruction only runs when the sky writer supplied a valid bus |

## 2. Clouds

| Feature | Status | Where |
|---|---|---|
| Procedural multiscale cloud shapes | Done | `nvs_cloudField`: a smooth mass plus a ridged detail channel |
| Depth from native cloud geometry | Done | the game's cloud boxes are kept; density and face orientation shade their top, underside and sides |
| Cumulus and wispy forms | Done | the two channels, mixed; `NVS_CLOUD_CUTOFF` controls how much is torn away |
| Motion | Done | `CloudOffset` is already inside the cloud position, so the field travels with the clouds |
| Altitude and scale | Done | `NVS_CLOUD_SCALE`, `NVS_CLOUD_HEIGHT` |
| Sun-facing illumination and shading | Approximated | lit tops, shaded undersides and darker creases, from face orientation and density. The clouds program is not given the sun's direction, so this is a key light from above, not a true sun-facing term |
| Sunset / night / rain appearance | Done | all of it arrives in `CloudColor`, set by the game |
| Cloud shadows on terrain | Approximated | the same field, three octaves, at up to 18% darkening, weighted by how lit the pixel already is. Soft and world-anchored, not stretched along the sun |
| No obvious tiling | Done | no texture and no lookup table; octaves are rotated before they are scaled |
| Works with Fast clouds | Degrades | the flat cloud layer gets the same field and shading, with no volume to shade |

## 3. Water

| Feature | Status | Where |
|---|---|---|
| Not a tinted flat surface | Done | wave normals, Fresnel and a reflected sky replace the flat tint |
| Animated multi-scale waves with wave normals | Done | five directional components, position-only domain warp, screen-footprint filtering and a looping ripple, in `water.glsl` |
| Fresnel reflection of the sky | Done | Schlick with water's `F0`; post pass uses the exact bus sky/fog colours and procedural sky gradient |
| Fresnel reflection of clouds | Approximated | reflected ray intersects a fixed cloud deck and samples the shared procedural cloud field; cloud drift offset is not available in post |
| Screen-space reflections | Done, untested | 24 coarse ray steps plus four refinements against the main depth buffer; off-screen rays fall back to sky |
| Reflection of the sun | Done, untested | sun direction and rain brightness are transferred through the data bus; reflected disc, corona and wave glint are added |
| Depth-dependent colour (shallow / deep) | Approximated | light from below is absorbed over the path length through the water, red first. The true depth of the water column is not available |
| Underwater appearance | Done | the surface is desaturated and tinted when the camera is submerged |
| Underwater fog | Done | the game's own water fog, with the pack's softer fog curve |
| Screen-space refraction | Approximated, untested | post pass shifts the recovered vanilla water/scene sample using wave normals; half-resolution horizontal marker layout limits detail |
| Shoreline transitions | Approximated | no hard edge, because the surface stays translucent over the bottom and the absorption is continuous; there is no shoreline mask to make foam at the sand |
| Foam | Done, untested | whitecaps follow the filtered wave-height sum and a looping breakup field; no shoreline foam without a shoreline mask |
| Caustics | **Not possible** | needs the surface normal of the underwater block, which the terrain vertex format does not carry; the cardinal shade in the vertex colour is confounded with the biome tint |

## 4. Lighting

| Feature | Status | Where |
|---|---|---|
| Sun angle-dependent sunlight | Done | `LightmapInfo.SkyLightColor`, which the game sets from the celestial angle, is the light colour |
| Moonlight | Done | the same channel at night |
| Day / night transitions | Done | inherits the game's transitions; the pack only reshapes the response |
| Ambient light | Done | `AmbientColor`, kept, with a small lift so blacks do not crush |
| Block light | Done | `BlockLightTint`, with a longer-reaching curve and more of its warmth kept |
| Cave response | Done | a slightly faster sky-light falloff, plus the ambient lift fading out as soon as anything is lit |
| Coherent exposure and contrast | Done | lightmap curves plus the post highlight shoulder, which leaves everything below `NVS_POST_SHOULDER` untouched |
| Neither crushed nor washed out | Done | the shoulder compresses only the top end; the lift is 0.004 and fades out by luminance 0.30 |
| Gamma / brightness option still works | Preserved | `BrightnessFactor` still drives the blend, at `NVS_GAMMA_STRENGTH` of its strength (0.85; set to 1.0 for vanilla's response) |

## 5. Materials and foliage

| Feature | Status | Where |
|---|---|---|
| Water material | Done | see section 3 |
| Foliage wind | Done | cutout terrain that is biome-tinted and off the block grid — the three properties the native vertex data actually supplies |
| Wind on leaves, sugar cane, untinted flowers | **Not possible** | leaves are cutout but their tint is not reliably distinguishable from the cardinal face shade; sugar cane and white flowers are untinted, so the test cannot see them. Deliberately not guessed: a wrong guess would sway fences and ladders |
| No invented material inputs | Enforced | nothing is inferred from texture atlas position, block id, or a `block.properties` file (which is a loader feature and does not exist here) |

## 6. Weather and fog

| Feature | Status | Where |
|---|---|---|
| Rain and storm ambience | Done | the game darkens `FogColor`, `ColorModulator` and `CloudColor` in rain; the pack also fades the sun corona by the rain brightness |
| Fog distance | Preserved | the game's distances are kept exactly |
| Fog density curve | Done | smoothstep instead of linear, so fog fades in rather than starting at a line |
| Fog colour | Preserved | `FogColor` untouched |
| Water fog | Done | vanilla's, with the softer curve |
| Cave fog | Done | dark through the lightmap, not through fog |
| Nether atmosphere | Done | from the Nether's own fog, sky and light colours, plus its block light tint |
| End atmosphere | Done | from the End's own colours; the End sky uses a different pipeline and is untouched |

## 7. Post-processing

| Feature | Status | Where |
|---|---|---|
| Bloom | Done | `nvs:post/bloom`, fixed 480×270 target, plus composite |
| Colour grading | Done | contrast, saturation and a shoulder in `nvs:post/composite` |
| Sharpen | Done | 4-neighbour Laplacian, `NVS_POST_SHARPEN` |
| Vignette | Done | in the composite, so it costs no extra pass |
| Antialiasing | Done, optional | `nvs:post_effect/fxaa.json`, applied with `/posteffect add @s nvs:fxaa` |
| Tonemapping | Approximated | the frame is 8-bit, so there is no HDR to map. The highlight shoulder is the closest valid equivalent: identity below the knee, compression above it. See LIMITATIONS.md |
| Depth-aware post effects | Done | the screen data bus carries projection, view rotation, sky/fog parameters and sun data; the water pass reads the main depth buffer |
| Applies before the GUI | Done | `end_of_frame` runs after the world and the hand, before the HUD |

## 8. Special effects and performance

| Feature | Status | Where |
|---|---|---|
| End portal | Preserved | vanilla portal shader retained with the reserved bus-column guard |
| Beacon beam | Preserved | vanilla beacon shader retained with the reserved bus-column guard |
| Lightning | Preserved | vanilla lightning shader retained with the reserved bus-column guard |
| Item and entity glint | Preserved | vanilla glint paths retained with the reserved bus-column guard |
| Emissive entity paths | Preserved | vanilla emissive entity paths retained with the reserved bus-column guard |
| Improved Transparency (OIT) | Pipeline-preserved; water SSR unverified | native OIT branches remain intact, but the water marker is written only in the final non-accumulation terrain pass; test water with OIT both on and off |
| Quality tiers | Done, as documented switches | `config.glsl` defines, plus deleting one JSON to remove all post-processing. Vanilla has no shader options menu |
| Performance on Intel HD 5500 class hardware | Untested | 24+4 SSR budget, reduced cloud-shadow octaves and fixed 480×270 bloom target; runtime frame time still needs measurement |

## What is deliberately not there

No `shaders.properties`, no `gbuffers_*`, no colortex or buffer declarations, no
shadow map, no loader macros, no per-dimension `world0`/`world1`/`world-1`
folders, no `block.properties`, `entity.properties` or `item.properties`. None of
these exist in vanilla, and `tools/check_pack.py` fails the build if one appears.

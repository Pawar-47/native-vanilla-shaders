#ifndef NVS_CONFIG_GLSL
#define NVS_CONFIG_GLSL

// Native Vanilla Shaders (NVS) - tunables.
//
// This pack has no options menu, because 26.3 has no shader options screen for
// resource packs. These #defines are the options: every one is guarded with
// #ifndef, so you can also override them by editing this one file. Nothing here
// changes the pack's interfaces, so any value compiles.
//
// The defaults are tuned for a low-end integrated GPU (Intel HD Graphics 5500
// class: 24 EUs, shared DDR3 memory). Raise them if you have headroom.

// ---------------------------------------------------------------- sky ------
// How quickly the sky goes from the horizon colour to the zenith colour.
// 1.0 = linear, higher = the horizon band stays thinner.
#ifndef NVS_SKY_HAZE_POWER
#define NVS_SKY_HAZE_POWER 2.6
#endif
// Sunrise and sunset: how strongly the low sky is warmed, 0 disables.
#ifndef NVS_SKY_WARM_STRENGTH
#define NVS_SKY_WARM_STRENGTH 0.55
#endif
// Night sky detail. 0 turns the procedural night sky off entirely.
#ifndef NVS_NIGHT_STRENGTH
#define NVS_NIGHT_STRENGTH 1.0
#endif
// Nebula noise octaves. 3 is the low-end default, 5 is richer and slower.
#ifndef NVS_NEBULA_OCTAVES
#define NVS_NEBULA_OCTAVES 3
#endif

// ------------------------------------------------------------- clouds ------
// Cloud field octaves. 4 gives multiscale cumulus detail; 3 is cheaper, 5 is
// smoother and slower. This also drives the cloud shadows on the terrain.
#ifndef NVS_CLOUD_OCTAVES
#define NVS_CLOUD_OCTAVES 3
#endif
 // Vertical detail is limited to two 3D octaves: clouds cover little screen
// area, but this keeps the extra volume breakup affordable on integrated GPUs.
#ifndef NVS_CLOUD_VOLUME_OCTAVES
#define NVS_CLOUD_VOLUME_OCTAVES 1
#endif
#ifndef NVS_CLOUD_VOLUME_STRENGTH
#define NVS_CLOUD_VOLUME_STRENGTH 0.16
#endif
// Reflected clouds use a reduced octave budget because they are evaluated in
// the full-resolution water post pass on the integrated-GPU target.
#ifndef NVS_CLOUD_REFLECTION_OCTAVES
#define NVS_CLOUD_REFLECTION_OCTAVES 2
#endif
#ifndef NVS_CLOUD_REFLECTION_DETAIL_OCTAVES
#define NVS_CLOUD_REFLECTION_DETAIL_OCTAVES 1
#endif
// World-space size of the largest cloud feature, in blocks.
#ifndef NVS_CLOUD_SCALE
#define NVS_CLOUD_SCALE 76.0
#endif
// Fragments whose cloud density is below this are discarded, which is what
// gives the shapes their wispy, non-tiled edges. Raise for thinner clouds.
#ifndef NVS_CLOUD_CUTOFF
#define NVS_CLOUD_CUTOFF 0.30
#endif
// How dark the shaded underside of a cloud gets, 1.0 = flat.
#ifndef NVS_CLOUD_SHADE
#define NVS_CLOUD_SHADE 0.55
#endif
// Depth of the cloud shadows on the ground, 0 = none, 0.18 = 18% darkening.
#ifndef NVS_CLOUD_SHADOW_STRENGTH
#define NVS_CLOUD_SHADOW_STRENGTH 0.12
#endif
// Cloud-shadow octave budget. Keep below visible-cloud quality to limit
// per-fragment cost across large terrain surfaces.
#ifndef NVS_CLOUD_SHADOW_OCTAVES
#define NVS_CLOUD_SHADOW_OCTAVES 2
#endif
#ifndef NVS_CLOUD_SHADOW_DETAIL_OCTAVES
#define NVS_CLOUD_SHADOW_DETAIL_OCTAVES 1
#endif
// Density threshold and penumbra width for ground cloud shadows.
#ifndef NVS_CLOUD_SHADOW_THRESHOLD
#define NVS_CLOUD_SHADOW_THRESHOLD 0.30
#endif
#ifndef NVS_CLOUD_SHADOW_SOFTNESS
#define NVS_CLOUD_SHADOW_SOFTNESS 0.46
#endif
// Height of the cloud layer, in blocks, as used for the shadow gradient.
#ifndef NVS_CLOUD_HEIGHT
#define NVS_CLOUD_HEIGHT 192.0
#endif

// -------------------------------------------------------------- water ------
// Overall wave slope. 0 = mirror, 1 = noticeably choppy.
#ifndef NVS_WATER_WAVE_STRENGTH
#define NVS_WATER_WAVE_STRENGTH 0.60
#endif
// Extra small-scale ripple on top of the eight-wave gravity spectrum.
#ifndef NVS_WATER_RIPPLE
#define NVS_WATER_RIPPLE 0.35
#endif
// How much water absorbs the scene underneath, per block of path length.
#ifndef NVS_WATER_ABSORB
#define NVS_WATER_ABSORB 0.022
#endif
// Fresnel floor: the reflectance of water seen straight down.
#ifndef NVS_WATER_F0
#define NVS_WATER_F0 0.02
#endif
// Wave-driven shift of the reflected image, in screen UV units per unit of tilt.
#ifndef NVS_WATER_REFLECTION_RIPPLE
#define NVS_WATER_REFLECTION_RIPPLE 0.04
#endif
// Refraction shift of the vanilla water/scene sample.
#ifndef NVS_WATER_REFRACTION_STRENGTH
#define NVS_WATER_REFRACTION_STRENGTH 0.03
#endif
// Brightness of the whitecaps on wave crests, 0 turns them off.
#ifndef NVS_WATER_FOAM
#define NVS_WATER_FOAM 0.07
#endif
// Flatten the wave spectrum with camera distance, as the projected wave
// height becomes less visible; the per-wave footprint filter handles aliasing.
#ifndef NVS_WATER_FLATTEN_DISTANCE
#define NVS_WATER_FLATTEN_DISTANCE 48.0
#endif
// Normalised wave-height threshold for whitecap foam.
#ifndef NVS_WATER_FOAM_THRESHOLD
#define NVS_WATER_FOAM_THRESHOLD 0.72
#endif
// Screen-space reflection ray budget. 24 coarse steps plus four refinements
// keeps the water pass viable on Intel HD 5500-class integrated graphics.
#ifndef NVS_WATER_SSR_STEPS
#define NVS_WATER_SSR_STEPS 24
#endif
#ifndef NVS_WATER_SSR_REFINE_STEPS
#define NVS_WATER_SSR_REFINE_STEPS 4
#endif
// Growth of each screen-space ray step. 1.13 extends the 24-step low-end
// budget across useful lake distances without doubling the sample count.
#ifndef NVS_WATER_SSR_STEP_GROWTH
#define NVS_WATER_SSR_STEP_GROWTH 1.13
#endif
// Additional aerial perspective beyond the game's vanilla fog start/end.
#ifndef NVS_ATMOSPHERE_HAZE_DISTANCE
#define NVS_ATMOSPHERE_HAZE_DISTANCE 900.0
#endif

// ------------------------------------------------------------- lighting ----
// Extra shaping of the vanilla lightmap. 1.0 leaves vanilla's curve alone.
#ifndef NVS_SKYLIGHT_CURVE
#define NVS_SKYLIGHT_CURVE 0.92
#endif
#ifndef NVS_BLOCKLIGHT_CURVE
#define NVS_BLOCKLIGHT_CURVE 0.92
#endif
// Ambient lift that keeps caves and nights from crushing to pure black.
#ifndef NVS_BLACK_LIFT
#define NVS_BLACK_LIFT 0.004
#endif
// How much of vanilla's "notGamma" curve is kept, 0 = linear, 1 = vanilla.
#ifndef NVS_GAMMA_STRENGTH
#define NVS_GAMMA_STRENGTH 0.85
#endif

// ------------------------------------------------------------- post --------
// These are compile-time only in the sense that they affect the post programs;
// they are constants in the shader, not in the JSON, so they need no rebuild.
#ifndef NVS_POST_BLOOM
#define NVS_POST_BLOOM 0.38
#endif
#ifndef NVS_POST_EXPOSURE
#define NVS_POST_EXPOSURE 1.03
#endif
#ifndef NVS_POST_CONTRAST
#define NVS_POST_CONTRAST 0.17
#endif
#ifndef NVS_POST_SATURATION
#define NVS_POST_SATURATION 1.08
#endif
#ifndef NVS_POST_VIGNETTE
#define NVS_POST_VIGNETTE 0.10
#endif
#ifndef NVS_POST_SHARPEN
#define NVS_POST_SHARPEN 0.18
#endif
// Luminance above which the highlight shoulder starts compressing.
#ifndef NVS_POST_SHOULDER
#define NVS_POST_SHOULDER 0.72
#endif

// ------------------------------------------------------------- plants ------
// Sway of cutout plants. Only plants that the native vertex data can actually
// identify are moved (see ARCHITECTURE.md); 0 disables it.
#ifndef NVS_PLANT_SWAY
#define NVS_PLANT_SWAY 0.055
#endif

#endif

#ifndef NVS_CLOUDS_GLSL
#define NVS_CLOUDS_GLSL

#include <nvs:config.glsl>
#include <nvs:noise.glsl>

// The cloud field.
//
// This one function is the whole system: `core/clouds` uses it to carve and
// shade the cloud volume, and `core/terrain` uses it for the cloud shadows on
// the ground. Because both read the same field, the shadows sit under the same
// shapes that cast them.
//
// It is taken in world-space XZ so it is anchored to the world, not to the
// camera or the screen. Two channels are summed: a large smooth mass, which
// gives the cumulus blocks, and a ridged detail, which gives the torn, wispy
// edges. Nothing repeats: there is no texture and no lookup table.

// Scattered cloud masses use warped multi-scale noise, not a grid of equal
// circles. A low-frequency coverage field breaks the sky into separate banks;
// the higher-frequency billows make each bank asymmetric and softly ragged.
float nvs_cloudLayerDensity(vec2 worldXZ, float scale, vec2 seed) {
    vec2 p = worldXZ / max(scale, 1.0);
    vec2 warp = vec2(
        nvs_valueNoise(p * 0.43 + seed + vec2(7.1, 2.8)),
        nvs_valueNoise(p * 0.43 + seed + vec2(19.7, 13.4))
    ) - 0.5;
    p += warp * 1.35;

    float broad = nvs_fbm(p * 0.72 + seed, 2);
    float billow = nvs_fbm(p * 1.55 + seed * 1.7 + vec2(5.3, 21.8), 2);
    float ragged = nvs_fbmRidged(p * 2.65 + seed + vec2(29.1, 4.6), 2);
    float bank = nvs_fbm(p * 0.24 + seed * 0.31 + vec2(41.0, 9.0), 2);
    float mass = broad * 0.57 + billow * 0.25 + ragged * 0.10 + bank * 0.08;
    float separation = smoothstep(0.39, 0.66, bank);
    return clamp(mass * mix(0.30, 1.0, separation), 0.0, 1.0);
}

// The shared near-layer field is also used by water reflections.
float nvs_cloudPuffDensity(vec2 worldXZ) {
    return nvs_cloudLayerDensity(worldXZ, NVS_CLOUD_SCALE, vec2(0.0));
}

// Shared density function. Visible clouds use the configured detail level;
// terrain shadows use fewer octaves for the integrated-GPU target, but retain
// exactly the same mass/detail shaping so the silhouettes stay related.
float nvs_cloudDensity(vec2 worldXZ, int massOctaves, int detailOctaves) {
    vec2 p = worldXZ / NVS_CLOUD_SCALE;
    // Low-frequency domain warp bends the native cell grid into broad,
    // irregular cloud masses instead of repeating rounded box silhouettes.
    vec2 warp = vec2(
        nvs_valueNoise(p * 0.42 + vec2(8.2, 1.7)),
        nvs_valueNoise(p * 0.42 + vec2(19.4, 5.3))
    ) - 0.5;
    p += warp * 0.62;
    float mass = nvs_fbm(p, massOctaves);
    float wisp = nvs_fbmRidged(p * 2.35 + vec2(11.0, 3.0), detailOctaves);
    float d = (mass - 0.5) * 1.55 + 0.5;
    d = mix(d, d * 0.72 + wisp * 0.42, 0.45);
    return clamp(d, 0.0, 1.0);
}

float nvs_cloudField(vec2 worldXZ) {
    return nvs_cloudPuffDensity(worldXZ);
}

// Visible cloud fragments use a shallow 3D field. The native cloud mesh is a
// thin box layer; sampling an independent vertical noise slice gives its top,
// sides and underside different billows instead of extruding the same flat
// silhouette through the whole volume. Ground shadows and reflected-sky
// fallback keep the cheaper 2D projection of this field.
float nvs_cloudVolumeField(vec2 worldXZ, float heightFraction, float baseDensity) {
    vec2 p = worldXZ / NVS_CLOUD_SCALE;
    float vertical = clamp(heightFraction, 0.0, 1.0);
    float volume = nvs_fbm3(vec3(p * 2.1 + vec2(7.3, 11.9), vertical * 2.0 + 0.17),
                            NVS_CLOUD_VOLUME_OCTAVES);
    float verticalProfile = 0.94 + 0.06 * sin(vertical * 3.14159265);
    float density = baseDensity + (volume - 0.5) * NVS_CLOUD_VOLUME_STRENGTH;
    return clamp(density * verticalProfile, 0.0, 1.0);
}

float nvs_cloudVolumeField(vec2 worldXZ, float heightFraction) {
    return nvs_cloudVolumeField(worldXZ, heightFraction, nvs_cloudField(worldXZ));
}

// Vertical shading. `upward` is 1 for a top face, 0 for a bottom face.
//
// The game does not give the clouds program the sun's direction, so this cannot
// be a real sun-facing term. It is a key light from above plus a thickness
// term, which is enough for the volume to read: lit tops, shaded undersides,
// darker creases. All of the time-of-day colour (noon white, sunset orange,
// night blue, rain grey) arrives separately in CloudInfo.CloudColor, set by the
// game, which is why this stays correct at every hour.
float nvs_cloudShade(float density, float upward) {
    float face = clamp(upward, 0.0, 1.0);
    // Lift the underside substantially: the previous 0.45-ish multiplier
    // crushed Minecraft's already subdued CloudColor into charcoal/black.
    // A warm key on upper lobes and a cool ambient fill give the puffs depth.
    float ambient = mix(0.78, 1.18, face);
    float fullness = mix(0.94, 1.08, smoothstep(0.30, 0.90, density));
    float core = smoothstep(0.55, 0.96, density) * (1.0 - face) * 0.035;
    float edge = (1.0 - smoothstep(NVS_CLOUD_CUTOFF, NVS_CLOUD_CUTOFF + 0.30, density))
               * smoothstep(0.08, 0.82, face) * 0.045;
    return max(ambient * fullness - core, 0.0) + edge;
}

// How much a ground fragment at this world XZ is shaded by the cloud above it.
// 1.0 = full sun.
//
// This runs on every lit terrain fragment, so it uses a reduced mass/detail
// octave budget. The shared density function keeps its shaping consistent with
// the visible cloud volume while the lower frequency count limits GPU cost.
float nvs_cloudShadow(vec2 worldXZ) {
    float density = nvs_cloudDensity(worldXZ,
                                      NVS_CLOUD_SHADOW_OCTAVES,
                                      NVS_CLOUD_SHADOW_DETAIL_OCTAVES);
    float cover = smoothstep(NVS_CLOUD_SHADOW_THRESHOLD,
                             NVS_CLOUD_SHADOW_THRESHOLD + NVS_CLOUD_SHADOW_SOFTNESS,
                             density);
    return 1.0 - cover * NVS_CLOUD_SHADOW_STRENGTH;
}

#endif

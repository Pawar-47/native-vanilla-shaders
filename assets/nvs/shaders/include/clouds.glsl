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

// Stylised cloud silhouettes: jittered rounded lobes form broad, connected
// cumulus masses. The native game mesh is still the carrier, but this field
// replaces its box-like cell mask with soft, scalloped cartoon contours.
float nvs_cloudPuffDensity(vec2 worldXZ) {
    vec2 p = worldXZ / (NVS_CLOUD_SCALE * 0.38);
    float lobes = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec2 cell = floor(p) + vec2(float(x), float(y));
            vec2 jitter = vec2(
                nvs_hash12(cell + vec2(13.1, 7.7)),
                nvs_hash12(cell + vec2(41.3, 19.9))
            ) - 0.5;
            jitter *= 0.34;
            vec2 local = p - cell - 0.5 - jitter;
            float radius = mix(0.48, 0.76, nvs_hash12(cell + 23.7));
            float lobe = 1.0 - smoothstep(radius - 0.18, radius + 0.08, length(local));
            lobes = max(lobes, lobe);
        }
    }
    float broad = nvs_fbm(p * 0.31 + vec2(4.7, 8.2), 2);
    float cluster = smoothstep(0.20, 0.72, broad);
    float softMass = lobes * mix(0.78, 1.0, cluster);
    // A restrained low-frequency modulation prevents a repeated bead pattern
    // while preserving the clean, rounded silhouette of each cumulus lobe.
    float billow = nvs_fbm(p * 0.72 + vec2(17.0, 3.0), 2);
    return clamp(softMass * mix(0.94, 1.06, billow), 0.0, 1.0);
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
    return nvs_cloudDensity(worldXZ, NVS_CLOUD_OCTAVES, max(NVS_CLOUD_OCTAVES - 1, 1));
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

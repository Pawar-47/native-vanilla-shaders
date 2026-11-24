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

float nvs_cloudField(vec2 worldXZ) {
    vec2 p = worldXZ / NVS_CLOUD_SCALE;

    float mass = nvs_fbm(p, NVS_CLOUD_OCTAVES);
    float wisp = nvs_fbmRidged(p * 2.6 + vec2(11.0, 3.0), NVS_CLOUD_OCTAVES - 1);

    // Centre the mass on 0.5 and open its contrast, so that a cutoff carves
    // recognisable shapes instead of nibbling at a flat grey.
    float d = (mass - 0.5) * 1.55 + 0.5;

    // Pull the detail into the mass: dense areas stay dense, thin areas tear.
    d = mix(d, d * 0.72 + wisp * 0.42, 0.45);

    return clamp(d, 0.0, 1.0);
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
    float form = mix(1.0 - NVS_CLOUD_SHADE, 1.05, face);
    float thickness = mix(0.80, 1.14, smoothstep(0.30, 0.88, density));

    // Dense cloud cores absorb more skylight on their undersides, while thin
    // upper edges scatter a little extra light. This adds volume without a
    // guessed sun vector: 26.3's CloudColor still supplies the real day,
    // sunset, night and weather tint.
    float core = smoothstep(0.48, 0.92, density) * (1.0 - face) * 0.14;
    float edge = (1.0 - smoothstep(NVS_CLOUD_CUTOFF, NVS_CLOUD_CUTOFF + 0.34, density))
               * smoothstep(0.08, 0.82, face) * 0.11;

    return max(form * thickness - core, 0.0) + edge;
}

// How much a ground fragment at this world XZ is shaded by the cloud above it.
// 1.0 = full sun.
//
// This runs on every lit terrain fragment, so it uses three octaves of the mass
// channel only. The shadow is soft enough that the detail it drops is invisible,
// and the shape it keeps is the same one `core/clouds` carves with.
float nvs_cloudShadow(vec2 worldXZ) {
    vec2 p = worldXZ / NVS_CLOUD_SCALE;
    float d = (nvs_fbm(p, 3) - 0.5) * 1.55 + 0.5;
    float cover = smoothstep(0.32, 0.78, d);
    return 1.0 - cover * NVS_CLOUD_SHADOW_STRENGTH;
}

#endif

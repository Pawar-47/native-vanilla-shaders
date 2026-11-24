#ifndef NVS_COMMON_GLSL
#define NVS_COMMON_GLSL

#include <nvs:config.glsl>
#include <nvs:noise.glsl>

const float NVS_PI = 3.14159265358979;

float nvs_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float nvs_max3(vec3 v) {
    return max(v.x, max(v.y, v.z));
}

float nvs_min3(vec3 v) {
    return min(v.x, min(v.y, v.z));
}

// How warm a colour already is, 0 for blue/grey, ~1 for strong orange.
// Used to let vanilla's own sunrise/sunset colours drive the pack's warmth
// instead of guessing the time of day.
float nvs_warmth(vec3 c) {
    return clamp((c.r - c.b) / max(nvs_max3(c), 0.02), 0.0, 1.0);
}

// Ordered 4x4 dither in [0, 1). Pure arithmetic, no lookup table, so it costs
// a few ALU and cannot upset a compiler.
float nvs_bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float nvs_bayer4(vec2 a) {
    return nvs_bayer2(a * 0.5) * 0.25 + nvs_bayer2(a);
}

// Dither offset in units of one 8-bit step. The frame target is RGBA8, so a
// smooth gradient across ~100 levels would band without this.
float nvs_dither(vec2 fragCoord) {
    return (nvs_bayer4(fragCoord) - 0.5) / 255.0;
}

// The dimension is not branched on anywhere in this pack. 26.3 hands every
// program the dimension's colours already (the sky's ColorModulator, FogColor,
// the lightmap's SkyLightColor and BlockLightTint), so the pack shapes those
// rather than trying to identify a dimension it cannot see.
//
// Camera height above sea level, in blocks, for the faint altitude response of
// the sky and the fog.
float nvs_altitude(float cameraY) {
    return clamp((cameraY - 63.0) / 160.0, -0.5, 1.0);
}

#endif

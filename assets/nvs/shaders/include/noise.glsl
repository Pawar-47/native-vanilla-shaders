#ifndef NVS_NOISE_GLSL
#define NVS_NOISE_GLSL

// Hash and noise used by the sky, the clouds and the water.
//
// Everything is procedural: the pack ships no textures and no noise images, so
// there is nothing to tile and nothing to credit to a third party. The cost is
// ALU only, which is the cheap resource on the target hardware.

float nvs_hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float nvs_hash13(vec3 p) {
    vec3 p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise in [0, 1].
float nvs_valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = nvs_hash12(i);
    float b = nvs_hash12(i + vec2(1.0, 0.0));
    float c = nvs_hash12(i + vec2(0.0, 1.0));
    float d = nvs_hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal sum of value noise, normalised to [0, 1].
//
// Each octave is rotated before it is scaled, so the octaves do not line up on
// the axes and no grid or tiling is visible at any zoom level.
float nvs_fbm(vec2 p, int octaves) {
    const mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        sum += amp * nvs_valueNoise(p);
        norm += amp;
        p = rot * p * 2.03 + vec2(17.0, 9.0);
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

// Ridged variant: creases instead of blobs, for the wispy cloud forms.
float nvs_fbmRidged(vec2 p, int octaves) {
    const mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        float n = nvs_valueNoise(p);
        n = 1.0 - abs(n * 2.0 - 1.0);
        sum += amp * n * n;
        norm += amp;
        p = rot * p * 2.03 + vec2(31.0, 5.0);
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

 // Smooth trilinear value noise in [0, 1], used to give the cloud shell
// independent structure through its thickness instead of extruding one flat
// XZ mask through the entire native cloud box.
float nvs_valueNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);
    float n000 = nvs_hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = nvs_hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = nvs_hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = nvs_hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = nvs_hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = nvs_hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = nvs_hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = nvs_hash13(i + vec3(1.0, 1.0, 1.0));
    float z0 = mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y);
    float z1 = mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y);
    return mix(z0, z1, u.z);
}

float nvs_fbm3(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 0.5;
    float normalizer = 0.0;
    for (int i = 0; i < octaves; ++i) {
        sum += amplitude * nvs_valueNoise3(p);
        normalizer += amplitude;
        p = p.yzx * 2.03 + vec3(17.0, 9.0, 13.0);
        amplitude *= 0.5;
    }
    return sum / max(normalizer, 1e-5);
}

#endif

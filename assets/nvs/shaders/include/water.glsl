#ifndef NVS_WATER_GLSL
#define NVS_WATER_GLSL

#include <nvs:common.glsl>
#include <nvs:clouds.glsl>
#include <nvs:sky.glsl>

// Water.
//
// The surface stays flat, exactly where the game put it: the waves live in the
// normal, which is all a reflection needs. Moving the geometry instead would
// also move glass and ice, which share the translucent terrain pass, and the
// vertex program gets no texture to tell them apart.
//
// Water is recognised the way the game's own textures allow: every water
// texture has a uniform alpha of 180/255, and water is tinted by the biome. The
// slime block shares the alpha but not the tint. The raw pre-lighting vertex
// colour is what makes that test possible, so `core/terrain.vsh` passes it.

#define NVS_WATER_ALPHA 180.0

bool nvs_isWater(vec4 texel, vec4 tint) {
    float spread = nvs_max3(tint.rgb) - nvs_min3(tint.rgb);
    return abs(texel.a * 255.0 - NVS_WATER_ALPHA) < 1.5 && spread > 0.04;
}

// GameTime arrives as 0..1 over 24000 ticks and wraps. Every animated function
// here is built so that the wrap is seamless: the time enters as whole numbers
// of cycles per day, and everywhere else as the phase of a circle.
#define NVS_WAVE_CYCLES_PER_DAY 120.0

float nvs_waveTime(float gameTime) {
    return gameTime * 6.2831853 * NVS_WAVE_CYCLES_PER_DAY;
}

// Surface slope: the gradient of a sum of directional waves, plus a ripple
// channel made of value noise. The ripple drifts around a circle rather than
// along a line, so it loops exactly when the day does.
vec2 nvs_waveGradient(vec2 p, float t, float strength) {
    vec2 grad = vec2(0.0);

    // Five incommensurate directions break up the parallel bands produced
    // by a small set of pure sine waves. Temporal rates are integer multiples
    // of the daily base frequency, so every wave closes exactly at GameTime's
    // wrap instead of snapping at dawn.
    const vec2 d0 = vec2(0.94, 0.34);
    const vec2 d1 = vec2(-0.42, 0.91);
    const vec2 d2 = vec2(0.68, -0.73);
    const vec2 d3 = vec2(-0.91, -0.40);
    const vec2 d4 = vec2(0.18, -0.98);
    const float k0 = 0.62;
    const float k1 = 1.17;
    const float k2 = 2.31;
    const float k3 = 0.86;
    const float k4 = 1.72;
    const float a0 = 0.050;
    const float a1 = 0.026;
    const float a2 = 0.012;
    const float a3 = 0.018;
    const float a4 = 0.009;

    float ph0 = dot(p, d0) * k0 + t;
    float ph1 = dot(p, d1) * k1 + t * 1.7;
    float ph2 = dot(p, d2) * k2 + t * 2.9;
    float ph3 = dot(p, d3) * k3 + t * 2.1;
    float ph4 = dot(p, d4) * k4 + t * 3.3;
    grad += (a0 * k0) * cos(ph0) * d0;
    grad += (a1 * k1) * cos(ph1) * d1;
    grad += (a2 * k2) * cos(ph2) * d2;
    grad += (a3 * k3) * cos(ph3) * d3;
    grad += (a4 * k4) * cos(ph4) * d4;

    vec2 orbit = vec2(cos(t * 0.5), sin(t * 0.5)) * 4.0;
    vec2 rp = p * 0.55 + orbit;
    const float e = 0.08;
    float n0 = nvs_valueNoise(rp);
    float nx = nvs_valueNoise(rp + vec2(e, 0.0));
    float nz = nvs_valueNoise(rp + vec2(0.0, e));
    grad += NVS_WATER_RIPPLE * vec2(nx - n0, nz - n0) / e * 0.10;

    return grad * strength;
}

vec3 nvs_waterNormal(vec2 p, float t, float strength) {
    vec2 g = nvs_waveGradient(p, t, strength);
    return normalize(vec3(-g.x, 1.0, -g.y));
}

// Foam on the crests of the wave sum. 0 in the troughs, 1 on the peaks.
float nvs_waterCrest(vec2 p, float t) {
    float h = 0.0;
    h += 0.5 + 0.5 * sin(dot(p, vec2(0.94, 0.34)) * 0.62 + t);
    h += 0.5 + 0.5 * sin(dot(p, vec2(-0.42, 0.91)) * 1.17 + t * 1.7);
    h += 0.5 + 0.5 * sin(dot(p, vec2(0.68, -0.73)) * 2.31 + t * 2.9);
    h += 0.5 + 0.5 * sin(dot(p, vec2(-0.91, -0.40)) * 0.86 + t * 2.1);
    h += 0.5 + 0.5 * sin(dot(p, vec2(0.18, -0.98)) * 1.72 + t * 3.3);
    return h / 5.0;
}

// The sky in the direction of a reflection, including the cloud layer.
// `horizon` is FogColor; the zenith is inferred from it, because this runs in
// a program that does not receive the sky's own colour.
vec3 nvs_reflectedSky(vec3 reflected, vec2 worldXZ, float worldY, vec3 horizon) {
    vec3 zenith = nvs_zenithFromHorizon(horizon);
    vec3 sky = nvs_skyGradient(reflected, zenith, horizon);

    // Carry the procedural night sky into the reflection as well. Without this,
    // the sky above can show stars and nebula while the water remains a flat,
    // empty dark gradient at night.
    float night = 1.0 - smoothstep(0.010, 0.075, nvs_luma(zenith));
    sky += nvs_nightSky(reflected, night);

    if (reflected.y > 0.02) {
        // Where the reflected ray crosses the cloud layer. The reflection of
        // real clouds is worth the four noise taps: a flat mirror is the single
        // most obvious tell of a fake water surface.
        float cloudY = NVS_CLOUD_HEIGHT;
        float travel = max(cloudY - worldY, 1.0);
        vec2 cloudXZ = worldXZ + reflected.xz * (travel / reflected.y);
        float d = nvs_cloudField(cloudXZ);
        float cover = smoothstep(NVS_CLOUD_CUTOFF, NVS_CLOUD_CUTOFF + 0.45, d) * 0.55;
        vec3 cloudTint = horizon * 1.10 + vec3(0.05);
        sky = mix(sky, cloudTint, cover);
    }

    return sky;
}

// Shade one water fragment.
//
// `baseColor` is what the game already computed for the water surface: texture
// times the biome tint times the lightmap. `viewPos` is the fragment relative to
// the camera (the camera is the origin there), `worldPos` is absolute.
//
// Only the colour changes. The alpha is left exactly as the game set it, which
// is what keeps the water translucent over the bottom and keeps the three
// Improved Transparency passes consistent with each other.
vec3 nvs_shadeWater(vec3 baseColor, vec3 viewPos, vec3 worldPos, float gameTime,
                    vec3 horizon, float underwater) {
    float t = nvs_waveTime(gameTime);

    vec3 V = normalize(-viewPos);
    float viewDistance = length(viewPos);

    // Keep the near-field lively, but fade sub-pixel wave detail in the far
    // field. Without this, the high-frequency ripples alias into dark bands
    // that make a large lake look striped rather than reflective.
    float farWaveFade = 1.0 - smoothstep(22.0, 88.0, viewDistance);
    float waveStrength = NVS_WATER_WAVE_STRENGTH * mix(0.42, 1.0, farWaveFade);
    vec3 N = nvs_waterNormal(worldPos.xz, t, waveStrength);

    float NoV = clamp(dot(N, V), 0.0, 1.0);

    // Schlick's approximation with water's F0. Grazing angles reflect almost
    // everything, which is what gives water its bright, silvery far field and
    // its transparent near field.
    float fresnel = NVS_WATER_F0 + (1.0 - NVS_WATER_F0) * pow(1.0 - NoV, 5.0);

    // The native terrain pass does not expose the bottom depth of a water
    // column. Camera distance is NOT water depth: using length(viewPos) here
    // made distant lakes turn nearly black even when the water was shallow.
    // Use a stable artistic water-column estimate instead, with a little more
    // absorption at grazing angles. This keeps the far field bright and blue-
    // green while still giving the surface real depth and color separation.
    float pathLength = mix(8.0, 24.0, smoothstep(0.15, 0.90, 1.0 - NoV));
    vec3 absorption = vec3(0.34, 0.13, 0.085) * NVS_WATER_ABSORB;
    vec3 transmittance = exp(-absorption * pathLength);
    vec3 deepWaterTint = vec3(0.78, 0.94, 1.06);
    vec3 below = baseColor * transmittance * deepWaterTint;

    vec3 reflected = reflect(-V, N);
    vec3 skyReflection = nvs_reflectedSky(reflected, worldPos.xz, worldPos.y, horizon);

    // Above the surface, Fresnel blends the water column with the sky.
    // Below the surface, the same geometric normal faces away from the viewer:
    // clamping NoV to zero would therefore force Fresnel to 1 and turn the
    // underside into a false sky mirror. The native pass has no underwater
    // reflection buffer, so keep the underside refractive and let vanilla fog
    // provide the distant underwater scene instead.
    float reflectionWeight = fresnel * (1.0 - clamp(underwater, 0.0, 1.0));
    vec3 color = mix(below, skyReflection, reflectionWeight);

    // Whitecaps: the crests of the same wave sum, broken up by the ripple so
    // they do not read as a regular pattern.
    if (NVS_WATER_FOAM > 0.0) {
        float crest = smoothstep(0.72, 1.0, nvs_waterCrest(worldPos.xz * 0.55, t));
        float broken = nvs_valueNoise(worldPos.xz * 1.9 + vec2(t * 0.25));
        float foam = crest * smoothstep(0.35, 0.85, broken) * mix(0.45, 1.0, farWaveFade);
        color += vec3(NVS_WATER_FOAM) * foam;
    }

    // Seen from under the surface: the game already fogs the world toward the
    // water colour, this only keeps the surface from reading as a mirror.
    color = mix(color, color * vec3(0.72, 0.94, 0.98), underwater * 0.6);

    return color;
}

#endif

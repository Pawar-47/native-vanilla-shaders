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
// The five directional wave components share one height field. Keeping the
// height, analytic slope and crest mask derived from the same amplitudes avoids
// the old mismatch where foam peaks did not line up with the reflected normals.
//
// Every temporal multiplier is an integer. GameTime wraps after one day, so
// integer harmonics close exactly at the wrap; fractional rates (1.7, 2.9,
// etc.) caused a visible phase discontinuity at midnight.
float nvs_waveFade(float waveNumber, float footprint) {
    float pixelScale = max(footprint, 1e-4);
    return smoothstep(2.0, 6.0, 6.2831853 / (waveNumber * pixelScale));
}

// A slowly varying domain warp breaks up the long parallel sine bands. The
// same position-only warp and amplitude field are used by height, slope and
// foam, so the surface remains temporally stable and the crests stay aligned.
// The warp derivative is deliberately omitted: at this scale it changes the
// normal very little, while differentiating the noise would add substantial cost.
vec3 nvs_waveDomain(vec2 p) {
    vec2 low = p * 0.045;
    vec2 warp = (vec2(nvs_valueNoise(low), nvs_valueNoise(low + 31.7)) - 0.5) * 14.0;
    float variation = 0.55 + 0.90 * nvs_valueNoise(low + vec2(17.3, 9.1));
    return vec3(p + warp, variation);
}

float nvs_waveHeight(vec2 p, float t, float footprint) {
    vec3 domain = nvs_waveDomain(p);
    vec2 waveP = domain.xy;
    float variation = domain.z;
    float f0 = nvs_waveFade(0.62, footprint);
    float f1 = nvs_waveFade(1.17, footprint);
    float f2 = nvs_waveFade(2.31, footprint);
    float f3 = nvs_waveFade(0.86, footprint);
    float f4 = nvs_waveFade(1.72, footprint);
    float h = 0.0;
    h += 0.050 * variation * f0 * sin(dot(waveP, vec2(0.94, 0.34)) * 0.62 + t);
    h += 0.026 * variation * f1 * sin(dot(waveP, vec2(-0.42, 0.91)) * 1.17 + t * 2.0);
    h += 0.012 * variation * f2 * sin(dot(waveP, vec2(0.68, -0.73)) * 2.31 + t * 3.0);
    h += 0.018 * variation * f3 * sin(dot(waveP, vec2(-0.91, -0.40)) * 0.86 + t * 5.0);
    h += 0.009 * variation * f4 * sin(dot(waveP, vec2(0.18, -0.98)) * 1.72 + t * 7.0);
    return h;
}

// Analytic derivative of nvs_waveHeight, plus a small circularly drifting
// noise ripple. The circular drift also closes after an integer number of
// revolutions when GameTime wraps.
vec2 nvs_waveGradient(vec2 p, float t, float strength, float footprint) {
    vec3 domain = nvs_waveDomain(p);
    vec2 waveP = domain.xy;
    float variation = domain.z;
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
    // A wave shorter than roughly two pixels aliases; fade it out before
    // it reaches that point, as in the reference water implementation.
    float f0 = nvs_waveFade(k0, footprint);
    float f1 = nvs_waveFade(k1, footprint);
    float f2 = nvs_waveFade(k2, footprint);
    float f3 = nvs_waveFade(k3, footprint);
    float f4 = nvs_waveFade(k4, footprint);

    vec2 grad = vec2(0.0);
    grad += (0.050 * variation * k0) * cos(dot(waveP, d0) * k0 + t) * d0 * f0;
    grad += (0.026 * variation * k1) * cos(dot(waveP, d1) * k1 + t * 2.0) * d1 * f1;
    grad += (0.012 * variation * k2) * cos(dot(waveP, d2) * k2 + t * 3.0) * d2 * f2;
    grad += (0.018 * variation * k3) * cos(dot(waveP, d3) * k3 + t * 5.0) * d3 * f3;
    grad += (0.009 * variation * k4) * cos(dot(waveP, d4) * k4 + t * 7.0) * d4 * f4;

    vec2 orbit = vec2(cos(t * 0.5), sin(t * 0.5)) * 4.0;
    vec2 rp = p * 0.55 + orbit;
    const float e = 0.08;
    float n0 = nvs_valueNoise(rp);
    float nx = nvs_valueNoise(rp + vec2(e, 0.0));
    float nz = nvs_valueNoise(rp + vec2(0.0, e));
    float rippleFade = nvs_waveFade(0.55, footprint);
    grad += NVS_WATER_RIPPLE * vec2(nx - n0, nz - n0) / e * 0.10 * rippleFade;

    return grad * strength;
}

vec3 nvs_waterNormal(vec2 p, float t, float strength, float footprint) {
    vec2 g = nvs_waveGradient(p, t, strength, footprint);
    return normalize(vec3(-g.x, 1.0, -g.y));
}

vec3 nvs_waterNormal(vec2 p, float t, float strength) {
    return nvs_waterNormal(p, t, strength, 1.0);
}

// Foam follows the actual combined wave height, so its crests coincide with
// the normal field rather than using five equally weighted, mismatched waves.
float nvs_waterCrest(vec2 p, float t, float footprint) {
    float variation = nvs_waveDomain(p).z;
    float totalAmplitude = variation * (0.050 * nvs_waveFade(0.62, footprint)
                         + 0.026 * nvs_waveFade(1.17, footprint)
                         + 0.012 * nvs_waveFade(2.31, footprint)
                         + 0.018 * nvs_waveFade(0.86, footprint)
                         + 0.009 * nvs_waveFade(1.72, footprint));
    return clamp(0.5 + 0.5 * nvs_waveHeight(p, t, footprint) / max(totalAmplitude, 1e-5), 0.0, 1.0);
}

float nvs_waterCrest(vec2 p, float t) {
    return nvs_waterCrest(p, t, 1.0);
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
        float cover = smoothstep(NVS_CLOUD_CUTOFF, NVS_CLOUD_CUTOFF + 0.45, d) * 0.62;
        // Water sees the underside of the cloud layer. Reuse the same
        // thickness/underside response as the visible cloud volume instead of
        // reflecting featureless horizon-coloured patches.
        float underside = nvs_cloudShade(d, 0.0);
        vec3 cloudTint = (horizon * 1.10 + vec3(0.05)) * underside;
        sky = mix(sky, cloudTint, cover);
    }

    return sky;
}


bool nvs_waterMarkersOn(float environmentalFogEnd) { return environmentalFogEnd > 100.0; }
float nvs_waterData(vec3 worldPosition) {
    vec3 n = cross(dFdx(worldPosition), dFdy(worldPosition));
    float l = length(n);
    n = l > 1e-5 ? n / l : vec3(0.0, 1.0, 0.0);
    return abs(n.y) > 0.7 ? 1.0 : (128.0 / 255.0);
}
vec4 nvs_waterMarker(int x, float data) {
    return vec4(float((x * 73 + 11) & 255) / 255.0,
                float((x * 197 + 89) & 255) / 255.0, data, 1.0);
}
bool nvs_isWaterMarker(vec4 c, int x) {
    vec4 m = nvs_waterMarker(x, 0.0);
    bool data = abs(c.b - 1.0) < 0.5 / 255.0 || abs(c.b - 128.0 / 255.0) < 1.0 / 255.0;
    return (x & 1) == 0 && abs(c.r - m.r) < 0.5 / 255.0
        && abs(c.g - m.g) < 0.5 / 255.0 && c.a > 254.5 / 255.0 && data;
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

    float viewDistance = length(viewPos);
    // A fragment exactly at the camera origin is a valid limiting case for
    // normalize(), but GLSL leaves normalize(vec3(0)) undefined. Use the
    // straight-up view direction at that singular point.
    vec3 V = viewDistance > 1e-4 ? -viewPos / viewDistance : vec3(0.0, 1.0, 0.0);

    // Keep the near-field lively, but fade sub-pixel wave detail in the far
    // field. Without this, the high-frequency ripples alias into dark bands
    // that make a large lake look striped rather than reflective.
    float farWaveFade = 1.0 - smoothstep(NVS_WATER_FAR_FADE_START, NVS_WATER_FAR_FADE_END, viewDistance);
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
        float crest = smoothstep(NVS_WATER_FOAM_THRESHOLD, 1.0, nvs_waterCrest(worldPos.xz, t));
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

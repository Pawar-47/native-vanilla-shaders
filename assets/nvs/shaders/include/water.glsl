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

// GameTime arrives as 0..1 over 24000 ticks and wraps. Three broad wave
// frequencies are integer cycles per Minecraft day, so phases remain seamless.
#define NVS_WAVE_CYCLES_PER_DAY 120.0

float nvs_waveTime(float gameTime) {
    return gameTime * 6.2831853 * NVS_WAVE_CYCLES_PER_DAY;
}

// Broad, overlapping swells replace the short, crossing ripples that produced
// crawling bands in reflections. Three directions are enough for calm lakes
// and rivers; the footprint filter fades detail before it can alias.
const int NVS_WAVE_COUNT = 3;
const vec2 NVS_WAVE_DIRECTIONS[3] = vec2[](
    vec2(1.0, 0.22), vec2(-0.38, 1.0), vec2(0.72, -0.68)
);
const float NVS_WAVE_LENGTHS[3] = float[](18.0, 11.5, 7.5);
const float NVS_WAVE_CYCLES[3] = float[](390.0, 505.0, 635.0);

float nvs_waveFade(float waveNumber, float footprint) {
    float pixelScale = max(footprint, 1e-4);
    return smoothstep(2.0, 6.0, 6.2831853 / (waveNumber * pixelScale));
}

// Evaluate height, analytic slope and normalisation amplitude together.
// No domain warp is used: the analytic gradient must be the true derivative
// of the height field, otherwise the reflection normal becomes visibly noisy.
vec4 nvs_waterSurface(vec2 p, float t, float strength, float footprint) {
    float height = 0.0;
    float totalAmplitude = 0.0;
    vec2 gradient = vec2(0.0);

    for (int i = 0; i < NVS_WAVE_COUNT; ++i) {
        float wavelength = NVS_WAVE_LENGTHS[i];
        float waveNumber = 6.2831853 / wavelength;
        vec2 direction = normalize(NVS_WAVE_DIRECTIONS[i]);
        float amplitude = 0.010 * wavelength * nvs_waveFade(waveNumber, footprint);
        float phase = waveNumber * dot(direction, p)
                    - t * (NVS_WAVE_CYCLES[i] / NVS_WAVE_CYCLES_PER_DAY);
        height += amplitude * sin(phase);
        gradient += amplitude * waveNumber * cos(phase) * direction;
        totalAmplitude += amplitude;
    }

    return vec4(height, gradient * strength, totalAmplitude);
}

float nvs_waveHeight(vec2 p, float t, float footprint) {
    return nvs_waterSurface(p, t, 0.0, footprint).x;
}

vec2 nvs_waveGradient(vec2 p, float t, float strength, float footprint) {
    return nvs_waterSurface(p, t, strength, footprint).yz;
}

vec3 nvs_waterNormal(vec2 p, float t, float strength, float footprint) {
    vec4 surface = nvs_waterSurface(p, t, strength, footprint);
    return normalize(vec3(-surface.y, 1.0, -surface.z));
}

vec3 nvs_waterNormal(vec2 p, float t, float strength) {
    return nvs_waterNormal(p, t, strength, 1.0);
}

// Foam follows the crest of the exact filtered height spectrum used for normals.
float nvs_waterCrest(vec2 p, float t, float footprint) {
    vec4 surface = nvs_waterSurface(p, t, 1.0, footprint);
    return clamp(0.5 + 0.5 * surface.x / max(surface.w, 1e-5), 0.0, 1.0);
}

float nvs_waterCrest(vec2 p, float t) {
    return nvs_waterCrest(p, t, 1.0);
}

// The sky in the direction of a reflection, including the cloud layer.
// Both colours come from the frame's data bus, so the reflection matches the
// actual biome, dimension, weather and time-of-day sky rather than estimating
// the zenith from the horizon.
vec3 nvs_reflectedSky(vec3 reflected, vec2 worldXZ, float worldY, vec3 zenith, vec3 horizon) {
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
        float d = nvs_cloudPuffDensity(cloudXZ);
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
    if (abs(n.y) > 0.7) return 1.0;

    // Side faces are axis-aligned in vanilla water geometry. Encode their
    // dominant horizontal normal in four exact byte values so the post pass
    // does not need full-screen derivatives to recover it.
    float direction = abs(n.x) > abs(n.z) ? (n.x >= 0.0 ? 0.0 : 1.0)
                                           : (n.z >= 0.0 ? 2.0 : 3.0);
    return 0.25 + direction * 0.125;
}
vec4 nvs_waterMarker(int x, float data) {
    return vec4(float((x * 73 + 11) & 255) / 255.0,
                float((x * 197 + 89) & 255) / 255.0, data, 1.0);
}
bool nvs_isWaterMarker(vec4 c, int x) {
    vec4 m = nvs_waterMarker(x, 0.0);
    float sideIndex = round((c.b - 0.25) * 8.0);
    bool topData = abs(c.b - 1.0) < 0.5 / 255.0;
    bool sideData = sideIndex >= 0.0 && sideIndex <= 3.0
                 && abs(c.b - (0.25 + sideIndex * 0.125)) < 0.5 / 255.0;
    return (x & 1) == 0 && abs(c.r - m.r) < 0.5 / 255.0
        && abs(c.g - m.g) < 0.5 / 255.0 && c.a > 254.5 / 255.0 && (topData || sideData);
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
    float distanceFade = 1.0 / (1.0 + viewDistance / NVS_WATER_FLATTEN_DISTANCE);
    float waveStrength = NVS_WATER_WAVE_STRENGTH * distanceFade;
    vec4 waveSurface = nvs_waterSurface(worldPos.xz, t, waveStrength, 1.0);
    vec3 N = normalize(vec3(-waveSurface.y, 1.0, -waveSurface.z));

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
    float pathLength = mix(18.0, 42.0, smoothstep(0.15, 0.90, 1.0 - NoV));
    vec3 absorption = vec3(0.62, 0.24, 0.12) * (NVS_WATER_ABSORB * 1.65);
    vec3 transmittance = exp(-absorption * pathLength);
    vec3 deepWaterTint = vec3(0.34, 0.66, 0.78);
    vec3 below = baseColor * transmittance * deepWaterTint;
    // Suppress bright seabed/riverbed detail beneath the surface. The native
    // pass exposes no true water-column depth, so this stable artistic veil
    // gives the view a deeper, more continuous body of water.

    vec3 reflected = reflect(-V, N);
    vec3 skyReflection = nvs_reflectedSky(reflected, worldPos.xz, worldPos.y, nvs_zenithFromHorizon(horizon), horizon);

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
        float crestValue = clamp(0.5 + 0.5 * waveSurface.x / max(waveSurface.w, 1e-5), 0.0, 1.0);
        float crest = smoothstep(NVS_WATER_FOAM_THRESHOLD, 1.0, crestValue);
        float broken = nvs_valueNoise(worldPos.xz * 1.9 + vec2(t * 0.25));
        float foam = crest * smoothstep(0.35, 0.85, broken) * mix(0.45, 1.0, distanceFade);
        color += vec3(NVS_WATER_FOAM) * foam;
    }

    // Seen from under the surface: the game already fogs the world toward the
    // water colour, this only keeps the surface from reading as a mirror.
    color = mix(color, color * vec3(0.72, 0.94, 0.98), underwater * 0.6);

    return color;
}

#endif

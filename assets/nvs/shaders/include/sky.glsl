#ifndef NVS_SKY_GLSL
#define NVS_SKY_GLSL

#include <nvs:common.glsl>

// The sky, as a function of a world-space direction.
//
// Every colour comes from the game: `zenith` is the sky's ColorModulator and
// `horizon` is FogColor. 26.3 already sets both from the time of day, the
// weather, the biome and the dimension, so nothing here has to know any of
// those, and the pack stays correct with datapacks that move the clock.
//
// The Vanilla sky is this colour mixed flat across a disc, which is where the
// flat gradient and the hard horizon edge come from. Here the mix follows a
// curve in the view's elevation instead.

// Solar disc and atmospheric aureole shared by the visible sky and water
// reflections. The game supplies the actual sun direction and rain dimmer.
vec3 nvs_sunGlow(vec3 direction, vec3 sunDirection, float rainBrightness) {
    // All callers provide normalized directions. Chord distance closely
    // approximates angular distance over the solar disc and aureole, avoiding
    // an expensive acos in the full-resolution sky/water passes.
    float cosine = clamp(dot(direction, sunDirection), -1.0, 1.0);
    float angle = sqrt(max(2.0 * (1.0 - cosine), 0.0));
    // A slightly generous angular disc remains legible at ordinary render
    // distances and on low-resolution displays, without becoming a giant flare.
    float disc = 1.0 - smoothstep(0.0058, 0.0072, angle);
    float corona = exp(-angle * 38.0) * 0.30 + exp(-angle * 12.0) * 0.085;
    float aureole = exp(-angle * 3.2) * 0.055;
    float visibility = smoothstep(-0.10, 0.08, sunDirection.y);
    return vec3(1.0, 0.82, 0.58) * (disc * 1.8 + corona + aureole)
         * rainBrightness * visibility;
}

vec3 nvs_skyGradient(vec3 dir, vec3 zenith, vec3 horizon) {
    float up = clamp(dir.y, 0.0, 1.0);

    // Pure function of the elevation, exactly 0 at the zenith and exactly 1 at
    // the horizon, so the sky meets the fog on distant terrain without a seam.
    // The default exponent bulges the horizon band the way air does.
    float haze = pow(1.0 - up, NVS_SKY_HAZE_POWER);

    vec3 c = mix(zenith, horizon, haze);

    // Sunrise and sunset: warm the last few degrees of sky above the horizon.
    // The strength follows how warm the horizon colour already is, so a blue
    // noon sky is untouched and a red sunset is deepened rather than tinted.
    float warm = nvs_warmth(horizon);
    float lowBand = pow(1.0 - up, 4.0);
    c = mix(c, c * vec3(1.18, 0.93, 0.74), warm * lowBand * NVS_SKY_WARM_STRENGTH);

    return max(c, 0.0);
}

// One layer of a procedural star field on the sphere of directions.
// The dot is a smooth, size-bounded blob inside one cell, so it never crosses a
// cell boundary and never shimmers as the camera turns.
float nvs_starLayer(vec3 dir, float scale, float threshold, out vec3 tint) {
    vec3 p = dir * scale;
    vec3 cell = floor(p);
    vec3 f = p - cell - 0.5;
    float h = nvs_hash13(cell);
    tint = vec3(0.0);
    float magnitude = smoothstep(threshold, 1.0, h);
    if (magnitude <= 0.0) {
        return 0.0;
    }
    float temperature = nvs_hash13(cell + 91.7);
    float r2 = dot(f, f);
    float dotFade = 1.0 - smoothstep(0.02, 0.30, r2);
    tint = mix(vec3(0.72, 0.85, 1.00), vec3(1.00, 0.87, 0.70), temperature);
    return magnitude * dotFade * (0.45 + 0.55 * temperature);
}

// The band of a galaxy across the sky, used to concentrate the nebula.
float nvs_galacticBand(vec3 dir) {
    const vec3 axis = vec3(0.42, 0.62, -0.66);
    float d = dot(normalize(dir), normalize(axis));
    return exp(-d * d * 9.0);
}

// Everything that only shows at night: airglow, a nebula with depth, and a
// star field. `night` comes from how dark the game's own sky colour is, so this
// needs no clock: it fades in exactly when vanilla's sky fades out.
vec3 nvs_nightSky(vec3 dir, float night) {
    if (night <= 0.002 || NVS_NIGHT_STRENGTH <= 0.0) {
        return vec3(0.0);
    }

    // Project the upper hemisphere onto a plane. The offset keeps the
    // projection from degenerating at the zenith, and no point of the visible
    // sky reaches the pole of the denominator.
    vec2 uv = dir.xz / (0.55 + max(dir.y, 0.0));

    float n = nvs_fbm(uv * 2.2 + vec2(3.1, 7.4), NVS_NEBULA_OCTAVES);
    float band = nvs_galacticBand(dir);

    // Nebula: creased clouds of gas, brighter along the band.
    float neb = pow(clamp(n * 1.30 - 0.12, 0.0, 1.0), 1.7);
    neb *= 0.30 + 1.05 * band;
    vec3 nebulaColor = mix(vec3(0.15, 0.19, 0.42), vec3(0.40, 0.23, 0.42), n);

    vec3 tintA;
    vec3 tintB;
    float starsA = nvs_starLayer(dir, 130.0, 0.900, tintA);
    float starsB = nvs_starLayer(dir, 240.0, 0.955, tintB);
    vec3 starColor = tintA * starsA + tintB * starsB * 0.55;

    // Stars and nebula both fade into the haze near the horizon, the way the
    // atmosphere extinguishes them.
    float extinction = smoothstep(-0.02, 0.22, dir.y);

    vec3 airglow = vec3(0.004, 0.007, 0.016) * smoothstep(0.0, 0.9, dir.y);

    return (nebulaColor * neb * 0.55 + starColor * 1.6 + airglow) * extinction * night * NVS_NIGHT_STRENGTH;
}

// A stand-in for the zenith colour for programs that do not receive the sky's
// ColorModulator. `core/terrain` is one: it gets FogColor but not the sky
// colour, so the water's reflection has to infer how the sky darkens upward.
// Warm horizons (sunrise, sunset) get a deeper, desaturated zenith; cool ones
// (day) a deeper blue; dark ones (night) stay dark.
vec3 nvs_zenithFromHorizon(vec3 horizon) {
    float warm = nvs_warmth(horizon);
    vec3 coolZenith = horizon * vec3(0.50, 0.68, 1.34);
    vec3 warmZenith = horizon * vec3(0.56, 0.50, 0.84);
    return mix(coolZenith, warmZenith, warm);
}

#endif

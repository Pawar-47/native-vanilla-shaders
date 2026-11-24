#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <nvs:sky.glsl>

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec3 nvsSkyDirection;
layout(location = 3) flat in float nvsLowerDisc;

layout(location = 0) out vec4 fragColor;

void main() {
    // The disc under the horizon keeps vanilla's look: it exists to hide the
    // void, not to be looked at.
    if (nvsLowerDisc > 0.5) {
        fragColor = apply_fog(ColorModulator, sphericalVertexDistance, cylindricalVertexDistance,
                              0.0, FogSkyEnd, FogSkyEnd, FogSkyEnd, FogColor);
        return;
    }

    // Both colours are the game's own, already correct for the hour, the
    // weather, the biome and the dimension.
    vec3 zenith = ColorModulator.rgb;
    vec3 horizon = FogColor.rgb;

    vec3 sky = nvs_skyGradient(nvsSkyDirection, zenith, horizon);

    // Night: how dark the game's sky colour is, which needs no clock and stays
    // right for every dimension and for datapacks that move the time.
    float night = 1.0 - smoothstep(0.010, 0.075, nvs_luma(zenith));
    sky += nvs_nightSky(nvsSkyDirection, night);

    // The target is 8-bit: a gradient this smooth bands without dithering.
    sky += nvs_dither(gl_FragCoord.xy);
    sky = max(sky, 0.0);

    // Vanilla's call, with vanilla's arguments: under blindness, or under
    // water, FogSkyEnd collapses and the sky becomes the fog colour. Keeping
    // this is what makes those effects keep working.
    fragColor = apply_fog(vec4(sky, ColorModulator.a), sphericalVertexDistance, cylindricalVertexDistance,
                          0.0, FogSkyEnd, FogSkyEnd, FogSkyEnd, FogColor);
}

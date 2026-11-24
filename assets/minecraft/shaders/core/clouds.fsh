#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:projection.glsl>

#include <minecraft:fog.glsl>
#include <minecraft:oit.glsl>
#include <nvs:clouds.glsl>

layout(location = 0) in float vertexDistance;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) in vec2 nvsCloudXZ;
layout(location = 3) flat in float nvsCloudUp;
layout(location = 4) in float nvsCloudHeight;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    #endif
    return color;
}

void main() {
    NVS_BUS_PROTECT
    // Carve the volume. The game supplies the cells; the field decides which
    // parts of them survive, which is where the multiscale cumulus forms, the
    // torn wispy edges and the absence of tiling come from.
    //
    // This happens before every OIT branch so that the three Improved
    // Transparency passes discard exactly the same fragments and their
    // transmittance stays consistent with the colour pass.
    float baseDensity = nvs_cloudField(nvsCloudXZ);
    // The vertical field can move density by at most half its configured
    // strength. Reject fragments that cannot reach the cutoff before paying
    // for the extra 3D noise octaves.
    if (baseDensity < NVS_CLOUD_CUTOFF - 0.5 * NVS_CLOUD_VOLUME_STRENGTH) {
        discard;
    }
    float density = nvs_cloudVolumeField(nvsCloudXZ, nvsCloudHeight, baseDensity);
    // Fade the last density band instead of cutting a hard silhouette at
    // every native cloud-cell boundary. Keep a small discard margin for cost.
    if (density < NVS_CLOUD_CUTOFF - 0.08) {
        discard;
    }

    vec4 color = vertexColor;
    color.a *= smoothstep(NVS_CLOUD_CUTOFF - 0.08,
                          NVS_CLOUD_CUTOFF + 0.14, density);
    #ifndef OIT_DEPTH_BOUNDS
    color.a *= 1.0f - linear_fog_value(vertexDistance, 0, FogCloudsEnd);
    #endif

    // Lit tops, shaded undersides, darker creases. All of the hour, the weather
    // and the dimension arrive in CloudColor, which the game sets.
    color.rgb *= nvs_cloudShade(density, nvsCloudUp * 0.5 + 0.5);

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}

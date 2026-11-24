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
    // The native 26.3 cloud mesh is a coarse box grid. Leave it transparent:
    // the sky post pass draws the stylised cloud layer from a world-space
    // rounded-lobe field, avoiding the dark rectangular geometry entirely.
    vec4 color = vec4(0.0);
    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, 0.0);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}

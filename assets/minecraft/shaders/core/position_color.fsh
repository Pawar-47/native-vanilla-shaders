#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:oit.glsl>

layout(location = 0) in vec4 vertexColor;
layout(location = 1) in float nvsGlowFalloff;

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
    vec4 color = vertexColor;
    if (color.a == 0.0) {
        discard;
    }

    color *= ColorModulator;

    // The glow's pipeline blends with (one, one), where alpha is ignored, so the
    // gradient has to be carried by the colour. See position_color.vsh.
    color.rgb *= nvsGlowFalloff;

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}

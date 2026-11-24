#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>

layout(location = 0) in vec3 nvsStarTint;

layout(location = 0) out vec4 fragColor;

void main() {
    // Vanilla writes ColorModulator alone, so every star is identical. The tint
    // is the pack's only change, and it keeps the star's own alpha and the
    // additive blend untouched.
    fragColor = vec4(ColorModulator.rgb * nvsStarTint, ColorModulator.a);
}

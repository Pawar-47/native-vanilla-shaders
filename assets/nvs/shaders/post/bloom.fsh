#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

// Bright pass, then a ring blur, in one pass.
//
// This runs at the size of the "bloom" target in the post-effect JSON, which is
// deliberately small and fixed: bloom is a glow, so it does not need the screen's
// resolution, and a fixed target keeps the cost identical on every display. That
// matters on an integrated GPU, where the number of fragments shaded is the
// budget.

vec3 brightPass(vec3 c) {
    float l = max(max(c.r, c.g), c.b);
    // Only highlights: a smoothstep rather than a hard threshold, so the bloom
    // has no visible edge where it starts.
    return c * smoothstep(0.55, 0.95, l);
}

void main() {
    vec2 texel = 1.0 / OutSize;
    vec3 sum = brightPass(texture(InSampler, texCoord).rgb) * 0.90;
    float weight = 0.90;

    // Two rings of eight samples. The separation is in the bloom target's own
    // pixels, so the blur radius is constant in screen terms.
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853981634;
        vec2 dir = vec2(cos(a), sin(a));
        sum += brightPass(texture(InSampler, texCoord + dir * texel * 2.2).rgb) * 0.70;
        sum += brightPass(texture(InSampler, texCoord + dir * texel * 4.7).rgb) * 0.35;
        weight += 1.05;
    }

    fragColor = vec4(sum / weight, 1.0);
}

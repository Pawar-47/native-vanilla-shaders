#version 330
#extension GL_ARB_separate_shader_objects : require

#include <nvs:config.glsl>
#include <nvs:common.glsl>

uniform sampler2D InSampler;
uniform sampler2D BloomSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

// The final grade: sharpen, bloom, highlight shoulder, contrast, saturation,
// vignette, dither.
//
// The game hands a post effect an 8-bit image, so there is no high dynamic range
// to tone-map here. What there is instead is headroom to reclaim: the shoulder
// below leaves everything under NVS_POST_SHOULDER untouched and compresses only
// the top end, on a curve that approaches 1 without ever crossing it. That is
// the closest valid equivalent of a tone map without HDR, and it cannot wash the
// midtones out because it does not move them at all.

vec3 shoulder(vec3 x) {
    float knee = NVS_POST_SHOULDER;
    float span = max(1.0 - knee, 1e-3);
    vec3 over = max(x - vec3(knee), vec3(0.0));
    return min(x, vec3(knee)) + span * (1.0 - exp(-over / span));
}

void main() {
    vec2 texel = 1.0 / InSize;

    vec3 c = texture(InSampler, texCoord).rgb;

    // A light sharpen. On a low-end GPU with no upscaling this reads as restored
    // clarity; it is kept low because it halos past about 0.3.
    if (NVS_POST_SHARPEN > 0.0) {
        vec3 around = (texture(InSampler, texCoord + vec2(texel.x, 0.0)).rgb
                     + texture(InSampler, texCoord - vec2(texel.x, 0.0)).rgb
                     + texture(InSampler, texCoord + vec2(0.0, texel.y)).rgb
                     + texture(InSampler, texCoord - vec2(0.0, texel.y)).rgb) * 0.25;
        c += (c - around) * NVS_POST_SHARPEN;
    }

    c += texture(BloomSampler, texCoord).rgb * NVS_POST_BLOOM;

    c = shoulder(max(c, vec3(0.0)) * NVS_POST_EXPOSURE);

    // Contrast about the midtones, as a smoothstep: it fixes 0 at 0 and 1 at 1,
    // so it adds punch without moving either end.
    c = mix(c, c * c * (3.0 - 2.0 * c), NVS_POST_CONTRAST);

    float l = nvs_luma(c);
    c = mix(vec3(l), c, NVS_POST_SATURATION);

    // A gentle vignette. Vanilla's own vignette is a full-screen quad drawn with
    // texture colours; this one is part of the grade so it costs no extra pass.
    float r = length(texCoord - 0.5) * 1.41421356;
    c *= 1.0 - NVS_POST_VIGNETTE * smoothstep(0.35, 1.0, r);

    // Dither, so the grading does not band an 8-bit target.
    c += nvs_dither(gl_FragCoord.xy);

    // Alpha 1: this pass consumes the world's alpha, and everything downstream
    // expects the frame to be opaque.
    fragColor = vec4(max(c, vec3(0.0)), 1.0);
}

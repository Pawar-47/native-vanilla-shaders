#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

// FXAA. Not part of the default chain: it costs a full-resolution pass and
// softens the block edges that make the game look like itself. It ships as its
// own post effect so it can be switched on with
//   /posteffect add @s nvs:fxaa
// and switched off again the same way.

float fxaaLuma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

void main() {
    vec2 texel = 1.0 / InSize;

    vec3 rgbM = texture(InSampler, texCoord).rgb;
    vec3 rgbNW = texture(InSampler, texCoord + vec2(-1.0, -1.0) * texel).rgb;
    vec3 rgbNE = texture(InSampler, texCoord + vec2(1.0, -1.0) * texel).rgb;
    vec3 rgbSW = texture(InSampler, texCoord + vec2(-1.0, 1.0) * texel).rgb;
    vec3 rgbSE = texture(InSampler, texCoord + vec2(1.0, 1.0) * texel).rgb;

    float lM = fxaaLuma(rgbM);
    float lNW = fxaaLuma(rgbNW);
    float lNE = fxaaLuma(rgbNE);
    float lSW = fxaaLuma(rgbSW);
    float lSE = fxaaLuma(rgbSE);

    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));

    // Flat area: leave it exactly as it was, so nothing is blurred needlessly.
    if (lMax - lMin < max(0.0312, lMax * 0.125)) {
        fragColor = vec4(rgbM, 1.0);
        return;
    }

    vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), ((lNW + lSW) - (lNE + lSE)));
    float dirReduce = max((lNW + lNE + lSW + lSE) * 0.03125, 0.0078125);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, vec2(-8.0), vec2(8.0)) * texel;

    vec3 rgbA = 0.5 * (texture(InSampler, texCoord + dir * (1.0 / 3.0 - 0.5)).rgb
                     + texture(InSampler, texCoord + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture(InSampler, texCoord + dir * -0.5).rgb
                                   + texture(InSampler, texCoord + dir * 0.5).rgb);

    float lB = fxaaLuma(rgbB);
    fragColor = vec4((lB < lMin || lB > lMax) ? rgbA : rgbB, 1.0);
}

#version 330
#extension GL_ARB_separate_shader_objects : require

#include <nvs:bus_read.glsl>
#include <nvs:sky.glsl>

uniform sampler2D InSampler;
uniform sampler2D DepthSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    ivec2 size = textureSize(InSampler, 0);
    ivec2 pixel = clamp(ivec2(texCoord * vec2(size)), ivec2(0), size - 1);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    NvsBus bus = nvs_readBus(InSampler);

    if (bus.present && texelFetch(DepthSampler, pixel, 0).r <= 0.0) {
        vec3 worldDir = nvs_busWorldDirection(bus, texCoord);
        vec3 sky = nvs_skyGradient(worldDir, bus.skyColor, bus.fogColor);
        float night = 1.0 - smoothstep(0.010, 0.075, nvs_luma(bus.skyColor));
        sky += nvs_nightSky(worldDir, night);

        float sunAngle = acos(clamp(dot(worldDir, bus.sunDirection), -1.0, 1.0));
        float sunDisc = 1.0 - smoothstep(0.0042, 0.0052, sunAngle);
        float corona = exp(-sunAngle * 42.0) * 0.24 + exp(-sunAngle * 13.0) * 0.075;
        sky += vec3(1.0, 0.82, 0.58) * (sunDisc * 1.8 + corona) * bus.rainBrightness;

        sky += nvs_dither(gl_FragCoord.xy);
        scene = vec4(max(sky, 0.0), 1.0);
    }

    // The bus is transport data, not a visible one-pixel stripe.
    if (pixel.x == 0) {
        scene = texelFetch(InSampler, ivec2(min(1, size.x - 1), pixel.y), 0);
    }
    fragColor = scene;
}

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

    float depth = texelFetch(DepthSampler, pixel, 0).r;
    float waterData = 0.0;
    bool drawn = depth > 0.0;
    if (drawn && nvs_isWaterMarker(texelFetch(InSampler, pixel, 0), pixel.x)) {
        waterData = texelFetch(InSampler, pixel, 0).b;
        vec4 right = texelFetch(InSampler, ivec2(min(pixel.x + 1, size.x - 1), pixel.y), 0);
        vec4 left = texelFetch(InSampler, ivec2(max(pixel.x - 1, 0), pixel.y), 0);
        bool leftIsWater = pixel.x >= 2
            && nvs_isWaterMarker(texelFetch(InSampler, ivec2(pixel.x - 2, pixel.y), 0), pixel.x - 2);
        scene = leftIsWater ? 0.5 * (left + right) : right;
    } else if (drawn && (pixel.x & 1) == 1 && pixel.x > 0) {
        vec4 leftMarker = texelFetch(InSampler, ivec2(pixel.x - 1, pixel.y), 0);
        if (nvs_isWaterMarker(leftMarker, pixel.x - 1)) waterData = leftMarker.b;
    }

    if (bus.present && nvs_busCameraInAir(bus) && depth <= 0.0) {
        vec3 worldDir = nvs_busWorldDirection(bus, texCoord);
        vec3 sky = nvs_skyGradient(worldDir, bus.skyColor, bus.fogColor);
        float night = 1.0 - smoothstep(0.010, 0.075, nvs_luma(bus.skyColor));
        sky += nvs_nightSky(worldDir, night);

        float sunAngle = acos(clamp(dot(worldDir, bus.sunDirection), -1.0, 1.0));
        float sunDisc = 1.0 - smoothstep(0.0042, 0.0052, sunAngle);
        float corona = exp(-sunAngle * 42.0) * 0.24 + exp(-sunAngle * 13.0) * 0.075;
        sky += vec3(1.0, 0.82, 0.58) * (sunDisc * 1.8 + corona) * bus.rainBrightness;

        sky += nvs_dither(gl_FragCoord.xy);
        sky += max(scene.rgb - bus.fogColor, vec3(0.0));
        scene = vec4(max(sky, 0.0), 1.0);
    }

    // The bus is transport data, not a visible one-pixel stripe.
    if (pixel.x == 0) {
        scene = texelFetch(InSampler, ivec2(min(1, size.x - 1), pixel.y), 0);
        waterData = 0.0;
    }
    float tag = waterData == 0.0 ? 1.0 : waterData > 0.75 ? 0.5 : 0.25;
    fragColor = vec4(scene.rgb, tag);
}

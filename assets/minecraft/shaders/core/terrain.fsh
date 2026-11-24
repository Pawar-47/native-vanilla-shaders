#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:projection.glsl>

#include <minecraft:fog.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:texture_sampling.glsl>
#include <minecraft:oit.glsl>
#include <minecraft:terrainglobals.glsl>
#ifndef MULTIDRAW_TERRAIN
    #include <minecraft:chunksection.glsl>
#endif
#include <nvs:water.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec4 vertexColor;
layout(location = 3) in vec2 texCoord0;
layout(location = 4) in float chunkVisibility;
layout(location = 5) in vec3 nvsWorldPos;
layout(location = 6) in vec3 nvsViewPos;
layout(location = 7) in vec4 nvsTint;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif
    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}

void main() {
    NVS_BUS_PROTECT
    // Sampled first and unconditionally: sampleNearest and sampleRGSS take
    // screen-space derivatives, which are undefined inside a branch.
    vec4 texel = (UseRgss == 1 ? sampleRGSS(Sampler0, texCoord0, 1.0f / TextureSize) : sampleNearest(Sampler0, texCoord0, 1.0f / TextureSize));
    float waterData = nvs_waterData(nvsWorldPos);
    #if !defined(OIT_ALPHA_ONLY) && !defined(OIT_ACCUMULATE)
    if (nvs_waterMarkersOn(FogEnvironmentalEnd) && (int(gl_FragCoord.x) & 1) == 0
            && nvs_isWater(texel, nvsTint)) {
        fragColor = nvs_waterMarker(int(gl_FragCoord.x), waterData);
        return;
    }
    #endif
    vec4 color = texel * vertexColor;

    #ifndef OIT_ALPHA_ONLY
    // Water, or ground. Both changes are confined to the colour: the alpha is
    // left exactly as the game computed it, which keeps the surface translucent
    // over whatever is beneath it and keeps the three Improved Transparency
    // passes consistent with the colour pass.
    vec4 textureColor = texel;
    if (nvs_isWater(textureColor, nvsTint)) {
        // The camera is under water when the game has collapsed the
        // environmental fog distance, which it does only for water (at most 96
        // blocks; it is 768 or more in air).
        float underwater = (FogEnvironmentalEnd < 200.0 && FogEnvironmentalEnd > 8.0) ? 1.0 : 0.0;
        if (underwater > 0.5) {
            color.rgb = nvs_shadeWater(color.rgb, nvsViewPos, nvsWorldPos, GameTime, FogColor.rgb, underwater);
        }
    } else {
        // Cloud shadows. They are applied in proportion to how lit the pixel
        // already is, because the fragment stage receives one combined light
        // value, not separate sky and block terms: sunlit ground takes the full
        // shadow, caves and torchlight are left alone.
        float lit = clamp(nvs_luma(vertexColor.rgb), 0.0, 1.0);
        float shadow = mix(1.0, nvs_cloudShadow(nvsWorldPos.xz), smoothstep(0.25, 0.80, lit));
        color.rgb *= shadow;
    }
    #endif

    #ifndef OIT_ALPHA_ONLY
    color = mix(FogColor * vec4(1, 1, 1, color.a), color, chunkVisibility);
    #endif

    #ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
    #endif

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}

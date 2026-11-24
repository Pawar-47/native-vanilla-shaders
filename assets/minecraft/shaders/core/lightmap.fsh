#version 330
#extension GL_ARB_separate_shader_objects : require

#include <nvs:config.glsl>

// The lightmap: the 16 x 16 texture every lit surface multiplies its albedo by.
// It is drawn once per frame, so this is by far the cheapest place in the
// pipeline to change the whole game's lighting, and the least intrusive: no
// other program has to know about it.
//
// Everything that identifies the hour and the dimension arrives from the game in
// LightmapInfo. SkyLightColor is already the colour of the sunlight for the
// current celestial angle, the weather and the dimension; BlockLightTint is
// already the colour of torchlight there. The pack shapes the response curves
// rather than substituting its own idea of what time it is, so it stays correct
// under every sky the game can produce.

layout(std140) uniform LightmapInfo {
    float SkyFactor;
    float BlockFactor;
    float NightVisionFactor;
    float DarknessScale;
    float BossOverlayWorldDarkeningFactor;
    float BrightnessFactor;
    vec3 BlockLightTint;
    vec3 SkyLightColor;
    vec3 AmbientColor;
    vec3 NightVisionColor;
} lightmapInfo;

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

float get_brightness(float level) {
    return level / (4.0 - 3.0 * level);
}

vec3 notGamma(vec3 color) {
    float maxComponent = max(max(color.x, color.y), color.z);
    // Darkness effects can reduce every channel to exactly zero. Avoid the
    // 0/0 normalization in vanilla's notGamma curve, which otherwise produces
    // NaNs that can leak into the lightmap and contaminate the final frame.
    if (maxComponent <= 1e-5) {
        return vec3(0.0);
    }
    float maxInverted = 1.0f - maxComponent;
    float maxScaled = 1.0f - maxInverted * maxInverted * maxInverted * maxInverted;
    return color * (maxScaled / maxComponent);
}

float parabolicMixFactor(float level) {
    return (2.0 * level - 1.0) * (2.0 * level - 1.0);
}

float nvs_luma255(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    // Calculate block and sky brightness levels based on texture coordinates
    float block_level = floor(texCoord.x * 16) / 15;
    float sky_level = floor(texCoord.y * 16) / 15;

    float block_brightness = get_brightness(block_level) * lightmapInfo.BlockFactor;
    float sky_brightness = get_brightness(sky_level) * lightmapInfo.SkyFactor;

    // The curves. Sky light falls away a little faster, so that depth and caves
    // read as deep; block light holds on a little longer, so a torch actually
    // lights the room it is in instead of a bubble around itself.
    block_brightness = pow(clamp(block_brightness, 0.0, 1.0), NVS_BLOCKLIGHT_CURVE);
    sky_brightness = pow(clamp(sky_brightness, 0.0, 1.0), NVS_SKYLIGHT_CURVE);

    // Calculate ambient color with or without night vision
    vec3 nightVisionColor = lightmapInfo.NightVisionColor * lightmapInfo.NightVisionFactor;
    vec3 color = max(lightmapInfo.AmbientColor, nightVisionColor);

    // Add sky light: the sun, the moon and the sky's own ambient, all in the
    // colour the game chose for this moment.
    color += lightmapInfo.SkyLightColor * sky_brightness;

    // Add block light. Warm at the edges of its reach and neutral at its centre,
    // as vanilla does, but with slightly less neutralisation, so the warmth of
    // the dimension's light source survives to full brightness.
    vec3 BlockLightColor = mix(lightmapInfo.BlockLightTint, vec3(1.0), 0.88 * parabolicMixFactor(block_level));
    color += BlockLightColor * block_brightness;

    // Apply boss overlay darkening effect
    color = mix(color, color * vec3(0.7, 0.6, 0.6), lightmapInfo.BossOverlayWorldDarkeningFactor);

    // Apply darkness effect scale
    color = color - vec3(lightmapInfo.DarknessScale);

    // A very small ambient lift, so caves and the deep night keep a little air
    // instead of crushing to absolute black. It fades out as soon as anything is
    // lit, so it cannot wash the image out.
    float level = nvs_luma255(max(color, vec3(0.0)));
    color += vec3(NVS_BLACK_LIFT) * (1.0 - smoothstep(0.0, 0.30, level));

    // Apply brightness
    color = clamp(color, 0.0, 1.0);
    vec3 notGamma = notGamma(color);
    color = mix(color, notGamma, clamp(lightmapInfo.BrightnessFactor * NVS_GAMMA_STRENGTH, 0.0, 1.0));

    fragColor = vec4(color, 1.0);
}

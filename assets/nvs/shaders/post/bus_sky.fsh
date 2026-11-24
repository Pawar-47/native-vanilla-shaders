#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <nvs:bus_read.glsl>
#include <nvs:sky.glsl>
#include <nvs:water.glsl>

uniform sampler2D InSampler;
uniform sampler2D DepthSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

void main() {
    ivec2 size = textureSize(InSampler, 0);
    ivec2 pixel = clamp(ivec2(texCoord * vec2(size)), ivec2(0), size - 1);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    float depth = texelFetch(DepthSampler, pixel, 0).r;
    // Opaque terrain only needs projection, view, sky and fog data. The four
    // sun rows are decoded only for sky pixels and translucent cloud layers.
    NvsBus bus = nvs_readBus(InSampler, depth <= 0.0 || scene.a < 0.99);
    float waterData = 0.0;
    bool drawn = depth > 0.0;
    if (drawn && nvs_isWaterMarker(scene, pixel.x)) {
        waterData = scene.b;
        vec4 right = texelFetch(InSampler, ivec2(min(pixel.x + 1, size.x - 1), pixel.y), 0);
        vec4 left = texelFetch(InSampler, ivec2(max(pixel.x - 1, 0), pixel.y), 0);
        bool leftIsWater = pixel.x >= 2
            && nvs_isWaterMarker(texelFetch(InSampler, ivec2(pixel.x - 2, pixel.y), 0), pixel.x - 2);
        scene = leftIsWater ? 0.5 * (left + right) : right;
    } else if (drawn && (pixel.x & 1) == 1 && pixel.x > 0) {
        vec4 leftMarker = texelFetch(InSampler, ivec2(pixel.x - 1, pixel.y), 0);
        if (nvs_isWaterMarker(leftMarker, pixel.x - 1)) waterData = leftMarker.b;
    }

    bool inAir = bus.present && nvs_busCameraInAir(bus);
    vec3 color = scene.rgb;

    if (inAir) {
        vec3 viewPosition = nvs_busViewPosition(bus, texCoord, depth > 0.0 ? depth : 1e-6);
        vec3 worldRelative = bus.viewToWorld * viewPosition;
        vec3 worldDirection = normalize(worldRelative);
        float cameraY = float(CameraBlockPos.y) - CameraOffset.y;
        float worldY = worldRelative.y + cameraY;

        // Clouds cover the even-column water markers because they are blended
        // after translucent terrain. Reconstruct the cloud-over-water sample
        // from the two odd neighbours before the atmosphere is applied.
        if (depth > 0.0 && waterData == 0.0 && (pixel.x & 1) == 0
                && scene.a > 252.5 / 255.0 && worldY > NVS_CLOUD_HEIGHT - 2.0) {
            vec4 left = texelFetch(InSampler, ivec2(max(pixel.x - 1, 0), pixel.y), 0);
            vec4 right = texelFetch(InSampler, ivec2(min(pixel.x + 1, size.x - 1), pixel.y), 0);
            scene.rgb = 0.5 * (left.rgb + right.rgb);
            color = scene.rgb;
        }

        vec3 sky = nvs_skyGradient(worldDirection, bus.skyColor, bus.fogColor);
        float alpha = scene.a;
        vec3 skyWithSun = sky;
        // Opaque terrain only needs the horizon/zenith colour. The procedural
        // night field and solar lobe are evaluated for sky and translucent
        // layers only, avoiding several noise taps across most of the screen.
        if (depth <= 0.0 || alpha < 0.99) {
            float night = 1.0 - smoothstep(0.010, 0.075, nvs_luma(bus.skyColor));
            skyWithSun += nvs_nightSky(worldDirection, night);
            skyWithSun += nvs_sunGlow(worldDirection, bus.sunDirection, bus.rainBrightness);
        }

        if (depth <= 0.0) {
            // The cleared frame is FogColor; preserve the vanilla moon, stars
            // and sunrise glow already drawn over it.
            color = skyWithSun + max(scene.rgb - bus.fogColor, vec3(0.0));
        } else if (alpha < 0.99 && worldY > NVS_CLOUD_HEIGHT - 2.0) {
            // Clouds are translucent over the clear colour. Replace only
            // the uncovered part with the same sky that the post pass drew.
            color = scene.rgb + (1.0 - alpha) * (skyWithSun - bus.fogColor);
        } else {
            // Remove vanilla's fog contribution, then add the stronger
            // aerial perspective and loaded-world edge fade.
            float vanillaFog = nvs_vanillaFog(bus, worldRelative);
            float amount = nvs_atmosphereFog(bus, worldRelative, vanillaFog);
            vec3 surface = scene.rgb - (1.0 - alpha) * bus.fogColor
                         - alpha * vanillaFog * bus.fogColor;
            float keep = (1.0 - amount) / max(1.0 - vanillaFog, 1e-4);
            color = surface * keep + alpha * amount * sky + (1.0 - alpha) * skyWithSun;
        }
    }

    // The bus is transport data, not a visible one-pixel stripe.
    if (pixel.x == 0) {
        color = texelFetch(InSampler, ivec2(min(1, size.x - 1), pixel.y), 0).rgb;
        waterData = 0.0;
    }
    float tag = waterData == 0.0 ? 1.0 : waterData > 0.75 ? 0.75 : waterData;
    fragColor = vec4(clamp(color, 0.0, 1.0), tag);
}

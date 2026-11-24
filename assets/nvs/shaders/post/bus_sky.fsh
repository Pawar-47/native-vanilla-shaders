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
            // Fog shape is defined in camera/view axes, not world XZ.
            float vanillaFog = nvs_vanillaFog(bus, viewPosition);
            float amount = nvs_atmosphereFog(bus, viewPosition, vanillaFog);
            vec3 surface = scene.rgb - (1.0 - alpha) * bus.fogColor
                         - alpha * vanillaFog * bus.fogColor;
            float keep = (1.0 - amount) / max(1.0 - vanillaFog, 1e-4);
            color = surface * keep + alpha * amount * sky + (1.0 - alpha) * skyWithSun;
        }

        // Procedural stylised cloud layer. The native cloud mesh is deliberately
        // transparent; intersect each sky ray with the configured cloud plane
        // and draw soft, rounded cumulus lobes here instead of vanilla boxes.
        bool cloudCandidate = depth <= 0.0
                          || (alpha < 0.99 && abs(worldY - NVS_CLOUD_HEIGHT) < 48.0);
        if (cloudCandidate && abs(worldDirection.y) > 0.012) {
            vec3 cameraWorld = vec3(CameraBlockPos) - CameraOffset;
            float cloudTravel = (NVS_CLOUD_HEIGHT - cameraY) / worldDirection.y;
            if (cloudTravel > 0.0 && cloudTravel < 6000.0) {
                vec2 cloudXZ = cameraWorld.xz + worldDirection.xz * cloudTravel;
                float density = nvs_cloudPuffDensity(cloudXZ);
                float cloudAlpha = smoothstep(NVS_CLOUD_CUTOFF - 0.055,
                                              NVS_CLOUD_CUTOFF + 0.13, density);
                cloudAlpha *= smoothstep(0.08, 0.30, density);
                cloudAlpha *= smoothstep(0.008, 0.055, abs(worldDirection.y));

                if (cloudAlpha > 0.002) {
                    float sunElevation = smoothstep(-0.12, 0.22, bus.sunDirection.y);
                    float sunStrength = max(bus.sunDirection.y, 0.0);
                    vec3 coolUnderside = mix(vec3(0.39, 0.49, 0.65),
                                             vec3(0.62, 0.67, 0.75), sunElevation);
                    vec3 warmLitTop = vec3(1.00, 0.965, 0.885)
                                    * (0.86 + 0.14 * sunStrength);
                    float litForm = smoothstep(0.34, 0.82, density);
                    vec3 cloudColor = mix(coolUnderside, warmLitTop, litForm);
                    cloudColor *= nvs_cloudShade(density, 0.55);
                    color = mix(color, cloudColor, cloudAlpha * 0.96);
                }
            }
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

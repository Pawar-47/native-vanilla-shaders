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

void nvs_drawCloudLayer(inout vec3 baseColor, vec3 rayDirection,
                          vec2 cameraXZ, float cameraY, float cloudHeight,
                          float scale, vec2 seed, float opacity,
                          vec3 sunDirection) {
    if (rayDirection.y <= 0.003) return;
    float travel = (cloudHeight - cameraY) / rayDirection.y;
    if (travel <= 0.0 || travel >= 26000.0) return;

    vec2 cloudXZ = cameraXZ + rayDirection.xz * travel;
    float density = nvs_cloudLayerDensity(cloudXZ, scale, seed);
    float coverage = smoothstep(0.545, 0.695, density);
    coverage *= smoothstep(0.006, 0.032, rayDirection.y);
    float alpha = coverage * opacity;
    if (alpha <= 0.002) return;

    // A cheap finite-difference normal gives each irregular bank a lit crown,
    // shaded folds and soft side volume instead of a flat 2-D stamp.
    float stepSize = scale * 0.018;
    float dx = nvs_cloudLayerDensity(cloudXZ + vec2(stepSize, 0.0), scale, seed)
             - nvs_cloudLayerDensity(cloudXZ - vec2(stepSize, 0.0), scale, seed);
    float dz = nvs_cloudLayerDensity(cloudXZ + vec2(0.0, stepSize), scale, seed)
             - nvs_cloudLayerDensity(cloudXZ - vec2(0.0, stepSize), scale, seed);
    vec3 normal = normalize(vec3(-dx * 8.0, 0.82, -dz * 8.0));
    vec3 lightDir = normalize(vec3(sunDirection.x, max(sunDirection.y, 0.16), sunDirection.z));
    float diffuse = max(dot(normal, lightDir), 0.0);
    float sunUp = smoothstep(-0.12, 0.24, sunDirection.y);

    vec3 underside = mix(vec3(0.38, 0.46, 0.59),
                         vec3(0.61, 0.68, 0.77), sunUp);
    vec3 crown = vec3(1.00, 0.975, 0.91) * (0.90 + 0.10 * max(sunDirection.y, 0.0));
    float lighting = smoothstep(0.12, 0.88, diffuse);
    vec3 cloudColor = mix(underside, crown, lighting);
    float body = smoothstep(0.55, 0.78, density);
    cloudColor *= 0.82 + 0.20 * body + 0.10 * diffuse;
    baseColor = mix(baseColor, cloudColor, alpha);
}

void main() {
    ivec2 size = textureSize(InSampler, 0);
    ivec2 pixel = clamp(ivec2(texCoord * vec2(size)), ivec2(0), size - 1);
    vec4 scene = texelFetch(InSampler, pixel, 0);
    float depth = texelFetch(DepthSampler, pixel, 0).r;
    // Opaque terrain only needs projection, view, sky and fog data. The four
    // sun rows are decoded only for sky pixels and translucent cloud layers.
    NvsBus bus = nvs_readBus(InSampler, true);
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

        // Three independently seeded cloud decks create depth: nearby broken
        // cumulus, smaller mid-distance banks and sparse high/horizon fragments.
        // The layers share the same world-anchored field used by reflections.
        bool cloudCandidate = depth <= 0.0
                          || (alpha < 0.99 && abs(worldY - NVS_CLOUD_HEIGHT) < 48.0);
        if (cloudCandidate) {
            vec3 cameraWorld = vec3(CameraBlockPos) - CameraOffset;
            nvs_drawCloudLayer(color, worldDirection, cameraWorld.xz, cameraY,
                               NVS_CLOUD_HEIGHT, 92.0, vec2(0.0, 0.0), 0.76,
                               bus.sunDirection);
            nvs_drawCloudLayer(color, worldDirection, cameraWorld.xz, cameraY,
                               252.0, 148.0, vec2(31.7, 18.3), 0.58,
                               bus.sunDirection);
            nvs_drawCloudLayer(color, worldDirection, cameraWorld.xz, cameraY,
                               326.0, 214.0, vec2(83.1, 47.9), 0.43,
                               bus.sunDirection);
        }

        // Reconstruct a view-space face normal from the depth buffer. The
        // native terrain vertex format has no normal attribute, but adjacent
        // depth samples provide a useful screen-space approximation for block
        // faces and flat vegetation cards. This adds directional form without
        // a shadow map or another render target.
        if (depth > 0.0 && alpha >= 0.99 && waterData == 0.0) {
            ivec2 pxL = ivec2(max(pixel.x - 1, 0), pixel.y);
            ivec2 pxR = ivec2(min(pixel.x + 1, size.x - 1), pixel.y);
            ivec2 pxD = ivec2(pixel.x, max(pixel.y - 1, 0));
            ivec2 pxU = ivec2(pixel.x, min(pixel.y + 1, size.y - 1));
            float dL = texelFetch(DepthSampler, pxL, 0).r;
            float dR = texelFetch(DepthSampler, pxR, 0).r;
            float dD = texelFetch(DepthSampler, pxD, 0).r;
            float dU = texelFetch(DepthSampler, pxU, 0).r;
            vec3 pL = nvs_busViewPosition(bus, (vec2(pxL) + 0.5) / vec2(size), max(dL > 0.0 ? dL : depth, 1e-6));
            vec3 pR = nvs_busViewPosition(bus, (vec2(pxR) + 0.5) / vec2(size), max(dR > 0.0 ? dR : depth, 1e-6));
            vec3 pD = nvs_busViewPosition(bus, (vec2(pxD) + 0.5) / vec2(size), max(dD > 0.0 ? dD : depth, 1e-6));
            vec3 pU = nvs_busViewPosition(bus, (vec2(pxU) + 0.5) / vec2(size), max(dU > 0.0 ? dU : depth, 1e-6));
            vec3 dx = abs(dR - depth) < abs(dL - depth) ? pR - viewPosition : viewPosition - pL;
            vec3 dy = abs(dU - depth) < abs(dD - depth) ? pU - viewPosition : viewPosition - pD;
            vec3 normalView = normalize(cross(dx, dy));
            if (dot(normalView, -viewPosition) < 0.0) normalView = -normalView;
            vec3 normalWorld = normalize(bus.viewToWorld * normalView);

            float sunAboveHorizon = smoothstep(-0.10, 0.18, bus.sunDirection.y);
            float directLight = max(dot(normalWorld, bus.sunDirection), 0.0) * sunAboveHorizon;
            float skyFill = 0.5 + 0.5 * max(normalWorld.y, 0.0);
            float nightFill = 1.0 - sunAboveHorizon;
            float directional = 0.70 + directLight * 0.38 + skyFill * 0.10
                              + nightFill * skyFill * 0.06;
            color *= clamp(directional, 0.66, 1.16);
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

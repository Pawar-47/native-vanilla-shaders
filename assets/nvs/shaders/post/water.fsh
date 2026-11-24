#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <nvs:bus_read.glsl>
#include <nvs:water.glsl>

uniform sampler2D InSampler;
uniform sampler2D MainSampler;
uniform sampler2D DepthSampler;

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

vec3 nvs_screenReflection(NvsBus bus, vec3 origin, vec3 direction) {
    float stepLength = 0.3 + 0.01 * length(origin);
    vec3 previous = origin;
    vec3 position = origin;
    for (int i = 0; i < NVS_WATER_SSR_STEPS; ++i) {
        position += direction * stepLength;
        vec4 clip = bus.projection * vec4(position, 1.0);
        if (clip.w <= 0.0) break;
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;
        float depth = texture(DepthSampler, uv).r;
        if (depth > 0.0) {
            float behind = nvs_busViewPosition(bus, uv, depth).z - position.z;
            if (behind > 0.12 && behind < stepLength * 3.0 + 0.5) {
                vec3 a = previous;
                vec3 b = position;
                for (int j = 0; j < NVS_WATER_SSR_REFINE_STEPS; ++j) {
                    vec3 middle = 0.5 * (a + b);
                    vec4 projected = bus.projection * vec4(middle, 1.0);
                    if (projected.w <= 0.0) {
                        a = middle;
                        continue;
                    }
                    vec2 muv = projected.xy / projected.w * 0.5 + 0.5;
                    if (any(lessThan(muv, vec2(0.0))) || any(greaterThan(muv, vec2(1.0)))) {
                        a = middle;
                        continue;
                    }
                    float md = texture(DepthSampler, muv).r;
                    if (md > 0.0 && nvs_busViewPosition(bus, muv, md).z > middle.z) {
                        b = middle;
                        uv = muv;
                    } else {
                        a = middle;
                    }
                }
                vec2 edge = smoothstep(vec2(0.0), vec2(0.08), min(uv, 1.0 - uv));
                return vec3(uv, edge.x * edge.y * (1.0 - float(i) / float(NVS_WATER_SSR_STEPS)));
            }
        }
        previous = position;
        stepLength *= NVS_WATER_SSR_STEP_GROWTH;
    }
    return vec3(0.0);
}

void main() {
    ivec2 size = textureSize(InSampler, 0);
    ivec2 pixel = clamp(ivec2(texCoord * vec2(size)), ivec2(0), size - 1);
    vec4 tagged = texelFetch(InSampler, pixel, 0);
    fragColor = vec4(tagged.rgb, 1.0);
    NvsBus bus = nvs_readBus(MainSampler);
    if (!bus.present || !nvs_busCameraInAir(bus)) return;

    float depth = texelFetch(DepthSampler, pixel, 0).r;
    vec3 viewPosition = nvs_busViewPosition(bus, texCoord, max(depth, 1e-6));
    vec3 worldRelative = bus.viewToWorld * viewPosition;
    // Evaluate derivatives uniformly across the frame before testing the water tag.
    vec3 worldDx = dFdx(worldRelative);
    vec3 worldDy = dFdy(worldRelative);
    vec3 normalRaw = cross(worldDx, worldDy);
    float pixelFootprint = max(length(worldDx.xz), length(worldDy.xz));
    float normalLength = length(normalRaw);
    vec3 faceNormal = normalLength > 1e-5 ? normalRaw / normalLength : vec3(0.0, 1.0, 0.0);
    if (tagged.a > 0.9 || depth <= 0.0) return;

    bool top = tagged.a > 0.375;
    vec3 cameraPosition = vec3(CameraBlockPos) - CameraOffset;
    vec3 worldPosition = worldRelative + cameraPosition;
    vec3 viewWorld = normalize(worldRelative);
    float distanceToSurface = length(viewPosition);
    if (dot(faceNormal, worldRelative) > 0.0) faceNormal = -faceNormal;

    vec3 normal = faceNormal;
    float t = nvs_waveTime(GameTime);
    float farWaveFade = 1.0 - smoothstep(NVS_WATER_FAR_FADE_START, NVS_WATER_FAR_FADE_END, distanceToSurface);
    float grazingFade = mix(0.15, 1.0, smoothstep(0.02, 0.25, abs(viewWorld.y)));
    float waveStrength = NVS_WATER_WAVE_STRENGTH * mix(0.42, 1.0, farWaveFade) * grazingFade;
    if (top) {
        normal = nvs_waterNormal(worldPosition.xz, t, waveStrength, pixelFootprint);
        if (faceNormal.y < 0.0) normal.y = -normal.y;
    }

    vec3 reflectedWorld = reflect(viewWorld, normal);
    if (top && reflectedWorld.y * normal.y < 0.0) reflectedWorld.y = -reflectedWorld.y;
    vec3 reflection = nvs_reflectedSky(reflectedWorld, worldPosition.xz, worldPosition.y, bus.skyColor, bus.fogColor);
    // The fallback sky needs the actual solar disc as well as the narrow
    // wave glint; otherwise off-screen sun reflections disappear at the
    // horizon and leave a flat patch where the sun should be.
    float sunAngle = acos(clamp(dot(reflectedWorld, bus.sunDirection), -1.0, 1.0));
    float sunDisc = 1.0 - smoothstep(0.0042, 0.0052, sunAngle);
    float sunCorona = exp(-sunAngle * 42.0) * 0.24 + exp(-sunAngle * 13.0) * 0.075;
    float sunGlint = pow(max(dot(reflectedWorld, bus.sunDirection), 0.0), 320.0) * 0.45;
    float sunVisibility = smoothstep(-0.10, 0.08, bus.sunDirection.y);
    reflection += vec3(1.0, 0.82, 0.58)
                * (sunDisc * 1.8 + sunCorona + sunGlint)
                * bus.rainBrightness * sunVisibility;

    mat3 worldToView = transpose(bus.viewToWorld);
    vec3 viewFace = worldToView * faceNormal;
    vec3 viewNormal = worldToView * normal;
    // March the flat-surface reflection for stable shoreline hits; waves only
    // perturb the lookup position, avoiding large misses at grazing angles.
    vec3 rayDirection = normalize(reflect(normalize(viewPosition), viewFace));
    vec3 hit = nvs_screenReflection(bus, viewPosition + viewFace * 0.05, rayDirection);
    if (hit.z > 0.0) {
        vec2 ripple = (viewNormal.xy - viewFace.xy) * 0.035;
        vec2 uv = hit.xy + ripple;
        bool inside = all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)));
        vec4 directHit = texture(InSampler, hit.xy);
        // Do not reflect another tagged water pixel back into this surface.
        // That feedback reads as dark patches and unstable recursive mirrors.
        if (directHit.a > 0.9) {
            vec4 shiftedHit = inside ? texture(InSampler, uv) : vec4(0.0);
            vec3 mirrored = inside && shiftedHit.a > 0.9 ? shiftedHit.rgb : directHit.rgb;
            reflection = mix(reflection, mirrored, hit.z);
        }
    }

    float sphericalFog = smoothstep(bus.fogEnvironmentalStart, max(bus.fogEnvironmentalEnd, bus.fogEnvironmentalStart + 1.0), distanceToSurface);
    float cylindricalDistance = max(length(viewPosition.xz), abs(viewPosition.y));
    float renderFog = smoothstep(bus.fogRenderDistanceStart, max(bus.fogRenderDistanceEnd, bus.fogRenderDistanceStart + 1.0), cylindricalDistance);
    float fogAmount = max(sphericalFog, renderFog);
    vec3 distantSky = nvs_skyGradient(viewWorld, bus.skyColor, bus.fogColor);
    reflection = mix(reflection, distantSky, fogAmount);

    vec2 distortion = (viewNormal.xy - viewFace.xy) * 0.018;
    vec2 shiftedUV = clamp(texCoord + distortion, vec2(0.001), vec2(0.999));
    vec4 under = texture(InSampler, shiftedUV);
    vec3 refraction = under.a < 0.9 ? under.rgb : tagged.rgb;
    float NoV = clamp(dot(normal, -viewWorld), 0.0, 1.0);
    float path = 1.0 / max(NoV, 0.15);
    vec3 absorption = vec3(0.30, 0.12, 0.08) * (0.55 + NVS_WATER_ABSORB * 8.0);
    refraction *= mix(exp(-absorption * path), vec3(1.0), fogAmount);

    float fresnel = NVS_WATER_F0 + (1.0 - NVS_WATER_F0) * pow(1.0 - clamp(dot(normalize(mix(faceNormal, normal, 0.25)), -viewWorld), 0.0, 1.0), 5.0);
    if (!top) fresnel *= 0.55;
    vec3 finalColor = mix(refraction, reflection, fresnel);

    // Whitecaps are drawn in the post water pass (the above-water terrain
    // pass deliberately leaves the vanilla surface untouched for SSR).
    if (top && NVS_WATER_FOAM > 0.0) {
        float crest = smoothstep(NVS_WATER_FOAM_THRESHOLD, 1.0,
                                 nvs_waterCrest(worldPosition.xz, t, pixelFootprint));
        vec2 foamDrift = vec2(cos(t * 0.5), sin(t * 0.5)) * 2.5;
        float broken = nvs_valueNoise(worldPosition.xz * 1.9 + foamDrift);
        float foam = crest * smoothstep(0.35, 0.85, broken) * mix(0.45, 1.0, farWaveFade);
        finalColor += vec3(NVS_WATER_FOAM) * foam;
    }
    fragColor = vec4(finalColor, 1.0);
}

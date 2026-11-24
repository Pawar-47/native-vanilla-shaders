#ifndef NVS_BUS_READ_GLSL
#define NVS_BUS_READ_GLSL

#include <nvs:bus.glsl>
#include <nvs:config.glsl>

// Decoded values transferred by the sky and celestial core programs.
struct NvsBus {
    bool present;
    mat4 projection;
    mat4 inverseProjection;
    mat3 viewToWorld;
    bool zeroToOneDepth;
    vec3 skyColor;
    vec3 fogColor;
    float fogEnvironmentalStart;
    float fogEnvironmentalEnd;
    float fogRenderDistanceStart;
    float fogRenderDistanceEnd;
    float fogSkyEnd;
    float fogCloudsEnd;
    vec3 sunDirection;
    float rainBrightness;
};

vec4 nvs_busTexel(sampler2D source, int row, bool fromBottom) {
    int height = textureSize(source, 0).y;
    return texelFetch(source, ivec2(0, fromBottom ? row : height - 1 - row), 0);
}

bool nvs_busIsMarker(vec4 value) {
    return all(lessThan(abs(value.rgb - vec3(1.0, 0.0, 1.0)), vec3(0.01)));
}

NvsBus nvs_readBus(sampler2D source) {
    NvsBus bus;
    int height = textureSize(source, 0).y;
    bool fromBottom = nvs_busIsMarker(texelFetch(source, ivec2(0, 0), 0));
    bus.present = fromBottom || nvs_busIsMarker(texelFetch(source, ivec2(0, height - 1), 0));
    if (!bus.present) {
        return bus;
    }

    mat4 view;
    for (int i = 0; i < 16; ++i) {
        bus.projection[i / 4][i % 4] =
            nvs_bus_unpackFloat(nvs_busTexel(source, NVS_BUS_ROW_PROJ + i, fromBottom));
        view[i / 4][i % 4] =
            nvs_bus_unpackFloat(nvs_busTexel(source, NVS_BUS_ROW_VIEW + i, fromBottom));
    }
    bus.inverseProjection = inverse(bus.projection);
    bus.viewToWorld = transpose(mat3(view));
    bus.zeroToOneDepth = bus.projection[2][2] < 0.5;
    bus.skyColor = nvs_busTexel(source, NVS_BUS_ROW_SKY, fromBottom).rgb;
    bus.fogColor = nvs_busTexel(source, NVS_BUS_ROW_FOG, fromBottom).rgb;

    float fog[6];
    for (int i = 0; i < 6; ++i) {
        fog[i] = nvs_bus_unpackFloat(nvs_busTexel(source, NVS_BUS_ROW_FOG_PARAMS + i, fromBottom));
    }
    bus.fogEnvironmentalStart = fog[0];
    bus.fogEnvironmentalEnd = fog[1];
    bus.fogRenderDistanceStart = fog[2];
    bus.fogRenderDistanceEnd = fog[3];
    bus.fogSkyEnd = fog[4];
    bus.fogCloudsEnd = fog[5];

    vec3 sunView = vec3(
        nvs_bus_unpackSigned(nvs_busTexel(source, NVS_BUS_ROW_SUN, fromBottom)),
        nvs_bus_unpackSigned(nvs_busTexel(source, NVS_BUS_ROW_SUN + 1, fromBottom)),
        nvs_bus_unpackSigned(nvs_busTexel(source, NVS_BUS_ROW_SUN + 2, fromBottom))
    );
    bus.sunDirection = normalize(bus.viewToWorld * sunView);
    bus.rainBrightness = nvs_bus_unpackSigned(
        nvs_busTexel(source, NVS_BUS_ROW_SUN + 3, fromBottom)) * 0.5 + 0.5;
    return bus;
}

// Reconstruct a camera-relative view-space point from screen UV and depth.
vec3 nvs_busViewPosition(NvsBus bus, vec2 uv, float depth) {
    float z = bus.zeroToOneDepth ? depth : depth * 2.0 - 1.0;
    vec4 p = bus.inverseProjection * vec4(uv * 2.0 - 1.0, z, 1.0);
    return p.xyz / p.w;
}

// Reconstruct a stable view ray from the far plane. Using a near-plane point
// is incorrect because ProjMat includes view bobbing translation; the far-plane
// direction is effectively translation-free.
vec3 nvs_busViewDirection(NvsBus bus, vec2 uv) {
    float farZ = bus.zeroToOneDepth ? 1e-6 : -0.999998;
    vec4 p = bus.inverseProjection * vec4(uv * 2.0 - 1.0, farZ, 1.0);
    return normalize(p.xyz / p.w);
}

vec3 nvs_busWorldDirection(NvsBus bus, vec2 uv) {
    return normalize(bus.viewToWorld * nvs_busViewDirection(bus, uv));
}

float nvs_linearFog(float distanceValue, float startValue, float endValue) {
    return clamp((distanceValue - startValue) / max(endValue - startValue, 1e-3), 0.0, 1.0);
}

float nvs_vanillaFog(NvsBus bus, vec3 viewPosition) {
    float spherical = length(viewPosition);
    float cylindrical = max(length(viewPosition.xz), abs(viewPosition.y));
    float fogValue = max(nvs_linearFog(spherical, bus.fogEnvironmentalStart, bus.fogEnvironmentalEnd),
                          nvs_linearFog(cylindrical, bus.fogRenderDistanceStart, bus.fogRenderDistanceEnd));
    // Match the smoothstep curve used by the pack's replacement fog.glsl;
    // the post pass must remove exactly the fog already mixed by core shaders.
    return fogValue * fogValue * (3.0 - 2.0 * fogValue);
}

float nvs_atmosphereFog(NvsBus bus, vec3 viewPosition, float vanillaFog) {
    float cylindrical = max(length(viewPosition.xz), abs(viewPosition.y));
    float renderEnd = max(bus.fogRenderDistanceEnd, 1.0);
    float edge = smoothstep(0.50, 0.95, cylindrical / renderEnd);
    float haze = 1.0 - exp(-length(viewPosition) / max(NVS_ATMOSPHERE_HAZE_DISTANCE, 1.0));
    return 1.0 - (1.0 - max(vanillaFog, edge)) * (1.0 - haze);
}

bool nvs_busCameraInAir(NvsBus bus) {
    return abs(bus.fogSkyEnd - min(bus.fogRenderDistanceEnd, 512.0)) < 1.0
        && bus.fogSkyEnd < bus.fogEnvironmentalEnd - 1.0;
}

#endif

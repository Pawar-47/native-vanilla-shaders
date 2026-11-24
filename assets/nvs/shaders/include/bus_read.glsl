#ifndef NVS_BUS_READ_GLSL
#define NVS_BUS_READ_GLSL

#include <nvs:bus.glsl>
#include <nvs:config.glsl>

// Decoded values transferred by the sky and celestial core programs.
struct NvsBus {
    bool present;
    mat4 projection;
    mat3 viewToWorld;
    bool zeroToOneDepth;
    vec3 skyColor;
    vec3 fogColor;
    float fogAlpha;
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

    mat3 view;
    for (int i = 0; i < 16; ++i) {
        bus.projection[i / 4][i % 4] =
            nvs_bus_unpackFloat(nvs_busTexel(source, NVS_BUS_ROW_PROJ + i, fromBottom));
    }
    for (int i = 0; i < 9; ++i) {
        view[i / 3][i % 3] =
            nvs_bus_unpackFloat(nvs_busTexel(source, NVS_BUS_ROW_VIEW + i, fromBottom));
    }
    bus.viewToWorld = transpose(view);
    bus.zeroToOneDepth = bus.projection[2][2] < 0.5;
    bus.skyColor = nvs_busTexel(source, NVS_BUS_ROW_SKY, fromBottom).rgb;
    vec4 fogSample = nvs_busTexel(source, NVS_BUS_ROW_FOG, fromBottom);
    bus.fogColor = fogSample.rgb;
    bus.fogAlpha = fogSample.a;

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
// ProjMat is the standard perspective matrix used by Minecraft's world
// pipelines. Solving its Z/W rows and then its 2x2 XY block avoids a full 4x4
// matrix inverse in every fragment of the full-resolution atmosphere pass.
// The equations work for both OpenGL [-1,1] and Vulkan [0,1] depth ranges.
vec3 nvs_busViewPosition(NvsBus bus, vec2 uv, float depth) {
    float ndcZ = bus.zeroToOneDepth ? depth : depth * 2.0 - 1.0;
    float p22 = bus.projection[2][2];
    float p23 = bus.projection[2][3];
    float p32 = bus.projection[3][2];
    float p33 = bus.projection[3][3];
    float denominator = ndcZ * p23 - p22;
    float viewZ = (p32 - ndcZ * p33) / (abs(denominator) > 1e-7 ? denominator : (denominator < 0.0 ? -1e-7 : 1e-7));
    float clipW = p23 * viewZ + p33;

    vec2 ndcXY = uv * 2.0 - 1.0;
    vec2 rhs = ndcXY * clipW - vec2(
        bus.projection[2][0] * viewZ + bus.projection[3][0],
        bus.projection[2][1] * viewZ + bus.projection[3][1]
    );
    float a = bus.projection[0][0];
    float b = bus.projection[1][0];
    float c = bus.projection[0][1];
    float d = bus.projection[1][1];
    float determinant = a * d - b * c;
    float safeDeterminant = abs(determinant) > 1e-7 ? determinant : (determinant < 0.0 ? -1e-7 : 1e-7);
    vec2 viewXY = vec2(d * rhs.x - b * rhs.y, a * rhs.y - c * rhs.x) / safeDeterminant;
    return vec3(viewXY, viewZ);
}

// Reconstruct a stable view ray from the far plane. Using a near-plane point
// is incorrect because ProjMat includes view bobbing translation; the far-plane
// direction is effectively translation-free.
vec3 nvs_busViewDirection(NvsBus bus, vec2 uv) {
    float farDepth = bus.zeroToOneDepth ? 1e-6 : 1e-6;
    return normalize(nvs_busViewPosition(bus, uv, farDepth));
}

vec3 nvs_busWorldDirection(NvsBus bus, vec2 uv) {
    return normalize(bus.viewToWorld * nvs_busViewDirection(bus, uv));
}

float nvs_linearFog(float distanceValue, float startValue, float endValue) {
    return clamp((distanceValue - startValue) / max(endValue - startValue, 1e-3), 0.0, 1.0);
}

float nvs_vanillaFog(NvsBus bus, vec3 worldRelativePosition) {
    float spherical = length(worldRelativePosition);
    float cylindrical = max(length(worldRelativePosition.xz), abs(worldRelativePosition.y));
    float fogValue = max(nvs_linearFog(spherical, bus.fogEnvironmentalStart, bus.fogEnvironmentalEnd),
                          nvs_linearFog(cylindrical, bus.fogRenderDistanceStart, bus.fogRenderDistanceEnd));
    // Match the smoothstep curve used by the pack's replacement fog.glsl;
    // the post pass must remove exactly the fog already mixed by core shaders.
    return fogValue * fogValue * (3.0 - 2.0 * fogValue) * bus.fogAlpha;
}

float nvs_atmosphereFog(NvsBus bus, vec3 worldRelativePosition, float vanillaFog) {
    float cylindrical = max(length(worldRelativePosition.xz), abs(worldRelativePosition.y));
    float renderEnd = max(bus.fogRenderDistanceEnd, 1.0);
    float edge = smoothstep(0.50, 0.95, cylindrical / renderEnd);
    float haze = 1.0 - exp(-length(worldRelativePosition) / max(NVS_ATMOSPHERE_HAZE_DISTANCE, 1.0));
    return 1.0 - (1.0 - max(vanillaFog, edge)) * (1.0 - haze);
}

bool nvs_busCameraInAir(NvsBus bus) {
    return abs(bus.fogSkyEnd - min(bus.fogRenderDistanceEnd, 512.0)) < 1.0
        && bus.fogSkyEnd < bus.fogEnvironmentalEnd - 1.0;
}

#endif

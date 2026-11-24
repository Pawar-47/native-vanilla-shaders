#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:sample_lightmap.glsl>
#include <minecraft:terrainglobals.glsl>
#ifndef MULTIDRAW_TERRAIN
    #include <minecraft:chunksection.glsl>
#endif
#include <nvs:config.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;
layout(location = 2) in vec2 UV0;
layout(location = 3) in ivec2 UV2;
#ifdef MULTIDRAW_TERRAIN
layout(location = 4) in ivec3 ChunkPosition;
layout(location = 5) in float ChunkVisibility;
#endif

#ifndef OIT_ALPHA_ONLY
uniform sampler2D Sampler2;
#endif

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
layout(location = 2) out vec4 vertexColor;
layout(location = 3) out vec2 texCoord0;
layout(location = 4) out float chunkVisibility;
// Absolute world position of the vertex, for the water waves and the cloud
// shadows. Both must be anchored to the world, not to the camera.
layout(location = 5) out vec3 nvsWorldPos;
// The vertex relative to the eye: the camera is the origin, so this is the
// view vector the water's Fresnel term needs.
layout(location = 6) out vec3 nvsViewPos;
// The raw pre-lighting vertex colour. It carries the biome tint, which is the
// only thing that tells water from slime (both have the same texture alpha).
layout(location = 7) out vec4 nvsTint;

void main() {
    // Absolute world position: ChunkPosition is the section's world origin.
    vec3 worldPos = Position + vec3(ChunkPosition);

    vec3 pos = Position + (ChunkPosition - CameraBlockPos) + CameraOffset;

    // Sway for plants.
    //
    // The terrain program is not told which block it draws, so this uses the
    // three properties that identify a plant in the native vertex data: it is
    // in the cutout layer, it is tinted by the biome (a Color that is not grey),
    // and its vertices are off the block grid, which cross models are and full
    // blocks are not. A grass block is tinted and cutout but on the grid, so it
    // stays still. This is the same discrimination the community technique
    // documents; whole plants move, with a phase that varies with height, which
    // is what the data allows: neither end of a plant can be identified.
    #ifdef ALPHA_CUTOUT
    if (ALPHA_CUTOUT > 0.4) {
        float tintSpread = max(max(Color.r, Color.g), Color.b) - min(min(Color.r, Color.g), Color.b);
        vec2 cell = fract(worldPos.xz);
        float offGrid = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
        if (tintSpread > 0.035 && offGrid > 0.02) {
            // 60 whole cycles per day, so the day's wrap is seamless.
            float windTime = GameTime * 6.2831853 * 60.0;
            float phase = worldPos.x * 0.21 + worldPos.z * 0.17;
            float sway = sin(windTime + phase + worldPos.y * 0.9) * NVS_PLANT_SWAY;
            pos.x += sway * 0.78;
            pos.z += sway * 0.62;
        }
    }
    #endif

    gl_Position = ProjMat * ModelViewMat * vec4(pos, 1.0);

    sphericalVertexDistance = fog_spherical_distance(pos);
    cylindricalVertexDistance = fog_cylindrical_distance(pos);
    #ifndef OIT_ALPHA_ONLY
    vec4 lightmap = sample_lightmap(Sampler2, UV2);
    #ifdef ALPHA_CUTOUT
    // Biome-tinted cutout foliage is especially prone to tiny chromatic
    // lightmap speckles at night, where the sky-light channels diverge.
    // Preserve the light level and most natural tint, but suppress unstable
    // per-channel colour noise only on identifiable tinted cutout geometry.
    float foliageTintSpread = max(max(Color.r, Color.g), Color.b)
                            - min(min(Color.r, Color.g), Color.b);
    if (ALPHA_CUTOUT > 0.4 && foliageTintSpread > 0.035) {
        float neutralLight = dot(lightmap.rgb, vec3(0.2126, 0.7152, 0.0722));
        lightmap.rgb = mix(vec3(neutralLight), lightmap.rgb, 0.18);
    }
    #endif
    vertexColor = Color * lightmap;
    #else
    vertexColor = Color;
    #endif
    texCoord0 = UV0;

    const float chunkFullyVisibleRange = 16.0;
    float dist = length(pos);
    chunkVisibility = mix(1.0, ChunkVisibility, clamp((dist - chunkFullyVisibleRange) / chunkFullyVisibleRange, 0.0, 1.0));

    nvsWorldPos = worldPos;
    nvsViewPos = pos;
    nvsTint = Color;
}

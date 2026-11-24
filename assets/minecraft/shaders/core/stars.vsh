#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <nvs:common.glsl>

layout(location = 0) in vec3 Position;

// Per-star colour and brightness, derived from the star's own position.
layout(location = 0) out vec3 nvsStarTint;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    // Vanilla's stars are a fixed buffer of single-pixel points and the program
    // gets nothing else: no per-star attribute, no texture. The position is the
    // only per-star input there is, so the variation has to come from it. A
    // hash of the direction is stable for the life of the world, which is what
    // separates a sky of stars from noise.
    float len = length(Position);
    vec3 dir = len > 1e-5 ? Position / len : vec3(0.0, 1.0, 0.0);
    vec3 cell = floor(dir * 400.0);

    float magnitude = nvs_hash13(cell);
    float temperature = nvs_hash13(cell + 7.13);

    // Squared so the field is mostly faint stars with a few bright ones.
    float brightness = mix(0.45, 2.6, magnitude * magnitude);

    vec3 cool = vec3(0.74, 0.86, 1.00);
    vec3 warm = vec3(1.00, 0.86, 0.66);
    nvsStarTint = mix(cool, warm, temperature) * brightness;
}

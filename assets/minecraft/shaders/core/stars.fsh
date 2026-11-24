#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:projection.glsl>

#include <minecraft:dynamictransforms.glsl>

layout(location = 0) out vec4 fragColor;

void main() {
    NVS_BUS_PROTECT
    fragColor = ColorModulator;
}

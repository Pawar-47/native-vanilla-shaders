#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;
layout(location = 2) in float LineWidth;

layout(location = 0) out vec4 vertexColor;
// This program shares position_color.fsh with the sunrise glow, so it has to
// provide the same varying. Debug points are never the glow: factor 1.
layout(location = 1) out float nvsGlowFalloff;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    vertexColor = Color;
    nvsGlowFalloff = 1.0;
    gl_PointSize = LineWidth;
}

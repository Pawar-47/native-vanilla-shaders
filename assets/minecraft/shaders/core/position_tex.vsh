#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;

layout(location = 0) out vec2 texCoord0;
// UV0 recentred to -1..1, which is the position within the celestial quad.
layout(location = 1) out vec2 nvsQuadUV;
// 1 for the sun, 0 for the moon.
layout(location = 2) flat out float nvsIsSun;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    texCoord0 = UV0;
    nvsQuadUV = UV0 * 2.0 - 1.0;

    // This program draws the sun and the moon and nothing else (the celestial
    // pipeline). The two quads are told apart by scale: 30 for the sun, 20 for
    // the moon, which is the only difference the program sees.
    nvsIsSun = abs(length(ModelViewMat[0].xyz) - 30.0) < 1.0 ? 1.0 : 0.0;
}

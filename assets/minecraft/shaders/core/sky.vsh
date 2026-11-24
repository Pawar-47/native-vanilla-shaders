#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:globals.glsl>

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
// The upper sky fan is remapped to the reserved data strip. The translated
// lower dark disc is moved off-screen and remains invisible as in vanilla.
layout(location = 4) out float nvsBusRow;

void main() {
    bool lowerDisc = dot(ModelViewMat[3].xyz, ModelViewMat[3].xyz) > 1.0;
    nvsBusRow = 0.0;
    if (lowerDisc) {
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        return;
    }

    // The vanilla sky mesh is a 10-vertex triangle fan. Vertices 0..3 form
    // the strip quad; the remaining vertices collapse onto its last corner.
    int i = gl_VertexIndex;
    vec2 corner = i == 0 ? vec2(0.0, 0.0) : i == 1 ? vec2(1.0, 0.0)
               : i == 2 ? vec2(1.0, 1.0) : vec2(0.0, 1.0);
    gl_Position = nvs_busStripCorner(corner, 0, NVS_BUS_SKY_ROWS, ScreenSize);
    nvsBusRow = corner.y * float(NVS_BUS_SKY_ROWS);
}

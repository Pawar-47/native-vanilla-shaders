#version 330
#extension GL_ARB_separate_shader_objects : require
#include <nvs:bus.glsl>
#include <minecraft:globals.glsl>

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
// World-space direction of this sky vertex from the eye.
layout(location = 2) out vec3 nvsSkyDirection;
// 1 when this is the "dark disc" the game draws under the horizon.
layout(location = 3) flat out float nvsLowerDisc;
layout(location = 4) out float nvsBusRow;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);

    // The sky disc is drawn with the camera rotation alone, so a vertex's
    // direction from the eye is a world-space direction: y is 1 straight up and
    // about 0 at the rim of the disc. That is what the gradient is built on.
    float len = length(Position);
    nvsSkyDirection = len > 1e-5 ? Position / len : vec3(0.0, 1.0, 0.0);

    // The same program draws the upper sky and the dark disc below the horizon,
    // the second one translated 12 blocks down. Only the upper sky is redrawn.
    nvsLowerDisc = dot(ModelViewMat[3].xyz, ModelViewMat[3].xyz) > 1.0 ? 1.0 : 0.0;
    nvsBusRow = 0.0;
    if (nvsLowerDisc > 0.5) { gl_Position = vec4(2.0, 2.0, 0.0, 1.0); return; }
    int i = gl_VertexIndex;
    vec2 corner = i == 0 ? vec2(0.0, 0.0) : i == 1 ? vec2(1.0, 0.0) : i == 2 ? vec2(1.0, 1.0) : vec2(0.0, 1.0);
    gl_Position = nvs_busStripCorner(corner, 0, NVS_BUS_SKY_ROWS, ScreenSize);
    nvsBusRow = corner.y * float(NVS_BUS_SKY_ROWS);
}

#version 330
#extension GL_ARB_separate_shader_objects : require

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
}

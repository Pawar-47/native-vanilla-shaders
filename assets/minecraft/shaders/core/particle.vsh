#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:sample_lightmap.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;
layout(location = 2) in vec4 Color;
layout(location = 3) in ivec2 UV2;

uniform sampler2D Sampler2;

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
layout(location = 2) out vec2 texCoord0;
layout(location = 3) out vec4 vertexColor;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    texCoord0 = UV0;

    // Keep the particle's own texture and vertex tint. Only desaturate the
    // sampled lightmap contribution, which otherwise gives tiny weather
    // streaks different red/green/blue channel values as they move through
    // biome- and time-tinted sky light.
    vec4 lightmap = sample_lightmap(Sampler2, UV2);
    float neutralLight = dot(lightmap.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 stableLight = mix(vec3(neutralLight), lightmap.rgb, 0.08);
    vertexColor = Color * vec4(stableLight, lightmap.a);
}

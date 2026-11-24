#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;

layout(location = 0) out vec4 vertexColor;
// Radial factor across the sunrise and sunset glow: 1 at its centre, 0 at its rim.
layout(location = 1) out float nvsGlowFalloff;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    vertexColor = Color;

    // The sunrise and sunset glow is a fixed fan of 18 vertices around the sun:
    // a centre at (0, 100, 0) and a ring about 120 units out. Vanilla paints it
    // in one flat colour, which is why the horizon glow reads as a hard-edged
    // disc. The factor below turns it into a gradient.
    //
    // This program also draws the debug shapes, so the pattern is matched by
    // geometry and under a perspective projection, and anything that does not
    // match keeps a factor of exactly 1.
    // Measure from the fan's actual centre, not from the world origin.
    // Its centre is at (0, 100), with the outer ring roughly 120 units away.
    float radius = length(Position.xy - vec2(0.0, 100.0));
    bool looksLikeGlow = ProjMat[2][3] != 0.0 && gl_VertexIndex < 18
                      && (radius < 1.0 || abs(radius - 120.0) < 8.0);
    nvsGlowFalloff = looksLikeGlow ? clamp(1.0 - radius / 126.0, 0.0, 1.0) : 1.0;
}

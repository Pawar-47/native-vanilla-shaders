#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in vec2 texCoord0;
layout(location = 1) in vec2 nvsQuadUV;
layout(location = 2) flat in float nvsIsSun;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 body = texture(Sampler0, texCoord0);

    // A corona inside the quad the sun already occupies. The quad is a fixed
    // size, so the radial distance within it is an angle: r = 1 is about 17
    // degrees out, which is a sun halo rather than a lens flare.
    float r = length(nvsQuadUV);
    float beyond = max(r - 0.18, 0.0);
    float halo = exp(-beyond * 3.4) * 0.34 + exp(-beyond * 1.15) * 0.08;

    // Reach exactly zero at the edge of the quad, so the glow has no cut-off.
    halo *= 1.0 - smoothstep(0.72, 1.0, r);

    // The halo takes its colour and its weather fade from the same
    // ColorModulator the game uses for the sun itself.
    vec3 haloColor = nvsIsSun > 0.5 ? vec3(1.00, 0.82, 0.52) : vec3(0.66, 0.78, 1.00);

    if (body.a == 0.0 && halo < 0.002) {
        discard;
    }

    // The celestial pipeline blends additively as (source * source alpha + dest).
    // Folding the body's own alpha into the colour and writing alpha 1 therefore
    // adds exactly what vanilla added, and puts the halo alongside it. Rain
    // brightness, which the game passes in ColorModulator.a, fades both.
    vec3 outColor = (body.rgb * ColorModulator.rgb * body.a + haloColor * halo) * ColorModulator.a;
    fragColor = vec4(outColor, 1.0);
}

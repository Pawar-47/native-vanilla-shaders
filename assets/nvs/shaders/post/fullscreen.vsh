#version 330
#extension GL_ARB_separate_shader_objects : require

// Full-screen triangle for the pack's post passes.
//
// The pack ships its own instead of referencing the game's: the vanilla program
// is called minecraft:core/screenquad in 26.3 and was renamed in the 26.4
// snapshots, and a post effect that fails to compile removes every selected
// resource pack in the middle of the game.

layout(location = 0) out vec2 texCoord;

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
    texCoord = uv;
}

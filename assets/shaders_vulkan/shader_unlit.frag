#version 450

layout(set = 0, binding = 1) uniform sampler2D u_Texture;

layout(location = 0) in vec2 in_UV;
layout(location = 0) out vec4 out_Color;

void main() {
    vec4 tex = texture(u_Texture, in_UV);
    out_Color = tex;
}
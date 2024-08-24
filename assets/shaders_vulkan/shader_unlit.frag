#version 450

layout(set = 0, binding = 1) uniform sampler2D u_Texture;

layout(location = 0) in vec2 v_UV;
layout(location = 0) out vec4 out_Color;

void main() {
    vec4 tex = texture(u_Texture, v_UV);
    out_Color = vec4(v_UV, 0.5, 1) * (1-tex.w) + tex;
    //out_Color = texture(u_Texture, v_UV);
    //out_Color = vec4(0, 1 - v_UV.x, 0.5, 1);
}
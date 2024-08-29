#version 450

// vertex attributes:
layout(location = 0) in vec3 v_Position;
layout(location = 1) in vec2 v_UV;
layout(location = 2) in vec3 v_Normal;

layout(binding = 0) uniform cameraBuffer {
    mat4 viewProjection;
} Camera;

layout( push_constant ) uniform pushConstantsBuffer {
    mat4 localToWorld;
} PushConstant;

// output
layout(location = 0) out vec2 out_UV;

void main() {
    gl_Position = vec4(v_Position, 1);//Camera.viewProjection * PushConstant.localToWorld * vec4(v_Position, 1);
    out_UV = v_UV;
}
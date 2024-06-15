#include <metal_stdlib>
using namespace metal;

// Vertex shader outputs and fragment shader inputs
struct RasterizerData
{
    float4 position [[position]];
    float4 color;
    float2 uv0;
};

struct VertexData
{
    float4 position;
    float4 color;
    float2 uv0;
};

struct CameraData
{
    float4x4 viewProjection;
};

struct InstanceData
{
    float4x4 localToWorld;
};

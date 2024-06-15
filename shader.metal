#include <metal_stdlib>

using namespace metal;

// Vertex shader outputs and fragment shader inputs
struct RasterizerData
{
    float4 position [[position]];
    float4 color;
};

struct VertexData
{
    float4 position;
};

vertex RasterizerData
main_vertex(uint vertexID [[vertex_id]],
             constant VertexData *vertices [[buffer(0)]])
{
    RasterizerData out;
    out.color = float4(1.0f, 1.0f, 1.0f, 1.0f);
    return out;
}

fragment float4 main_fragment(RasterizerData in [[stage_in]])
{
    return in.color;
}

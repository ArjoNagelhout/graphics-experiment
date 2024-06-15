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
    float4 color;
};

vertex RasterizerData
main_vertex(uint vertexID [[vertex_id]],
            device VertexData const* vertices [[buffer(0)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    out.position = data.position;
    out.color = data.color;
    return out;
}

fragment float4 main_fragment(RasterizerData in [[stage_in]])
{
    return in.color;
}

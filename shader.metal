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
    float4 a[3] = {float4(0.5, -0.5, 0, 1), float4(-0.5, -0.5, 0, 1), float4(0, 0.5, 0, 1)};
    float4 c[3] = {float4(1.0, 0.0, 0.0, 1), float4(0.0, 1.0, 0.0, 1), float4(0.0, 0.0, 1.0, 1)};

    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    out.position = data.position;
    out.color = data.color;
    //out.position = a[vertexID % 3];
    //out.color = c[vertexID % 3];

    return out;
}

fragment float4 main_fragment(RasterizerData in [[stage_in]])
{
    return float4(1.0f, 1.0f, 1.0f, 1.0f);
    //return in.color;
}

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

vertex RasterizerData
main_vertex(
    uint vertexID [[vertex_id]],
    device VertexData const* vertices [[buffer(0)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    out.position = data.position;
    out.color = data.color;
    out.uv0 = data.uv0;
    return out;
}

fragment half4 main_fragment(
    RasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::nearest);

    return tex.sample(s, in.uv0);
}

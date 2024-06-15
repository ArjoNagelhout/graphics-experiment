#include <metal_stdlib>

using namespace metal;

vertex RasterizerData
main_vertex(
    uint vertexID [[vertex_id]],
    device VertexData const* vertices [[buffer(0)]],
    device CameraData const& camera [[buffer(1)]],
    device InstanceData const& instance [[buffer(2)]])
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

    return half4(1.0f, 0.0f, 1.0f, 1.0f);
    return tex.sample(s, in.uv0);
}

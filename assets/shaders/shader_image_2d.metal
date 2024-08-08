struct Image2dVertexData
{
    float4 position;
    float2 uv0;
};

struct Image2dRasterizerData
{
    float4 position [[position]];
    float2 uv0;
};

vertex Image2dRasterizerData image_2d_vertex(
    uint vertexID [[vertex_id]],
    device Image2dVertexData const* vertices [[buffer(binding_vertex::vertexData)]])
{
    Image2dRasterizerData out;
    device Image2dVertexData const& data = vertices[vertexID];
    out.position = data.position;
    out.uv0 = data.uv0;
    return out;
}

fragment half4 image_2d_fragment(
    Image2dRasterizerData in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(binding_fragment::texture)]])
{
    constexpr sampler s(address::repeat, filter::linear);
    return half4(texture.sample(s, in.uv0).rgb, 1.0f);
}
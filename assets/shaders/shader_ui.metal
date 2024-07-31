vertex RasterizerData ui_vertex(
    uint vertexID [[vertex_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    out.position = data.position;
    out.color = data.color;
    out.uv0 = data.uv0;
    return out;
}

fragment half4 ui_fragment(
    RasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(bindings::texture)]])
{
    constexpr sampler s(address::repeat, filter::linear);

    return half4(tex.sample(s, in.uv0).rgb, 1.0f);
}

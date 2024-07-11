vertex RasterizerData ui_vertex(
    uint vertexID [[vertex_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const& instance [[buffer(bindings::instanceData)]])
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
    texture2d< half, access::sample > tex [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::nearest);

    return tex.sample(s, in.uv0);
}

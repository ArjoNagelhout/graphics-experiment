vertex RasterizerData unlit_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    out.position = camera.viewProjection * instance.localToWorld * data.position;

    out.color = data.color;
    out.uv0 = data.uv0;
    return out;
}

fragment half4 unlit_fragment(
    RasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(bindings::texture)]])
{
    constexpr sampler s(address::repeat, filter::nearest);
    return tex.sample(s, in.uv0);
}

fragment half4 unlit_colored_fragment(
    RasterizerData in [[stage_in]])
{
    return half4(in.color);
}
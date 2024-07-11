vertex RasterizerData shadow_vertex(
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
    out.uv0 = data.uv0;
    return out;
}

fragment half4 shadow_fragment(
    RasterizerData in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::nearest);
    half4 color = texture.sample(s, in.uv0);
    return half4(0, 0, 0, 0.0f);
}

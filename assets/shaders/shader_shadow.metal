vertex RasterizerData shadow_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],

    // vertex data
    device packed_float3 const* positions [[buffer(bindings::positions)]],
    device packed_float2 const* uv0s [[buffer(bindings::uv0s)]]
)
{
    // vertex data
    device packed_float3 const& position = positions[vertexId];
    device packed_float2 const& uv0 = uv0s[vertexId];

    RasterizerData out;
    device InstanceData const& instance = instances[instanceId];

    out.position = camera.viewProjection * instance.localToWorld * float4(position, 1.0f);
    out.uv0 = uv0;
    return out;
}

fragment half4 shadow_fragment(
    RasterizerData in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(bindings::texture)]])
{
    //constexpr sampler s(address::repeat, filter::nearest);
    //half4 color = texture.sample(s, in.uv0);
    return half4(0, 0, 0, 0.0f);
}

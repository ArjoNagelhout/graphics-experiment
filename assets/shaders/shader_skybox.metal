struct SkyboxRasterizerData
{
    float4 position [[position]];
    float3 direction; // direction of the vertex
    float2 uv;
};

vertex SkyboxRasterizerData skybox_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]])
{
    SkyboxRasterizerData out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    out.position = camera.viewProjection * instance.localToWorld * data.position;
    out.position.z = out.position.w - 0.01f;
    out.direction = normalize((instance.localToWorld * data.position).xyz);
    out.uv = data.uv0;
    return out;
}

fragment half4 skybox_fragment(
    SkyboxRasterizerData in [[stage_in]],
    texture2d<half, access::sample> tex [[texture(bindings::texture)]])
{
    float theta = atan2(in.direction.z, in.direction.x); // longitude
    float phi = asin(in.direction.y); // latitude

    // Map spherical coordinates to texture coordinates
    float u = (theta / (2.0 * 3.141592653589793)) + 0.5;
    float v = (phi / 3.141592653589793) + 0.5;

    float2 uv{u, 1.0f-v};
    constexpr sampler s(address::repeat, filter::linear);
    return tex.sample(s, in.uv);
}
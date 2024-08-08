struct SkyboxRasterizerData
{
    float4 position [[position]];
    float3 direction; // direction of the vertex
    float2 uv;
};

vertex SkyboxRasterizerData skybox_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(binding_vertex::cameraData)]],

    // vertex data
    device packed_float3 const* positions [[buffer(binding_vertex::positions)]]
)
{
    SkyboxRasterizerData out;

    // vertex data
    device packed_float3 const& position = positions[vertexId];

    out.position = camera.viewProjection * float4(position, 1.0f);
    out.position.z = out.position.w;
    out.direction = position;
    return out;
}

fragment half4 skybox_fragment(
    SkyboxRasterizerData in [[stage_in]],
    texture2d<half, access::sample> tex [[texture(binding_fragment::texture)]])
{
    // the GPU's rasterizer performs linear interpolation
    // linearly interpolating between two normalized vectors does not result in a
    // normalized vector, so we need to normalize in the fragment shader
    in.direction = normalize(in.direction);

    float theta = atan2(in.direction.z, in.direction.x); // longitude
    float phi = asin(in.direction.y); // latitude

    // map spherical coordinates to texture coordinates
    float u = (theta / (2.0f * M_PI_F)) + 0.5f;
    float v = (phi / M_PI_F) + 0.5f;

    float2 uv{u, 1.0f-v};
    constexpr sampler s(address::repeat, filter::linear);
    return tex.sample(s, uv);
}
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
    device CameraData const& camera [[buffer(bindings::cameraData)]])
{
    SkyboxRasterizerData out;
    device VertexData const& data = vertices[vertexID];

    out.position = camera.viewProjection * data.position;
    out.position.z = out.position.w;
    out.direction = data.position.xyz;
    return out;
}

fragment half4 skybox_fragment(
    SkyboxRasterizerData in [[stage_in]],
    texture2d<half, access::sample> tex [[texture(bindings::texture)]])
{
    // the GPU's rasterizer performs linear interpolation
    // linearly interpolating between two normalized vectors does not result in a
    // normalized vector, so we need to normalize in the fragment shader
    in.direction = normalize(in.direction);

    float theta = atan2(in.direction.z, in.direction.x); // longitude
    float phi = asin(in.direction.y); // latitude

    // map spherical coordinates to texture coordinates
    float u = (theta / (2.0 * 3.141592653589793)) + 0.5;
    float v = (phi / 3.141592653589793) + 0.5;

    float2 uv{u, 1.0f-v};
    constexpr sampler s(address::repeat, filter::linear);
    return tex.sample(s, uv);
}
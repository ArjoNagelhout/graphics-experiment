float calculateShadow(float4 positionLightSpace, depth2d<float, access::sample> texture)
{
    // perform perspective divide
    float3 projected = positionLightSpace.xyz / positionLightSpace.w;

    // transform from NDC (between -1 and 1) to texture coordinates (between 0 and 1)
    float4x4 toTextureCoordinates(
        0.5, 0.0, 0.0, 0.0,
        0.0, -0.5, 0.0, 0.0, // flipped y axis
        0.0, 0.0, 0.5, 0.0,
        0.5, 0.5, 0.5, 1.0
    );

    float3 textureCoordinates = (toTextureCoordinates * float4(projected, 1)).xyz;

    // get depth of current fragment from light's perspective
    float depthOfThisFragment = projected.z;

    constexpr sampler s(address::clamp_to_edge, filter::linear, compare_func::less_equal);
    float shadow = texture.sample_compare(s, textureCoordinates.xy, depthOfThisFragment);
    return shadow;
}

vertex RasterizerData terrain_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(0)]],
    device CameraData const& camera [[buffer(1)]],
    device InstanceData const* instances [[buffer(2)]],
    device LightData const& light [[buffer(3)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    out.fragmentPosition = instance.localToWorld * data.position;
    out.fragmentPositionLightSpace = light.lightSpace * float4(out.fragmentPosition.xyz, 1);
    out.position = camera.viewProjection * out.fragmentPosition;

    out.color = data.color;
    out.uv0 = data.position.xz;
    return out;
}

fragment half4 terrain_fragment(
    RasterizerData in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(0)]],
    depth2d<float, access::sample> shadowMap [[texture(1)]])
{
    //constexpr sampler s(address::repeat, filter::nearest);

    float shadow = calculateShadow(in.fragmentPositionLightSpace, shadowMap);
    //return shadow * texture.sample(s, in.uv0);
    return shadow;
    //return texture.sample(s, in.uv0);
}

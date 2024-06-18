vertex RasterizerData lit_vertex(
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
    out.uv0 = data.uv0;
    return out;
}

fragment half4 lit_fragment(
    RasterizerData in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(0)]],
    depth2d<float, access::sample> shadowMap [[texture(1)]])
{
    constexpr sampler s(address::repeat, filter::nearest);

    // base color
    half4 textured = texture.sample(s, in.uv0);
    float textureAlpha = textured.w;

    // shadow
    half4 shadowColor = half4(27.f/255.f, 55.f/255.f, 117.f/255.f, 1.f);
    float shadowOpacity = 0.7f;
    float isInLight = calculateIsInLight(in.fragmentPositionLightSpace, shadowMap);
    float shadowAmount = clamp(shadowOpacity - isInLight, 0.0f, 1.0f);
    half4 shadowed = mix(textured, shadowColor, shadowAmount);

    // fog
    half4 fogColor = half4(0, 1, 1, 1);
    float fog = (in.position.z / in.position.w) * 0.02;

    // fix alpha
    return half4(mix(shadowed, fogColor, fog).xyz, textureAlpha);
}

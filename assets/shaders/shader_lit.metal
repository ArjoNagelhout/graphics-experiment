vertex RasterizerDataLit lit_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(binding_vertex::cameraData)]],
    device InstanceData const* instances [[buffer(binding_vertex::instanceData)]],
    device LightData const& light [[buffer(binding_vertex::lightData)]],

    // vertex data
    device packed_float3 const* positions [[buffer(binding_vertex::positions)]],
    device packed_float4 const* colors [[buffer(binding_vertex::colors)]],
    device packed_float2 const* uv0s [[buffer(binding_vertex::uv0s)]]
)
{
    // vertex data
    device packed_float3 const& position = positions[vertexId];
    device packed_float4 const& color = colors[vertexId];
    device packed_float2 const& uv0 = uv0s[vertexId];

    RasterizerDataLit out;
    device InstanceData const& instance = instances[instanceId];

    out.fragmentPosition = instance.localToWorld * float4(position, 1.0f);
    out.fragmentPositionLightSpace = light.lightSpace * float4(out.fragmentPosition.xyz, 1);
    out.position = camera.viewProjection * out.fragmentPosition;

    out.color = color;
    out.uv0 = uv0;
    return out;
}

constant bool alphaCutout [[function_constant(binding_constant::alphaCutout)]];

fragment half4 lit_fragment(
    RasterizerDataLit in [[stage_in]],
    texture2d<half, access::sample> texture [[texture(binding_fragment::texture)]],
    depth2d<float, access::sample> shadowMap [[texture(binding_fragment::shadowMap)]])
{
    constexpr sampler s(address::repeat, filter::nearest);

    // base color
    half4 textured = texture.sample(s, in.uv0);
    float textureAlpha = textured.w;

    if (alphaCutout && textureAlpha < 1.0f)
    {
        discard_fragment();
    }

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

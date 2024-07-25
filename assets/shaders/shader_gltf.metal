// non-interleaved vertex buffer layout

struct GltfRasterizerData
{
    float4 position [[position]];
    float4 normal;
    float2 uv0;
    float4 color;
    float2 lightMapUv0;
};

vertex GltfRasterizerData gltf_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device packed_float3 const* positions [[buffer(bindings::positions)]],
    device packed_float3 const* normals [[buffer(bindings::normals)]],
    device packed_float2 const* uv0s [[buffer(bindings::uv0s)]],
    device packed_float3 const* colors [[buffer(bindings::colors)]],
    device packed_float2 const* lightMapUvs [[buffer(bindings::lightMapUvs)]],
    device packed_float3 const* tangents [[buffer(bindings::tangents)]])
{
    GltfRasterizerData out;
    device InstanceData const& instance = instances[instanceId];
    device packed_float3 const& position = positions[vertexId];
    //device packed_float3 const& normal = normals[vertexId];
    device packed_float2 const& uv0 = uv0s[vertexId];

    out.position = camera.viewProjection * instance.localToWorld * float4(position, 1.0f);
    out.uv0 = uv0;
    //out.normal = float4(normal, 1.0f);
    return out;
}

fragment half4 gltf_fragment(
    GltfRasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(bindings::texture)]])
{
    constexpr sampler s(address::repeat, filter::nearest);
    return tex.sample(s, in.uv0);
    //return half4(1, 0, 1, 1);
}
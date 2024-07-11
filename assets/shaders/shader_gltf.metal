// non-interleaved vertex buffer layout

struct GltfRasterizerData
{
    float4 position [[position]];
    float4 normal;
    float2 uv0;
    float4 color;
    float2 lightMapUv0;
};

vertex RasterizerData gltf_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device float3 const* positions [[buffer(bindings::positions)]],
    device float3 const* normals [[buffer(bindings::normals)]],
    device float2 const* uv0s [[buffer(bindings::uv0s)]])
{
    RasterizerData out;
    device InstanceData const& instance = instances[instanceId];
    device float3 const& position = positions[vertexId];
    device float3 const& normal = normals[vertexId];
    device float3 const& uv0 = uv0s[vertexId];

    out.position = camera.viewProjection * instance.localToWorld * position;

    out.uv0 = data.uv0;
    return out;
}

fragment half4 gltf_fragment(
    RasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::nearest);
    return tex.sample(s, in.uv0);
}
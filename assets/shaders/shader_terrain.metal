vertex RasterizerDataLit terrain_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device LightData const& light [[buffer(bindings::lightData)]])
{
    RasterizerDataLit out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    out.fragmentPosition = instance.localToWorld * data.position;
    out.fragmentPositionLightSpace = light.lightSpace * float4(out.fragmentPosition.xyz, 1);
    out.position = camera.viewProjection * out.fragmentPosition;

    out.color = data.color;
    out.uv0 = data.position.xz;
    return out;
}

vertex RasterizerDataLit vertex_terrain_deinterleaved(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device LightData const& light [[buffer(bindings::lightData)]],

    // vertex attributes
    device packed_float3 const* positions [[buffer(bindings::positions)]],
    device packed_float3 const* normals [[buffer(bindings::normals)]],
    device packed_float2 const* uv0s [[buffer(bindings::uv0s)]],
    device packed_float4 const* colors [[buffer(bindings::colors)]],
    device packed_float2 const* lightMapUvs [[buffer(bindings::lightMapUvs)]],
    device packed_float3 const* tangents [[buffer(bindings::tangents)]]
)
{
    RasterizerDataLit out;
    device InstanceData const& instance = instances[instanceId];

    // vertex attributes
    device packed_float3 const& position = positions[vertexId];
    //device packed_float3 const& normal = normals[vertexId];
    //device packed_float3 const& tangent = tangents[vertexId];
    device packed_float2 const& uv0 = uv0s[vertexId];
    device packed_float4 const& color = colors[vertexId];

    out.fragmentPosition = float4(position, 1.0f);
    out.fragmentPositionLightSpace = light.lightSpace * float4(out.fragmentPosition.xyz, 1);
    out.position = camera.viewProjection * out.fragmentPosition;

    out.color = color;
    out.uv0 = uv0; //position.xz;
    return out;
}

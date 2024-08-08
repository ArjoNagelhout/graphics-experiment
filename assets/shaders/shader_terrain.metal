vertex RasterizerDataLit terrain_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(binding_vertex::cameraData)]],
    device InstanceData const* instances [[buffer(binding_vertex::instanceData)]],
    device LightData const& light [[buffer(binding_vertex::lightData)]],

    // vertex data
    device packed_float3 const* positions [[buffer(binding_vertex::positions)]]
)
{
    RasterizerDataLit out;
    device InstanceData const& instance = instances[instanceId];

    // vertex data
    device packed_float3 const& position = positions[vertexId];

    out.fragmentPosition = float4(position, 1.0f);
    out.fragmentPositionLightSpace = light.lightSpace * float4(out.fragmentPosition.xyz, 1);
    out.position = camera.viewProjection * out.fragmentPosition;

    out.uv0 = position.xz;
    return out;
}

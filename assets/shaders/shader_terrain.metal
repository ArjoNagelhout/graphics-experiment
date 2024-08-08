vertex RasterizerDataLit terrain_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device LightData const& light [[buffer(bindings::lightData)]],

    // vertex data
    device packed_float3 const* positions [[buffer(bindings::positions)]]
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

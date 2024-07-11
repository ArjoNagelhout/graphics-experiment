vertex RasterizerDataLit terrain_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device LightData const& light [[buffer(3)]])
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

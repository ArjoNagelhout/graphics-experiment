vertex RasterizerData terrain_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(0)]],
    device CameraData const& camera [[buffer(1)]],
    device InstanceData const* instances [[buffer(2)]])
{
    RasterizerData out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    float4 pos = data.position;
    //pos.y += -0.1 * (sin(pos.x * 5) + cos(pos.z * 5));

    out.position = camera.viewProjection * instance.localToWorld * pos;



    out.color = data.color;
    out.uv0 = data.position.xz;
    return out;
}

fragment half4 terrain_fragment(
    RasterizerData in [[stage_in]],
    texture2d< half, access::sample > tex [[texture(0)]])
{
    constexpr sampler s(address::repeat, filter::nearest);

    //return half4(in.color);
    return tex.sample(s, in.uv0);
}

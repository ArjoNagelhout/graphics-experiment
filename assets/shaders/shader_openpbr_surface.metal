// implementation of https://academysoftwarefoundation.github.io/OpenPBR

// non-constant parameters used in the vertex function
struct OpenPBRSurfaceGlobalVertexData
{

};

// non-constant parameters used in the fragment function
struct OpenPBRSurfaceGlobalFragmentData
{
    float4 color;
    float4 color2;
    float metallicness;
};

struct OpenPBRSurfaceRasterizerData
{
    float4 position [[position]];
};

vertex OpenPBRSurfaceRasterizerData openpbr_surface_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device InstanceData const* instances [[buffer(bindings::instanceData)]],
    device VertexData const* vertices [[buffer(bindings::vertexData)]],
    device OpenPBRSurfaceGlobalVertexData const& globalData [[buffer(bindings::globalVertexData)]]
)
{
    OpenPBRSurfaceRasterizerData out;
    device InstanceData const& instance = instances[instanceId];
    device VertexData const& v = vertices[vertexId];

    out.position = camera.viewProjection * instance.localToWorld * v.position;

    return out;
}

fragment half4 openpbr_surface_fragment(
    OpenPBRSurfaceRasterizerData in [[stage_in]],
    device OpenPBRSurfaceGlobalFragmentData const& globalData [[buffer(bindings::globalFragmentData)]]
)
{
    // diffuse


    // gloss

    // layer(diffuse, gloss)

    // subsurface

    // translucent-base

    // metal

    // coat

    // fuzz

    // ambient-medium

    return half4(mix(globalData.color, globalData.color2, globalData.metallicness));
}
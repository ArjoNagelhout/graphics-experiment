// implementation of https://academysoftwarefoundation.github.io/OpenPBR

// non-constant parameters used in the vertex function
struct OpenPBRSurfaceGlobalVertexData
{
    float4x4 localToWorldTransposedInverse;
};

// non-constant parameters used in the fragment function
struct OpenPBRSurfaceGlobalFragmentData
{
    float3 cameraPosition;
};

struct OpenPBRSurfaceRasterizerData
{
    float4 position [[position]];

    float3 worldSpacePosition;
    float3 worldSpaceNormal;
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

    float4 position = instance.localToWorld * v.position;
    out.position = camera.viewProjection * position;
    //out.worldSpacePosition = position.xyz / position.w;

    // calculate world-space normal
    //out.worldSpaceNormal = (globalData.localToWorldTransposedInverse * float4(v.normal.xyz, 0.0f)).xyz;

    return out;
}

fragment half4 openpbr_surface_fragment(
    OpenPBRSurfaceRasterizerData in [[stage_in]],
    device OpenPBRSurfaceGlobalFragmentData const& globalData [[buffer(bindings::globalFragmentData)]],
    texture2d<half, access::sample> reflectionMap [[texture(bindings::reflectionMap)]]
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

    // get the direction vector for the reflection map
    float3 direction = normalize(in.worldSpaceNormal);

    // sample reflection map


    return half4(1, 0, 1, 1);
}
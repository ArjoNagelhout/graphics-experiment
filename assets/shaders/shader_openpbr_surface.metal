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
    float roughness;
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
    out.worldSpacePosition = position.xyz / position.w;

    // calculate world-space normal
    out.worldSpaceNormal = (globalData.localToWorldTransposedInverse * float4(v.normal.xyz, 0.0f)).xyz;

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


    // GGX consists of:

    // - fresnel term F
    // - microfacet distribution function D
    // - shadowing-masking function G (depends on D)
    // - microsurface BSDF (reflection, BSRF and refraction, BSTF) (depends on F, D, G)

    // GGX requires multi sampling
    // https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-20-gpu-based-importance-sampling

    // https://bruop.github.io/ibl/
    // involved: requires precomputing many terms and storing them into cubemaps and textures
    // e.g.
    // https://learnopengl.com/PBR/IBL/Specular-IBL
    // split sum approximation (LUT = lookup texture) -> https://wiki.jmonkeyengine.org/docs/3.4/tutorials/how-to/articles/pbr/pbr_part3.html
    // pre-filtered environment map


    float3 normal = normalize(in.worldSpaceNormal);
    float3 cameraDirection = normalize(in.worldSpacePosition - globalData.cameraPosition);
    float3 outDirection = reflect(cameraDirection, normal);

    // sample reflection map
    float theta = atan2(outDirection.z, outDirection.x); // longitude
    float phi = asin(outDirection.y); // latitude

    // map spherical coordinates to texture coordinates
    float u = (theta / (2.0f * M_PI_F)) + 0.5f;
    float v = (phi / M_PI_F) + 0.5f;

    float2 uv{u, 1.0f-v};
    constexpr sampler s(address::repeat, filter::linear);
    return reflectionMap.sample(s, uv);

    //return half4(1, 0, 1, 1);
}
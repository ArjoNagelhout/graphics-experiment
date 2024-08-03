// implementation of https://academysoftwarefoundation.github.io/OpenPBR
// https://jcgt.org/published/0008/01/03/paper.pdf

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
    float3 color;
    uint mipLevels;
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
    device OpenPBRSurfaceGlobalVertexData const& data [[buffer(bindings::globalVertexData)]]
)
{
    OpenPBRSurfaceRasterizerData out;
    device InstanceData const& instance = instances[instanceId];
    device VertexData const& v = vertices[vertexId];

    float4 position = instance.localToWorld * v.position;
    out.position = camera.viewProjection * position;
    out.worldSpacePosition = position.xyz / position.w;

    // calculate world-space normal
    out.worldSpaceNormal = (data.localToWorldTransposedInverse * float4(v.normal.xyz, 0.0f)).xyz;

    return out;
}

fragment half4 openpbr_surface_fragment(
    OpenPBRSurfaceRasterizerData in [[stage_in]],
    device OpenPBRSurfaceGlobalFragmentData const& data [[buffer(bindings::globalFragmentData)]],
    texture2d<half, access::sample> reflectionMap [[texture(bindings::reflectionMap)]],
    texture2d<float, access::sample> prefilteredEnvironmentMap [[texture(bindings::prefilteredEnvironmentMap)]],
    texture2d<float, access::sample> brdfLookupTexture [[texture(bindings::brdfLookupTexture)]],
    texture2d<float, access::sample> irradianceMap [[texture(bindings::irradianceMap)]]
)
{
    constexpr sampler mipSampler(address::repeat, filter::linear, mip_filter::linear);
    constexpr sampler sampler(address::repeat, filter::linear);

    float3 normal = normalize(in.worldSpaceNormal);
    float3 cameraDirection = normalize(in.worldSpacePosition - data.cameraPosition);
    float3 outDirection = reflect(cameraDirection, normal);

    // when the normal faces the camera, the dot product becomes 1.0f, which creates a white spot, so we add a slight offset
    float nDotV = clamp(dot(normal, -cameraDirection), 0.0f, 0.999f);

    // uvs
    float2 outDirectionUv = directionToUvEquirectangular(outDirection);
    float2 normalUv = directionToUvEquirectangular(normal);

    // F0 is the color when the normal faces the camera
    float3 F0 = data.color;
    float3 Fr = max(float3(1.0f - data.roughness), F0) - F0;

    float3 kS = F0 + Fr * pow(1.0f - nDotV, 5.0f);

    float2 f_ab = brdfLookupTexture.sample(sampler, float2(nDotV, data.roughness)).rg;
    float3 FssEss = kS * f_ab.x + f_ab.y;

    float mipLevel = data.roughness * data.mipLevels;
    float3 radiance = prefilteredEnvironmentMap.sample(mipSampler, outDirectionUv, level(mipLevel)).rgb;

    float3 irradiance = irradianceMap.sample(sampler, normalUv).rgb;

    // multiple scattering
    float Ess = f_ab.x + f_ab.y;
    float Ems = 1.0f - Ess;
    float3 Favg = F0 + (1.0f - F0) / 21;
    float3 Fms = FssEss * Favg / (1 - (1 - Ess) * Favg);

    // conductor
    return half4(float4(FssEss * radiance + Fms * Ems * irradiance, 1.0f));
}
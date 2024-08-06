// non-interleaved vertex buffer layout

struct GltfPbrRasterizerData
{
    float4 position [[position]];
    float4 normal;
    float2 uv0;
    float4 color;
    float2 lightMapUv0;

    // pbr
    float3 worldSpacePosition;
    float3 worldSpaceTangent; // for constructing the TBN (tangent, bitangent, normal) matrix
    float3 worldSpaceBitangent;
    float3 worldSpaceNormal;
};

struct GltfPbrInstanceData
{
    float4x4 localToWorld;
    float4x4 localToWorldTransposedInverse;
};

vertex GltfPbrRasterizerData gltf_pbr_vertex(
    uint vertexId [[vertex_id]],
    uint instanceId [[instance_id]],
    device CameraData const& camera [[buffer(bindings::cameraData)]],
    device GltfPbrInstanceData const* instances [[buffer(bindings::instanceData)]],
    device packed_float3 const* positions [[buffer(bindings::positions)]],
    device packed_float3 const* normals [[buffer(bindings::normals)]],
    device packed_float2 const* uv0s [[buffer(bindings::uv0s)]],
    device packed_float3 const* colors [[buffer(bindings::colors)]],
    device packed_float2 const* lightMapUvs [[buffer(bindings::lightMapUvs)]],
    device packed_float3 const* tangents [[buffer(bindings::tangents)]])
{
    GltfPbrRasterizerData out;
    device GltfPbrInstanceData const& instance = instances[instanceId];

    // vertex data non-interleaved
    device packed_float3 const& position = positions[vertexId];
    device packed_float3 const& normal = normals[vertexId];
    device packed_float3 const& tangent = tangents[vertexId];
    device packed_float2 const& uv0 = uv0s[vertexId];

    float4 worldSpacePosition = instance.localToWorld * float4(position, 1.0f);
    out.position = camera.viewProjection * worldSpacePosition;
    out.worldSpacePosition = worldSpacePosition.xyz / worldSpacePosition.w; // apply perspective projection

    // calculate world-space normal
    out.worldSpaceNormal = (instance.localToWorldTransposedInverse * float4(normal, 0.0f)).xyz;
    out.worldSpaceTangent = (instance.localToWorldTransposedInverse * float4(tangent, 0.0f)).xyz;
    out.worldSpaceBitangent = cross(out.worldSpaceNormal, out.worldSpaceTangent);

    out.uv0 = uv0;
    out.normal = float4(normal, 1.0f);

    return out;
}

struct GltfPbrFragmentData
{
    float3 cameraPosition;
    uint mipLevels;
};

fragment half4 gltf_pbr_fragment(
    GltfPbrRasterizerData in [[stage_in]],
    device GltfPbrFragmentData const& data [[buffer(bindings::globalFragmentData)]],
    texture2d<float, access::sample> baseColorMap [[texture(bindings::baseColorMap)]],
    texture2d<float, access::sample> normalMap [[texture(bindings::normalMap)]],
    texture2d<float, access::sample> metallicRoughnessMap [[texture(bindings::metallicRoughnessMap)]],
    texture2d<float, access::sample> prefilteredEnvironmentMap [[texture(bindings::prefilteredEnvironmentMap)]],
    texture2d<float, access::sample> brdfLookupTexture [[texture(bindings::brdfLookupTexture)]],
    texture2d<float, access::sample> irradianceMap [[texture(bindings::irradianceMap)]]
)
{
    constexpr sampler mipSampler(address::repeat, filter::linear, mip_filter::linear);
    constexpr sampler sampler(address::repeat, filter::linear);

    float3 occlusionMetalnessRoughness = metallicRoughnessMap.sample(sampler, in.uv0).rgb;
    float occlusion = occlusionMetalnessRoughness.r;
    float roughness = occlusionMetalnessRoughness.g;
    float metalness = occlusionMetalnessRoughness.b;

    // normal mapping
    float3x3 normalToWorld = float3x3(
        normalize(in.worldSpaceTangent),
        normalize(in.worldSpaceBitangent),
        normalize(in.worldSpaceNormal)
    );
    float3 localNormal = normalMap.sample(sampler, in.uv0).rgb;
    localNormal = localNormal * 2.0f - 1.0f;

    float3 normal = normalize(normalToWorld * localNormal);
    float3 cameraDirection = normalize(in.worldSpacePosition - data.cameraPosition);
    float3 outDirection = reflect(cameraDirection, normal);

    // when the normal faces the camera, the dot product becomes 1.0f, which creates a white spot, so we add a slight offset
    float nDotV = clamp(dot(normal, -cameraDirection), 0.001f, 0.999f);

    // uvs
    float2 outDirectionUv = directionToUvEquirectangular(outDirection);
    float2 normalUv = directionToUvEquirectangular(normal);

    // F0 is the color when the normal faces the camera
    float3 baseColor = baseColorMap.sample(sampler, in.uv0).rgb;
    float3 F0 = mix(float3(0.04, 0.04, 0.04), baseColor, metalness);

    float3 Fr = max(float3(1.0f - roughness), F0) - F0;
    float3 kS = F0 + Fr * pow(1.0f - nDotV, 5.0f);

    float2 f_ab = brdfLookupTexture.sample(sampler, float2(nDotV, clamp(roughness, 0.001f, 0.999f))).rg;
    float3 FssEss = kS * f_ab.x + f_ab.y;

    float mipLevel = roughness * data.mipLevels;
    float3 radiance = prefilteredEnvironmentMap.sample(mipSampler, outDirectionUv, level(mipLevel)).rgb;

    float3 irradiance = irradianceMap.sample(sampler, normalUv).rgb;

    // multiple scattering
    float Ess = f_ab.x + f_ab.y;
    float Ems = 1.0f - Ess;
    float3 Favg = F0 + (1.0f - F0) / 21;
    float3 Fms = FssEss * Favg / (1.0f - (1.0f - Ess) * Favg);

    // conductors
    float3 conductor = FssEss * radiance + Fms * Ems * irradiance;

    // dielectrics
    float3 albedo = baseColor;

    float3 Edss = 1.0f - (FssEss + Fms * Ems);
    float3 kD = albedo * Edss;
    float3 dielectric = FssEss * radiance + (Fms*Ems+kD) * irradiance;

    float3 color = mix(dielectric, conductor, metalness);

    color *= occlusion;
    return half4(float4(color, 1.0f));
}
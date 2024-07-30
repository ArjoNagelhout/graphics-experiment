// http://holger.dammertz.org/stuff/notes_HammersleyOnHemisphere.html
float2 hammersley(uint i, uint N)
{
    uint bits = (i << 16u) | (i >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    float radicalInverse = float(bits) * 2.3283064365386963e-10;

    return float2(float(i) / float(N), radicalInverse);
}

struct PBRPrefilterEnvironmentMapData
{
    float roughness;
    uint mipLevel;
    uint width;
    uint height;
};

float4 sampleEquirectangular(float3 direction, texture2d<float, access::sample> source)
{
    direction = normalize(direction);

    float theta = atan2(direction.z, direction.x); // longitude
    float phi = asin(direction.y); // latitude

    // map spherical coordinates to texture coordinates
    float u = (theta / (2.0 * M_PI_F)) + 0.5f;
    float v = (phi / M_PI_F) + 0.5f;

    float2 uv{u, 1.0f-v};
    constexpr sampler s(address::repeat, filter::linear);
    return source.sample(s, uv);
}

float3 importanceSampleGGX(float2 Xi, float roughness, float3 N)
{
    float a = roughness * roughness;
    float phi = 2 * M_PI_F;
    return N;
}

// equirectangular projection (for now)
// https://cdn2.unrealengine.com/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf
//
kernel void pbr_prefilter_environment_map(
    device PBRPrefilterEnvironmentMapData const& data [[buffer(0)]],
    texture2d<float, access::sample> source [[texture(1)]],
    texture2d<float, access::write> outView [[texture(2)]], // specific mip map level
    uint2 id [[thread_position_in_grid]]
)
{
    if (id.x >= data.width || id.y >= data.height)
    {
        return;
    }

    if (data.roughness == 0.0f)
    {
        return;
    }

    // determine direction vector based on grid id

    float3 R = float3(0, 0, 0); // direction vector
    float3 N = R;
    float3 V = R;

    float3 color = float3(0, 0, 0);
    float totalWeight = 0;

    uint const samples = 32;
    for (uint i = 0; i < samples; i++)
    {
        float2 Xi = hammersley(i, samples);
        float3 H = importanceSampleGGX(Xi, data.roughness, N);
        float3 L = 2 * dot(V, H) * H - V;

        // NoL is the contributing weight of this sample to the output color
        float NoL = saturate(dot(N, L)); // saturate clamps range 0.0-1.0

        if (NoL > 0) // weight 0 does not contribute, so skip
        {
            // sample
            color += sampleEquirectangular(L, source).rgb * NoL;
            totalWeight += NoL;
        }
    }

    color /= totalWeight;

    // write to pixel

}
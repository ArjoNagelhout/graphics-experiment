// irradiance map
kernel void pbr_create_irradiance_map(

)
{

}

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
    uint sampleCount;
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

// get direction vector from 2D (between 0 and 1) UV coordinates
float3 uvToDirectionEquirectangular(float2 uv)
{
    float u = uv.x;
    float v = 1.0f - uv.y;

    // uv coordinates to spherical coordinates
    float theta = (u - 0.5f) * 2.0f * M_PI_F;
    float phi = (v - 0.5f) * M_PI_F;

    // spherical coordinates to cartesian coordinates
    float x = cos(phi) * cos(theta);
    float y = sin(phi);
    float z = cos(phi) * sin(theta);

    return float3(x, y, z);
}

float3 importanceSampleGGX(float2 Xi, float roughness, float3 N)
{
    float a = roughness * roughness;
    float phi = 2 * M_PI_F * Xi.x;
    float cosTheta = sqrt((1 - Xi.y) / (1 + (a * a - 1) * Xi.y));
    float sinTheta = sqrt(1 - cosTheta * cosTheta);

    float3 H = float3(
        sinTheta * cos(phi),
        sinTheta * sin(phi),
        cosTheta);

    float3 upVector = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangentX = normalize(cross(upVector, N));
    float3 tangentY = cross(N, tangentX);

    // convert tangent to world space
    return tangentX * H.x + tangentY * H.y + N * H.z;
}

// uses equirectangular projection
// https://cdn2.unrealengine.com/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf
kernel void pbr_create_prefiltered_environment_map(
    device PBRPrefilterEnvironmentMapData const& data [[buffer(0)]],
    texture2d<float, access::sample> source [[texture(1)]],
    texture2d<float, access::write> outView [[texture(2)]], // specific mip map level
    uint2 id [[thread_position_in_grid]]
)
{
    // determine direction vector based on grid id
    float2 uv = float2(float(id.x) / (float)data.width, float(id.y) / (float)data.height);
    float3 R = uvToDirectionEquirectangular(uv); // direction vector
    float3 N = R;
    float3 V = R;

    float3 color = float3(0, 0, 0);
    float totalWeight = 0;

    for (uint i = 0; i < data.sampleCount; i++)
    {
        float2 Xi = hammersley(i, data.sampleCount);
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
    outView.write(float4(color, 1.0f), id);
}

struct PBRIntegrateBRDFData
{
    uint width;
    uint height;
    uint sampleCount;
};

// https://bruop.github.io/ibl/
// https://google.github.io/filament/Filament.html#toc4.4.2
float gSmithApproximation(float roughness, float nDotV, float nDotL)
{
    float a2 = pow(roughness, 4);
    float ggxV = nDotL * sqrt(nDotV * nDotV * (1.0f - a2) + a2);
    float ggxL = nDotV * sqrt(nDotL * nDotL * (1.0f - a2) + a2);
    return 0.5f / (ggxV + ggxL);
}

kernel void pbr_create_brdf_lookup_texture(
    device PBRIntegrateBRDFData const& data [[buffer(0)]],
    texture2d<float, access::write> lookupTexture [[texture(1)]],
    uint2 id [[thread_position_in_grid]]
)
{
    float nDotV = (float)id.x / (float)data.width;
    float roughness = (float)id.y / (float)data.height;

    float3 V = float3(
        sqrt(1.0f - nDotV * nDotV), // sin
        0,
        nDotV); // cos
    float3 N = float3(0, 0, 1);

    float2 value = float2(0, 0);

    for (uint i = 0; i < data.sampleCount; i++)
    {
        float2 Xi = hammersley(i, data.sampleCount);
        float3 H = importanceSampleGGX(Xi, roughness, N); // where does N come from??

        float3 lightDirection = 2 * dot(V, H) * H - V;

        float nDotL = saturate(dot(N, lightDirection));
        float nDotH = saturate(dot(N, H));
        float vDotH = saturate(dot(V, H));

        if (nDotL > 0)
        {
            float g = gSmithApproximation(roughness, nDotV, nDotL);
            float gVisible = g * vDotH * nDotL / nDotH;
            float Fc = pow(1.0f - vDotH, 5);
            value.x += (1.0f - Fc) * gVisible;
            value.y += Fc * gVisible;
        }
    }

    lookupTexture.write(4.0f * float4(value / data.sampleCount, 0, 0), id);
}
#include <metal_stdlib>
using namespace metal;

// Vertex shader outputs and fragment shader inputs
struct RasterizerData
{
    float4 position [[position]];
    float4 color;
    float2 uv0;
    float4 normal;
};

struct RasterizerDataLit
{
    float4 position [[position]];
    float4 color;
    float2 uv0;
    float4 normal;
    float4 fragmentPosition;
    float4 fragmentPositionLightSpace;
};

struct CameraData
{
    float4x4 viewProjection;
};

struct InstanceData
{
    float4x4 localToWorld;
};

struct LightData
{
    float4x4 lightSpace;
};

float calculateIsInLight(float4 positionLightSpace, depth2d<float, access::sample> texture)
{
    // perform perspective divide
    float3 projected = positionLightSpace.xyz / positionLightSpace.w;

    // transform from NDC (between -1 and 1) to texture coordinates (between 0 and 1)
    float4x4 toTextureCoordinates(
        0.5, 0.0, 0.0, 0.0,
        0.0, -0.5, 0.0, 0.0, // flipped y axis
        0.0, 0.0, 0.5, 0.0,
        0.5, 0.5, 0.5, 1.0
    );

    float3 textureCoordinates = (toTextureCoordinates * float4(projected, 1)).xyz;

    // get depth of current fragment from light's perspective
    float depthOfThisFragment = projected.z - 0.001;

    constexpr sampler s(address::clamp_to_edge, filter::linear, compare_func::less_equal);
    float shadow = texture.sample_compare(s, textureCoordinates.xy, depthOfThisFragment);
    return shadow;
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

float2 directionToUvEquirectangular(float3 direction)
{
    direction = normalize(direction);

    float theta = atan2(direction.z, direction.x); // longitude
    float phi = asin(direction.y); // latitude

    // map spherical coordinates to texture coordinates
    float u = (theta / (2.0 * M_PI_F)) + 0.5f;
    float v = (phi / M_PI_F) + 0.5f; //up: 1, down: 0.000002

    float2 uv{u, 1.0f-clamp(v, 0.01f, 0.99f)};
    return uv;
}

float4 sampleEquirectangular(float3 direction, texture2d<float, access::sample> source)
{
    float2 uv = directionToUvEquirectangular(direction);
    constexpr sampler s(address::repeat, filter::linear);
    return source.sample(s, uv);
}
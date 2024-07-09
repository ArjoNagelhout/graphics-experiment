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

struct VertexData
{
    float4 position;
    float4 normal;
    float4 color;
    float2 uv0;
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
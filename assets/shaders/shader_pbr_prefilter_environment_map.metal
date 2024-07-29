struct PBRPrefilterEnvironmentMapData
{
    float roughness;
    unsigned int mipLevel;
};

// equirectangular projection (for now)
kernel void pbr_prefilter_environment_map(
    device PBRPrefilterEnvironmentMapData const& data [[buffer(0)]],
    texture2d<half, access::sample> source [[texture(1)]],
    texture2d<half, access::write> outView [[texture(2)]],
    uint2 id [[thread_position_in_grid]]
)
{

}
struct DepthClearVertexIn
{
    float2 position [[ attribute(0) ]];
};

struct DepthClearVertexOut
{
    float4 position [[ position ]];
};

struct DepthClearFragmentOut
{
    float depth [[depth(any)]];
};

vertex DepthClearVertexOut
depth_clear_vertex(DepthClearVertexIn in [[ stage_in ]])
{
    DepthClearVertexOut out;
    // Just pass the position through. We're clearing in NDC space.
    out.position = float4(in.position, 0.5, 1.0);
    return out;
}

fragment DepthClearFragmentOut depth_clear_fragment()
{
    DepthClearFragmentOut out;
    out.depth = 1.0;
    return out;
}
struct RasterizerDataBlinnPhong
{
    float4 position [[position]];
    float4 color;
    float2 uv0;
    float4 normal;

    // blinn phong specific

    // we calculate the lighting in world space, so
    // that we don't have to transform the lighting
    // for each fragment
    float3 worldSpacePosition;
    float3 worldSpaceNormal;
};

struct BlinnPhongVertexData
{
    // as normals are direction vectors perpendicular to the surface, we can't
    // multiply the normal by the localToWorld matrix.
    //
    // see Introduction to 3D game programming with DirectX 9.0c page 247
    // the transposed inverse of the localToWorld matrix gives the correct normal vector
    // that is perpendicular to the surface
    float4x4 localToWorldTransposedInverse;
};

vertex RasterizerDataBlinnPhong blinn_phong_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device VertexData const* vertices [[buffer(0)]],
    device CameraData const& camera [[buffer(1)]],
    device InstanceData const* instances [[buffer(2)]],
    device BlinnPhongVertexData const& blinnPhong [[buffer(3)]])
{
    RasterizerDataBlinnPhong out;
    device VertexData const& data = vertices[vertexID];
    device InstanceData const& instance = instances[instanceID];

    float4 position = instance.localToWorld * data.position;
    out.position = camera.viewProjection * position;
    out.worldSpacePosition = position.xyz / position.w;
    out.worldSpaceNormal = normalize((blinnPhong.localToWorldTransposedInverse * float4(data.normal.xyz, 0.0f)).xyz);

    out.normal = data.normal;
    out.color = data.color;
    out.uv0 = data.uv0;
    return out;
}

float3 blinnPhongBRDF(
    float3 lightDirection,
    float3 viewDirection,
    float3 normal,
    float3 diffuseColor,
    float3 specularColor,
    float shininess)
{
    float3 color = diffuseColor;
    float3 halfDirection = normalize(viewDirection + lightDirection);
    float specularDot = max(dot(halfDirection, normal), 0.0);
    color += pow(specularDot, shininess) * specularColor;
    return color;
}

struct BlinnPhongFragmentData
{
    float3 cameraPosition;
    float3 lightDirection;

    // colors
    float3 ambientColor;
    float3 specularColor;
    float3 lightColor;

    // parameters
    float irradiancePerp;
    float shininess;
};

fragment half4 blinn_phong_fragment(
    RasterizerDataBlinnPhong in [[stage_in]],
    texture2d< float, access::sample > tex [[texture(0)]],
    device BlinnPhongFragmentData const& blinnPhong [[buffer(1)]])
{
    constexpr sampler s(address::repeat, filter::nearest);
    float3 diffuseColor = tex.sample(s, in.uv0).xyz;

    float3 lightDirection = normalize(-blinnPhong.lightDirection);
    float3 viewDirection = normalize(blinnPhong.cameraPosition - in.worldSpacePosition);

    float3 radiance = blinnPhong.ambientColor;

    float irradiance = max(dot(lightDirection, in.worldSpaceNormal), 0.0) * blinnPhong.irradiancePerp;
    if(irradiance > 0.0)
    {
        float3 brdf = blinnPhongBRDF(
            lightDirection,
            viewDirection,
            in.worldSpaceNormal,
            diffuseColor,
            blinnPhong.specularColor,
            blinnPhong.shininess);
        radiance += brdf * irradiance * blinnPhong.lightColor;
    }

    radiance = pow(radiance, float3(1.0 / 2.2) ); // gamma correction, is this needed?
    half3 r = half3(radiance);
    return half4(r, 1.0f);
}
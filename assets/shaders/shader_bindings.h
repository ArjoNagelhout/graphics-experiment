#ifndef METAL_EXPERIMENT_SHADER_BINDINGS_H
#define METAL_EXPERIMENT_SHADER_BINDINGS_H

// used by both shader code and the main codebase

#ifdef SHADER_BINDINGS_MAIN
// for in the main codebase
#define BINDING static constexpr
#else
// for inside shader
#define BINDING constant
#endif

    // vertex bindings
namespace binding_vertex
{
    BINDING int cameraData = 0;
    BINDING int instanceData = 1;
    BINDING int lightData = 2;
    BINDING int globalVertexData = 3; // same for each vertex
    BINDING int vertexData = 4; // interleaved data

    // deinterleaved data
    BINDING int positions = 4;
    BINDING int normals = 5;
    BINDING int uv0s = 6;
    BINDING int colors = 7;
    BINDING int lightMapUvs = 8;
    BINDING int tangents = 9;
}

    // fragment bindings
namespace binding_fragment
{
    BINDING int fragmentData = 0; // same for each fragment
    BINDING int materialData = 1;
    BINDING int texture = 2;
    BINDING int shadowMap = 3;
    BINDING int reflectionMap = 4; // skybox or reflection probe
    BINDING int prefilteredEnvironmentMap = 5;
    BINDING int brdfLookupTexture = 6;
    BINDING int irradianceMap = 7;
    BINDING int normalMap = 8;
    BINDING int baseColorMap = 9;
    BINDING int metallicRoughnessMap = 10;
    BINDING int emissionMap = 11;

}

    // function constants bindings (for shader variants)
namespace binding_constant
{
    BINDING int alphaCutout = 0; // bool
    BINDING int hasBaseColorMap = 1; // bool
    BINDING int hasNormalMap = 2; // bool
    BINDING int hasMetallicRoughnessMap = 3; // bool
}

// common types

#ifdef SHADER_BINDINGS_MAIN
// for in the main codebase
#define FLOAT3 simd_float3
#define FLOAT4 simd_float4
#define MATRIX4X4 glm::mat4
#else
// for inside shader
#define FLOAT3 float3
#define FLOAT4 float4
#define MATRIX4X4 float4x4
#endif

struct PbrMaterialData
{
    // used if the shader does not have maps defined: (set shader constants)
    float metalness;
    float roughness;
    FLOAT3 baseColor;
};

struct PbrFragmentData
{
    FLOAT3 cameraPosition;
    unsigned int mipLevels;
};

struct PbrInstanceData
{
    MATRIX4X4 localToWorld;
    MATRIX4X4 localToWorldTransposedInverse;
};

#endif //METAL_EXPERIMENT_SHADER_BINDINGS_H

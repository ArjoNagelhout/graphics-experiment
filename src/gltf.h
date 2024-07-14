#ifndef BORED_C_GLTF_H
#define BORED_C_GLTF_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "mesh.h"

#include "cgltf.h"

static constexpr size_t invalidIndex = std::numeric_limits<size_t>::max();

struct GltfMaterial
{
    // texture indices
    size_t baseColor = invalidIndex;
    size_t metallicRoughness = invalidIndex;
};

struct GltfVertexAttribute
{
    cgltf_attribute_type type;
    size_t componentCount;
    size_t size; // size of this part of the buffer
};

struct GltfPrimitive
{
    // buffers
    id <MTLBuffer> vertexBuffer;
    id <MTLBuffer> indexBuffer;

    size_t vertexCount;
    MTLPrimitiveType primitiveType;
    MTLIndexType indexType;
    size_t indexCount;

    // attributes descriptor
    std::vector<GltfVertexAttribute> attributes;

    // material reference
    size_t material = invalidIndex;
};

// contains multiple materials
struct GltfMesh
{
    std::vector<GltfPrimitive> primitives;
};

struct GltfModel
{
    std::vector<GltfMesh> meshes;
    std::vector<id <MTLTexture>> textures;
    std::vector<GltfMaterial> materials;
};

// returns true when successful
bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, GltfModel* outModel);

#endif //BORED_C_GLTF_H

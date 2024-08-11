#ifndef METAL_EXPERIMENT_GLTF_H
#define METAL_EXPERIMENT_GLTF_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "mesh.h"

#include "cgltf.h"

#import "glm/detail/type_mat4x4.hpp"

static constexpr size_t invalidIndex = std::numeric_limits<size_t>::max();

struct GltfMaterialPbr
{
    size_t baseColorMap = invalidIndex; // texture index
    size_t metallicRoughnessMap = invalidIndex; // texture index
    size_t normalMap = invalidIndex; // texture index
    size_t emissionMap = invalidIndex; // texture index
};

struct GltfPrimitive
{
    PrimitiveDeinterleaved mesh;

    // material reference
    size_t material = invalidIndex;
};

// contains multiple materials
struct GltfMesh
{
    std::vector<GltfPrimitive> primitives;
};

struct GltfScene
{
    size_t rootNode;
};

struct GltfNode
{
    size_t meshIndex = invalidIndex;
    glm::mat4 localTransform;
    std::vector<size_t> childNodes;
};

struct GltfModel
{
    // data
    std::vector<GltfMesh> meshes;
    std::vector<id <MTLTexture>> textures;
    std::vector<GltfMaterialPbr> materials;

    // scenes
    std::vector<GltfScene> scenes;
    std::vector<GltfNode> nodes;
};

// returns true when successful
[[nodiscard]] bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, GltfModel* outModel);

#endif //METAL_EXPERIMENT_GLTF_H

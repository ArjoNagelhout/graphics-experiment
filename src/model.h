//
// Created by Arjo Nagelhout on 15/08/2024.
//

#ifndef METAL_EXPERIMENT_MODEL_H
#define METAL_EXPERIMENT_MODEL_H

#include "mesh.h"
#include "constants.h"

#include <filesystem>

#include "glm/detail/type_mat4x4.hpp"

namespace model
{
    struct Material
    {
        simd_float3 baseColor; // used if base color map not set
        size_t baseColorMap = invalidIndex; // texture index

        float metalness; // used if metallic roughness map not set
        float roughness; // used if metallic roughness map not set
        size_t metallicRoughnessMap = invalidIndex; // texture index
        size_t normalMap = invalidIndex; // texture index
        size_t emissionMap = invalidIndex; // texture index
    };

    struct Primitive
    {
        PrimitiveDeinterleaved primitive;
        size_t materialIndex = invalidIndex;
    };

    struct Mesh
    {
        std::vector<Primitive> primitives;
    };

    struct Node
    {
        size_t meshIndex = invalidIndex;
        glm::mat4 localTransform;
        std::vector<size_t> childNodes;
    };

    struct Scene
    {
        size_t rootNode;
    };

    // contains all data for rendering a specific 3d model
    // used for both ifc and gltf
    struct Model
    {
        // data
        std::vector<Mesh> meshes;
        std::vector<id <MTLTexture>> textures;
        std::vector<Material> materials;

        // scenes
        std::vector<Scene> scenes;
        std::vector<Node> nodes;
    };
}

#endif //METAL_EXPERIMENT_MODEL_H

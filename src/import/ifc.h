//
// Created by Arjo Nagelhout on 11/08/2024.
//

#ifndef METAL_EXPERIMENT_IFC_H
#define METAL_EXPERIMENT_IFC_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "glm/mat4x4.hpp"

#include "../mesh.h"
#include "../common.h"

struct IfcImportSettings
{
    bool flipYAndZAxes;
};

struct IfcNode
{
    size_t meshIndex = invalidIndex;
    glm::mat4 localTransform;
    std::vector<size_t> childNodes;
};

struct IfcMesh
{
    // change into a list of primitives for different materials
    PrimitiveDeinterleaved primitive;
};

struct IfcModel
{
    std::vector<IfcMesh> meshes;
    std::vector<IfcNode> nodes;
};

// returns true when successful
[[nodiscard]] bool importIfc(id <MTLDevice> device, std::filesystem::path const& path, IfcModel* outModel, IfcImportSettings settings);

#endif //METAL_EXPERIMENT_IFC_H

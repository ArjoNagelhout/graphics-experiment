//
// Created by Arjo Nagelhout on 11/08/2024.
//

#ifndef METAL_EXPERIMENT_IFC_H
#define METAL_EXPERIMENT_IFC_H

#include <filesystem>
#include <vector>
#include <unordered_map>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "glm/mat4x4.hpp"

#include "../model.h"
#include "../mesh.h"
#include "../constants.h"

struct IfcImportSettings
{
    bool flipYAndZAxes;
};

// returns true when successful
[[nodiscard]] bool importIfc(id <MTLDevice> device, std::filesystem::path const& path, model::Model* outModel, IfcImportSettings settings);

#endif //METAL_EXPERIMENT_IFC_H

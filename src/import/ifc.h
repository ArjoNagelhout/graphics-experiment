//
// Created by Arjo Nagelhout on 11/08/2024.
//

#ifndef METAL_EXPERIMENT_IFC_H
#define METAL_EXPERIMENT_IFC_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "../mesh.h"

struct IfcImportSettings
{
    bool flipYAndZAxes;
};

struct IfcModel
{
    std::vector<PrimitiveDeinterleaved> meshes;
};

// returns true when successful
[[nodiscard]] bool importIfc(id <MTLDevice> device, std::filesystem::path const& path, IfcModel* outModel, IfcImportSettings settings);

#endif //METAL_EXPERIMENT_IFC_H

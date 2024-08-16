#ifndef METAL_EXPERIMENT_GLTF_H
#define METAL_EXPERIMENT_GLTF_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "mesh.h"
#include "constants.h"
#include "model.h"

// returns true when successful
[[nodiscard]] bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, model::Model* outModel);

#endif //METAL_EXPERIMENT_GLTF_H

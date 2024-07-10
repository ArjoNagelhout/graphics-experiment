#ifndef BORED_C_GLTF_H
#define BORED_C_GLTF_H

#include <filesystem>

#import <Metal/MTLDevice.h>
#import <Metal/MTLTexture.h>

#include "mesh.h"

struct GltfModel
{
    std::vector<Mesh> meshes;
    std::vector<id <MTLTexture>> textures;
};

// returns true when successful
bool importGltf(id <MTLDevice> device, std::filesystem::path const& path, GltfModel* outModel);

#endif //BORED_C_GLTF_H

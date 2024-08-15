//
// Created by Arjo Nagelhout on 15/08/2024.
//

#ifndef METAL_EXPERIMENT_SCENE_H
#define METAL_EXPERIMENT_SCENE_H

#include "mesh.h"

#include <filesystem>

struct Material
{

};

struct Primitive
{
    PrimitiveDeinterleaved primitive;
    Material* material;
};

struct Mesh
{

};

struct Node
{
    Mesh* mesh;
};

struct Scene
{
    Node* node;
};

// there should be a container of all assets
// assets should be lazily loadable

// what is the problem an asset database solves:

// 1. caching of assets
// when an asset is already imported once, it generates some artifacts, and doesn't need to be imported again.
// this is especially useful with CAD data, as the optimization steps

// this gives the following functions:

// copyFileToAssetsDirectory() -> this duplicates the source file from the source location to the assets directory
// convertFile() -> calls convertIfc() or convertGltf() -> this creates a set of meshes etc. (exists in cache, memory) (this should be done on a separate thread)
// saveCacheToDisk() -> this stores the cache onto the disk
// saveMesh() -> this creates a mesh inside the asset
//

// assets watcher
// for (file in assetsDirectory)
// {
//      if (cache.contains(file)
//      {
//          break;
//      }
//
//      threadpool.enqueue([] {
//          convertFile(file);
//          saveCacheToDisk()
//      });
// }

// 2. extracting of imported assets
// similar to caching, we can also retrieve for example the generated meshes from the CAD file import,
// which can then be saved as a separate file.

// automatic loading of specific assets

// e.g. one file references another file, which references another file
// each of these files should then be imported as well, because they are dependencies



struct AssetId
{
    std::string relativePath;
};

enum class AssetHandleStatus
{
    None = 0,
    Loaded,
    Error
};

struct AssetHandle
{
    AssetId id;
    AssetHandleStatus status;
    void* data;
};

struct Assets
{
    std::unordered_map<AssetId, AssetHandle> assets;
};

#endif //METAL_EXPERIMENT_SCENE_H

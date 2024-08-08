//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef METAL_EXPERIMENT_PROCEDURAL_MESH_H
#define METAL_EXPERIMENT_PROCEDURAL_MESH_H

#include "mesh.h"

class RectMinMaxf;

// create rounded cube
[[nodiscard]] PrimitiveDeinterleaved createRoundedCube(id <MTLDevice> device, simd_float3 size, float cornerRadius, int cornerDivisions);

[[nodiscard]] PrimitiveDeinterleaved createUVSphere(id <MTLDevice> device, int horizontalDivisions, int verticalDivisions);

// create cube without uv coordinates (requires fewer vertices)
[[nodiscard]] PrimitiveDeinterleaved createCubeWithoutUV(id <MTLDevice> device);

// create cube
[[nodiscard]] PrimitiveDeinterleaved createCube(id <MTLDevice> device);

[[nodiscard]] PrimitiveDeinterleaved createPlane(id <MTLDevice> device, RectMinMaxf extents);

// creates two vertical planes that cross each other
[[nodiscard]] PrimitiveDeinterleaved createTree(id <MTLDevice> device, float width, float height);

// because we want to use the generated vertices for placing trees, we don't create the mesh
// but return the vertices, indices and primitive type (hacky)
void createTerrain(
    RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions,
    std::vector<float3>* outPositions, std::vector<uint32_t>* outIndices, MTLPrimitiveType* outPrimitiveType);

[[nodiscard]] PrimitiveDeinterleaved createAxes(id <MTLDevice> device);

#endif //METAL_EXPERIMENT_PROCEDURAL_MESH_H

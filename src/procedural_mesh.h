//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef BORED_C_ROUNDED_CUBE_H
#define BORED_C_ROUNDED_CUBE_H

#include "mesh.h"

class RectMinMaxf;

// create rounded cube
[[nodiscard]] Mesh createRoundedCube(id <MTLDevice> device, simd_float3 size, float cornerRadius, int cornerDivisions);

[[nodiscard]] Mesh createSphere(id <MTLDevice> device, int horizontalDivisions, int verticalDivisions);

// create cube without uv coordinates
[[nodiscard]] Mesh createCubeWithoutUV(id <MTLDevice> device);

// create cube
[[nodiscard]] Mesh createCube(id <MTLDevice> device);

[[nodiscard]] Mesh createPlane(id <MTLDevice> device, RectMinMaxf extents);

[[nodiscard]] Mesh createTree(id <MTLDevice> device, float width, float height);

void createTerrain(RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions,
                   std::vector<VertexData>* outVertices, std::vector<uint32_t>* outIndices, MTLPrimitiveType* outPrimitiveType);

#endif //BORED_C_ROUNDED_CUBE_H

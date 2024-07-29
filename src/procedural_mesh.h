//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef BORED_C_PROCEDURAL_MESH_H
#define BORED_C_PROCEDURAL_MESH_H

#include "mesh.h"

class RectMinMaxf;

// create rounded cube
[[nodiscard]] Mesh createRoundedCube(id <MTLDevice> device, simd_float3 size, float cornerRadius, int cornerDivisions);

[[nodiscard]] Mesh createUVSphere(id <MTLDevice> device, int horizontalDivisions, int verticalDivisions);

// create cube without uv coordinates (requires fewer vertices)
[[nodiscard]] Mesh createCubeWithoutUV(id <MTLDevice> device);

// create cube
[[nodiscard]] Mesh createCube(id <MTLDevice> device);

[[nodiscard]] Mesh createPlane(id <MTLDevice> device, RectMinMaxf extents);

// creates two vertical planes that cross each other
[[nodiscard]] Mesh createTree(id <MTLDevice> device, float width, float height);

// because we want to use the generated vertices for placing trees, we don't create the mesh
// but return the vertices, indices and primitive type (hacky)
void createTerrain(RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions,
                   std::vector<VertexData>* outVertices, std::vector<uint32_t>* outIndices, MTLPrimitiveType* outPrimitiveType);

[[nodiscard]] Mesh createAxes(id <MTLDevice> device);

#endif //BORED_C_PROCEDURAL_MESH_H

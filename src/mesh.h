//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef METAL_EXPERIMENT_MESH_H
#define METAL_EXPERIMENT_MESH_H

#include "simd/simd.h"

#import <Metal/Metal.h>

struct VertexData
{
    simd_float4 position;
    simd_float4 normal;
    simd_float4 color;
    simd_float2 uv0;
};

struct Mesh
{
    id <MTLBuffer> vertexBuffer;
    bool indexed;
    id <MTLBuffer> indexBuffer;
    MTLIndexType indexType;
    size_t vertexCount;
    size_t indexCount;
    MTLPrimitiveType primitiveType;
};

[[nodiscard]] Mesh createMesh(id <MTLDevice> device, std::vector<VertexData>* vertices, MTLPrimitiveType primitiveType);

[[nodiscard]] Mesh createMeshIndexed(id <MTLDevice> device, std::vector<VertexData>* vertices, std::vector<uint32_t>* indices, MTLPrimitiveType primitiveType);

#endif //METAL_EXPERIMENT_MESH_H

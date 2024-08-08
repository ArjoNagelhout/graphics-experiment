//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef METAL_EXPERIMENT_MESH_H
#define METAL_EXPERIMENT_MESH_H

#include "simd/simd.h"

#import <Metal/Metal.h>

#include <vector>

enum class VertexAttributeType : uint16_t
{
    Position,
    Normal,
    Tangent,
    TextureCoordinate,
    Color,
    Joints,
    Weights,
};

// only floats supported right now
struct VertexAttribute
{
    VertexAttributeType type;
    uint16_t index;
    size_t componentCount; // amount of floats per vertex (e.g. 3 for a vector3)
    size_t size; // size of this part of the buffer
};

// todo: use grouped interleaved attributes that are grouped per pass where they are needed
// e.g. shadow pass only needs 1., this is faster due to having less memory reads
// 1. position (uv0 if alpha testing)
// 2. normal, tangent, uv0, uv1, etc.
// 3. skinning data
// still store everything in the same buffer, only change attributes
// generate shader based on data layout
struct MeshDeinterleaved
{
    id <MTLBuffer> vertexBuffer;
    id <MTLBuffer> indexBuffer;
    size_t vertexCount;
    size_t indexCount;
    MTLPrimitiveType primitiveType;
    MTLIndexType indexType;
    bool indexed;
    std::vector<VertexAttribute> attributes;
};

struct float2
{
    float x;
    float y;
};

struct float3
{
    float x;
    float y;
    float z;
};

struct float4
{
    float x;
    float y;
    float z;
    float w;
};

[[nodiscard]] MeshDeinterleaved createMeshDeinterleaved(
    id <MTLDevice> device,
    std::vector<float3>* positions,
    std::vector<float3>* normals,
    std::vector<float4>* colors,
    std::vector<float2>* uv0s,
    std::vector<uint32_t>* indices, // if nullptr, this mesh is not indexed
    MTLPrimitiveType primitiveType);

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

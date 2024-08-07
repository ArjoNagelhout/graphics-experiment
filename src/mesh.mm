#include "mesh.h"

#include <vector>

Mesh createMesh(id <MTLDevice> device, std::vector<VertexData>* vertices, MTLPrimitiveType primitiveType)
{
    Mesh mesh{};
    mesh.indexed = false;
    mesh.indexType = MTLIndexTypeUInt32;
    mesh.primitiveType = primitiveType;

    // create vertex buffer
    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
    mesh.vertexBuffer = [device newBufferWithBytes:vertices->data() length:vertices->size() * sizeof(VertexData) options:options];
    mesh.vertexCount = vertices->size();

    return mesh;
}

Mesh createMeshIndexed(id <MTLDevice> device, std::vector<VertexData>* vertices, std::vector<uint32_t>* indices, MTLPrimitiveType primitiveType)
{
    Mesh mesh = createMesh(device, vertices, primitiveType);

    // create index buffer
    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
    mesh.indexBuffer = [device newBufferWithBytes:indices->data() length:indices->size() * sizeof(uint32_t) options:options];
    mesh.indexCount = indices->size();
    mesh.indexed = true;

    return mesh;
}

MeshDeinterleaved createMeshDeinterleaved(
    id <MTLDevice> device,
    std::vector<simd_float4>* positions,
    std::vector<simd_float4>* normals,
    std::vector<simd_float4>* colors,
    std::vector<simd_float2>* uv0s,
    std::vector<uint32_t>* indices, // if nullptr, this mesh is not indexed
    MTLPrimitiveType primitiveType)
{
    assert(positions && !positions->empty());

    MeshDeinterleaved mesh{};
    size_t offset = 0;
    mesh.vertexCount = positions->size();
    std::vector<VertexAttribute>* attributes = &mesh.attributes;

    // positions
    {
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Position,
            .componentCount = 4
        });
    }

    if (normals)
    {
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Normal,
            .componentCount = 4
        });
    }

    if (colors)
    {
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Color,
            .componentCount = 4
        });
    }

    if (uv0s)
    {
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::TextureCoordinate,
            .componentCount = 2
        });
    }

    // set sizes
    size_t totalSize = 0;
    for (VertexAttribute& attribute: *attributes)
    {
        attribute.size = attribute.componentCount * sizeof(float) * mesh.vertexCount;
        totalSize += attribute.size;
    }

    // create vertex buffer
    {
        MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
//        mesh.vertexBuffer = [device]
    }

    // indexed mesh
    if (indices)
    {
        mesh.indexed = true;
        mesh.indexType = MTLIndexTypeUInt32;

        // create index buffer
    }

    return mesh;
}
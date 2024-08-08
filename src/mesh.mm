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
    std::vector<float3>* positions,
    std::vector<float3>* normals,
    std::vector<float4>* colors,
    std::vector<float2>* uv0s,
    std::vector<uint32_t>* indices, // if nullptr, this mesh is not indexed
    MTLPrimitiveType primitiveType)
{
    assert(positions && !positions->empty());

    MeshDeinterleaved mesh{};
    mesh.vertexCount = positions->size();
    std::vector<VertexAttribute>* attributes = &mesh.attributes;
    mesh.primitiveType = primitiveType;

    // positions
    attributes->emplace_back(VertexAttribute{
        .type = VertexAttributeType::Position,
        .componentCount = 3
    });

    if (normals)
    {
        assert(normals->size() == mesh.vertexCount); // should be same amount of vertices
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Normal,
            .componentCount = 3
        });
    }

    if (colors)
    {
        assert(colors->size() == mesh.vertexCount); // should be same amount of vertices
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Color,
            .componentCount = 4
        });
    }

    if (uv0s)
    {
        assert(uv0s->size() == mesh.vertexCount); // should be same amount of vertices
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
        mesh.vertexBuffer = [device newBufferWithLength:totalSize options:options];
        auto* data = (unsigned char*)[mesh.vertexBuffer contents]; // unsigned char is 1 byte

        // copy data
        size_t offset = 0;
        for (VertexAttribute& attribute: *attributes)
        {
            void* source = nullptr;
            switch (attribute.type)
            {
                case VertexAttributeType::Position: source = positions->data(); break;
                case VertexAttributeType::Normal: source = normals->data(); break;
                case VertexAttributeType::Color: source = colors->data(); break;
                case VertexAttributeType::TextureCoordinate: source = uv0s->data(); break;
                default: continue;
            }
            memcpy(data + offset, source, attribute.size);
            offset += attribute.size;
        }

        NSRange range = NSMakeRange(0, totalSize);
        [mesh.vertexBuffer didModifyRange:range];
    }

    // indexed mesh
    if (indices)
    {
        mesh.indexed = true;
        mesh.indexType = MTLIndexTypeUInt32;

        // create index buffer
        MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        mesh.indexBuffer = [device newBufferWithBytes:indices->data() length:indices->size() * sizeof(uint32_t) options:options];
    }

    return mesh;
}
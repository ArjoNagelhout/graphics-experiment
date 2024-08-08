#include "mesh.h"

#include <vector>

[[nodiscard]] MeshDeinterleaved createMeshDeinterleaved(
    id <MTLDevice> device,
    MeshDeinterleavedDescriptor* descriptor)
{
    assert(descriptor->positions && !descriptor->positions->empty());

    MeshDeinterleaved mesh{};
    mesh.vertexCount = descriptor->positions->size();
    std::vector<VertexAttribute>* attributes = &mesh.attributes;
    mesh.primitiveType = descriptor->primitiveType;

    // positions
    attributes->emplace_back(VertexAttribute{
        .type = VertexAttributeType::Position,
        .componentCount = 3
    });

    if (descriptor->normals)
    {
        assert(descriptor->normals->size() == mesh.vertexCount); // should be same amount of vertices
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Normal,
            .componentCount = 3
        });
    }

    if (descriptor->colors)
    {
        assert(descriptor->colors->size() == mesh.vertexCount); // should be same amount of vertices
        attributes->emplace_back(VertexAttribute{
            .type = VertexAttributeType::Color,
            .componentCount = 4
        });
    }

    if (descriptor->uv0s)
    {
        assert(descriptor->uv0s->size() == mesh.vertexCount); // should be same amount of vertices
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
                //@formatter:off
                case VertexAttributeType::Position: source = descriptor->positions->data(); break;
                case VertexAttributeType::Normal: source = descriptor->normals->data(); break;
                case VertexAttributeType::Color: source = descriptor->colors->data(); break;
                case VertexAttributeType::TextureCoordinate: source = descriptor->uv0s->data(); break;
                default: continue;
                //@formatter:on
            }
            memcpy(data + offset, source, attribute.size);
            offset += attribute.size;
        }

        NSRange range = NSMakeRange(0, totalSize);
        [mesh.vertexBuffer didModifyRange:range];
    }

    // indexed mesh
    if (descriptor->indices)
    {
        assert(!descriptor->indices->empty());

        mesh.indexed = true;
        mesh.indexType = MTLIndexTypeUInt32;
        mesh.indexCount = descriptor->indices->size();

        // create index buffer
        MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        mesh.indexBuffer = [device newBufferWithBytes:descriptor->indices->data() length:descriptor->indices->size() * sizeof(uint32_t) options:options];
    }

    return mesh;
}
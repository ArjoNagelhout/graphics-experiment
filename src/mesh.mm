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
    [mesh.vertexBuffer retain];
    mesh.vertexCount = vertices->size();

    return mesh;
}

Mesh createMeshIndexed(id <MTLDevice> device, std::vector<VertexData>* vertices, std::vector<uint32_t>* indices, MTLPrimitiveType primitiveType)
{
    Mesh mesh = createMesh(device, vertices, primitiveType);

    // create index buffer
    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
    mesh.indexBuffer = [device newBufferWithBytes:indices->data() length:indices->size() * sizeof(uint32_t) options:options];
    [mesh.indexBuffer retain];
    mesh.indexCount = indices->size();
    mesh.indexed = true;

    return mesh;
}
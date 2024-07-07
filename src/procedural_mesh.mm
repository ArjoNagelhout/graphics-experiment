//
// Created by Arjo Nagelhout on 07/07/2024.
//

#include "mesh.h"

#include "common.h"
#include "rect.h"
#include "perlin.h"

#include <vector>

// adapted from std::clamp
float clamp(float value, float min, float max)
{
    return value < min ? min : max < value ? max : value;
}

struct RoundedCubeData
{
    simd_float3 size;
    float cornerRadius;
    int cornerVertices;
    float positionPerIndex;

    std::vector<VertexData> vertices;
    std::vector<uint32_t> indices;
};

void roundedCubeSetVertex(RoundedCubeData* data, int vertexIndex, simd_float3 position)
{
    position -= data->size / 2.0f;
    simd_float3 inner = position;

    VertexData& vertex = data->vertices[vertexIndex];

    vertex.position = simd_make_float4(position, 1.0f);

    simd_float3 min = -data->size / 2.0f + simd_make_float3(1.0f) * data->cornerRadius;
    simd_float3 max = data->size / 2.0f - simd_make_float3(1.0f) * data->cornerRadius;
    inner = simd_clamp(inner, min, max);

    simd_float3 normal = simd_normalize(position - inner);
    vertex.normal = simd_make_float4(normal, 1.0f);
    vertex.position = simd_make_float4(inner + normal * data->cornerRadius, 1.0f);
}

void roundedCubeAddRow(RoundedCubeData* data, int* const vertexIndex, float y)
{
    // side 1
    for (int x = 0; x < data->cornerVertices; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{(float)x * data->positionPerIndex, y, 0});
    }
    for (int x = 0; x < data->cornerVertices; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->size.x - data->cornerRadius + (float)x * data->positionPerIndex, y, 0});
    }

    // side 2
    for (int z = 1; z < data->cornerVertices; z++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->size.x, y, (float)z * data->positionPerIndex});
    }
    for (int z = 0; z < data->cornerVertices; z++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->size.x, y, data->size.z - data->cornerRadius + (float)z * data->positionPerIndex});
    }

    // side 3
    for (int x = 1; x < data->cornerVertices; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->size.x - (float)x * data->positionPerIndex, y, data->size.z});
    }
    for (int x = 0; x < data->cornerVertices; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->cornerRadius - (float)x * data->positionPerIndex, y, data->size.z});
    }

    // side 4
    for (int z = 1; z < data->cornerVertices; z++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{0, y, data->size.z - (float)z * data->positionPerIndex});
    }
    for (int z = 0; z < data->cornerVertices - 1; z++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{0, y, data->cornerRadius - (float)z * data->positionPerIndex});
    }
}

// create rounded cube
[[nodiscard]] Mesh createRoundedCube(id <MTLDevice> device, simd_float3 size, float cornerRadius, int cornerDivisions)
{
    float smallestSize = std::numeric_limits<float>::max();
    for (int i = 0; i < 3; i++)
    {
        if (size[i] < smallestSize)
        {
            smallestSize = size[i];
        }
    }

    RoundedCubeData data{
        .size = size,
        .cornerRadius = clamp(cornerRadius, 0, smallestSize / 2.0f),
    };

    // create vertices
    {
        int cornerVertices = cornerDivisions + 2;
        int ring = cornerVertices * 8 - 4;
        int around = ring * (cornerVertices * 2);
        int rowVertices = (cornerVertices * 2) - 2;
        int planeVertices = rowVertices * rowVertices;
        int totalVertices = 2 * planeVertices + around;
        data.vertices.resize(totalVertices);

        int v = 0;
        data.positionPerIndex = cornerRadius / (float)(cornerVertices - 1);
        for (int y = 0; y < cornerVertices; y++)
        {
            roundedCubeAddRow(
                &data,
                &v,
                (float)y * data.positionPerIndex);
        }
        for (int y = 0; y < cornerVertices; y++)
        {
            roundedCubeAddRow(
                &data,
                &v,
                size.y - cornerRadius + (float)y * data.positionPerIndex);
        }
    }

    // create triangles
    {

    }
}

Mesh createSphere(id <MTLDevice> device, int horizontalDivisions, int verticalDivisions)
{
    constexpr float angleCorrectionForCenterAlign = -0.5f * pi_;

    std::vector<VertexData> vertices;
    std::vector<uint32_t> indices;

    int latitudeIndex = 0;
    int longitudeIndex = 0;

    for (int w = 0; w <= horizontalDivisions; w++)
    {
        float theta = ((float)w / (float)horizontalDivisions - 0.5f) * pi_;
        float sinTheta = sin(theta);
        float cosTheta = cos(theta);

        for (int h = 0; h <= verticalDivisions; h++)
        {
            float phi = ((float)h / (float)verticalDivisions - 0.5f) * 2.0f * pi_ + angleCorrectionForCenterAlign;
            float sinPhi = sin(phi);
            float cosPhi = cos(phi);
            float x = cosPhi * cosTheta;
            float y = sinTheta;
            float z = sinPhi * cosTheta;
            float u = (float)h / (float)verticalDivisions;
            float v = 1.0f - (float)w / (float)horizontalDivisions;

            vertices.emplace_back(VertexData{.position{x, y, z, 1}, .uv0{u, v}});

            if (h != verticalDivisions && w != horizontalDivisions)
            {
                int a = w * (verticalDivisions + 1) + h;
                int b = a + verticalDivisions + 1;

                indices.emplace_back(a);
                indices.emplace_back(a + 1);
                indices.emplace_back(b);
                indices.emplace_back(b);
                indices.emplace_back(a + 1);
                indices.emplace_back(b + 1);
            }
        }
    }

    return createMeshIndexed(device, &vertices, &indices, MTLPrimitiveTypeTriangle);
}

// create cube without uv coordinates
[[nodiscard]] Mesh createCubeWithoutUV(id <MTLDevice> device)
{
    float s = 1.0f;
    std::vector<VertexData> vertices{
        {{-s, +s, -s, 1}},
        {{-s, -s, -s, 1}},
        {{+s, +s, -s, 1}},
        {{+s, -s, -s, 1}},
        {{-s, +s, +s, 1}},
        {{-s, -s, +s, 1}},
        {{+s, +s, +s, 1}},
        {{+s, -s, +s, 1}},
    };

    std::vector<uint32_t> indices{
        2, 3, 0, 1, invalidIndex,
        4, 5, 6, 7, invalidIndex,
        4, 0, 5, 1, 7, 3, 6, 2, 4, 0,
    };

    return createMeshIndexed(device, &vertices, &indices, MTLPrimitiveTypeTriangleStrip);
}

// create cube
[[nodiscard]] Mesh createCube(id <MTLDevice> device)
{
    float uvmin = 0.0f;
    float uvmax = 1.0f;
    float s = 1.0f;
    std::vector<VertexData> vertices{
        {.position{-s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // A 0
        {.position{+s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // B 1
        {.position{+s, +s, -s, 1}, .uv0{uvmax, uvmax}},  // C 2
        {.position{-s, +s, -s, 1}, .uv0{uvmin, uvmax}},  // D 3
        {.position{-s, -s, +s, 1}, .uv0{uvmin, uvmin}},  // E 4
        {.position{+s, -s, +s, 1}, .uv0{uvmax, uvmin}},  // F 5
        {.position{+s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // G 6
        {.position{-s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // H 7
        {.position{-s, +s, -s, 1}, .uv0{uvmin, uvmin}},  // D 8
        {.position{-s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // A 9
        {.position{-s, -s, +s, 1}, .uv0{uvmax, uvmax}},  // E 10
        {.position{-s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // H 11
        {.position{+s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // B 12
        {.position{+s, +s, -s, 1}, .uv0{uvmax, uvmin}},  // C 13
        {.position{+s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // G 14
        {.position{+s, -s, +s, 1}, .uv0{uvmin, uvmax}},  // F 15
        {.position{-s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // A 16
        {.position{+s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // B 17
        {.position{+s, -s, +s, 1}, .uv0{uvmax, uvmax}},  // F 18
        {.position{-s, -s, +s, 1}, .uv0{uvmin, uvmax}},  // E 19
        {.position{+s, +s, -s, 1}, .uv0{uvmin, uvmin}},  // C 20
        {.position{-s, +s, -s, 1}, .uv0{uvmax, uvmin}},  // D 21
        {.position{-s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // H 22
        {.position{+s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // G 23
    };
    std::vector<uint32_t> indices{
        // front and back
        0, 3, 2,
        2, 1, 0,
        4, 5, 6,
        6, 7, 4,
        // left and right
        11, 8, 9,
        9, 10, 11,
        12, 13, 14,
        14, 15, 12,
        // bottom and top
        16, 17, 18,
        18, 19, 16,
        20, 21, 22,
        22, 23, 20
    };

    return createMeshIndexed(device, &vertices, &indices, MTLPrimitiveTypeTriangle);
}

[[nodiscard]] Mesh createPlane(id <MTLDevice> device, RectMinMaxf extents)
{
    std::vector<VertexData> vertices{
        {.position{extents.minX, 0, extents.minY, 1}, .uv0{0, 1}},
        {.position{extents.minX, 0, extents.maxY, 1}, .uv0{0, 0}},
        {.position{extents.maxX, 0, extents.minY, 1}, .uv0{1, 1}},
        {.position{extents.maxX, 0, extents.maxY, 1}, .uv0{1, 0}},
    };
    return createMesh(device, &vertices, MTLPrimitiveTypeTriangleStrip);
}

[[nodiscard]] Mesh createTree(id <MTLDevice> device, float width, float height)
{
    std::vector<VertexData> vertices{
        {.position{-width / 2, 0, 0, 1}, .uv0{0, 1}},
        {.position{-width / 2, +height, 0, 1}, .uv0{0, 0}},
        {.position{+width / 2, 0, 0, 1}, .uv0{1, 1}},
        {.position{+width / 2, +height, 0, 1}, .uv0{1, 0}},
        {.position{0, 0, -width / 2, 1}, .uv0{0, 1}},
        {.position{0, +height, -width / 2, 1}, .uv0{0, 0}},
        {.position{0, 0, +width / 2, 1}, .uv0{1, 1}},
        {.position{0, +height, +width / 2, 1}, .uv0{1, 0}},
    };
    std::vector<uint32_t> indices{
        0, 1, 2, 3, invalidIndex, 4, 5, 6, 7
    };
    return createMeshIndexed(device, &vertices, &indices, MTLPrimitiveTypeTriangleStrip);
}

void createTerrain(RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions,
                   std::vector<VertexData>* outVertices, std::vector<uint32_t>* outIndices, MTLPrimitiveType* outPrimitiveType)
{
    float xSize = extents.maxX - extents.minX;
    float zSize = extents.maxY - extents.minY;
    uint32_t xCount = xSubdivisions + 1; // amount of vertices is subdivisions + 1
    uint32_t zCount = zSubdivisions + 1;
    outVertices->resize(xCount * zCount);

    float xStep = xSize / (float)xSubdivisions;
    float zStep = zSize / (float)zSubdivisions;

    for (uint32_t zIndex = 0; zIndex < zCount; zIndex++)
    {
        for (uint32_t xIndex = 0; xIndex < xCount; xIndex++)
        {
            float x = extents.minX + (float)xIndex * xStep;
            float z = extents.minY + (float)zIndex * zStep;

            float y = 0.1f * perlin(x * 8, z * 8) + 2.0f * perlin(x / 2, z / 2) + 10.0f * perlin(x / 9, z / 12);

            outVertices->at(zIndex * xCount + xIndex) = VertexData{
                .position{x, y, z, 1}, .color{0, 1, 0, 1}
            };
        }
    }

    // triangle strip
    for (uint32_t zIndex = 0; zIndex < zCount - 1; zIndex++)
    {
        for (uint32_t xIndex = 0; xIndex < xCount; xIndex++)
        {
            uint32_t offset = zIndex * xCount;
            outIndices->emplace_back(offset + xIndex);
            outIndices->emplace_back(offset + xIndex + xCount);
        }
        // reset primitive
        outIndices->emplace_back(invalidIndex);
    }

    *outPrimitiveType = MTLPrimitiveTypeTriangleStrip;
}
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

//-------------------------------
// rounded cube
//-------------------------------

struct RoundedCubeData
{
    simd_float3 size;
    float cornerRadius;
    int cornerDivisions;
    int cornerVertices;
    float positionPerIndex;

    std::vector<float3> positions;
    std::vector<float3> normals;
    std::vector<uint32_t> indices;
};

void roundedCubeSetVertex(RoundedCubeData* data, int vertexIndex, simd_float3 position)
{
    position -= data->size / 2.0f;
    simd_float3 inner = position;

    simd_float3 min = -data->size / 2.0f + simd_make_float3(1.0f, 1.0f, 1.0f) * data->cornerRadius;
    simd_float3 max = data->size / 2.0f - simd_make_float3(1.0f, 1.0f, 1.0f) * data->cornerRadius;
    inner = simd_clamp(inner, min, max);

    simd_float3 normal = simd_normalize(position - inner);
    data->normals[vertexIndex] = float3{normal.x, normal.y, normal.z};
    simd_float3 pos = inner + normal * data->cornerRadius;
    data->positions[vertexIndex] = float3{pos.x, pos.y, pos.z};
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

void roundedCubeAddHorizontalRow(RoundedCubeData* data, int* const vertexIndex, float y, float z)
{
    for (int x = 1; x < data->cornerVertices; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{(float)x * data->positionPerIndex, y, z});
    }
    for (int x = 0; x < data->cornerVertices - 1; x++)
    {
        roundedCubeSetVertex(data, (*vertexIndex)++, simd_float3{data->size.x - data->cornerRadius + (float)x * data->positionPerIndex, y, z});
    }
}

void roundedCubeAddHorizontalPlane(RoundedCubeData* data, int* const vertexIndex, float y)
{
    for (int z = 1; z < data->cornerVertices; z++)
    {
        roundedCubeAddHorizontalRow(data, vertexIndex, y, (float)z * data->positionPerIndex);
    }
    for (int z = 0; z < data->cornerVertices - 1; z++)
    {
        roundedCubeAddHorizontalRow(data, vertexIndex, y, data->size.z - data->cornerRadius + (float)z * data->positionPerIndex);
    }
}

int roundedCubeSetQuad(RoundedCubeData* data, int index, int v00, int v10, int v01, int v11)
{
    data->indices[index] = v00;
    data->indices[index + 1] = data->indices[index + 4] = v01;
    data->indices[index + 2] = data->indices[index + 3] = v10;
    data->indices[index + 5] = v11;
    return index + 6;
}

int roundedCubeCreateTopFace(RoundedCubeData* data, int t, int ring)
{
    int sizePerAxis = (data->cornerDivisions + 2) * 2 - 1;
    int v = ring * sizePerAxis;
    for (int x = 0; x < (sizePerAxis) - 1; x++, v++)
    {
        t = roundedCubeSetQuad(data, t, v, v + 1, v + ring - 1, v + ring);
    }
    t = roundedCubeSetQuad(data, t, v, v + 1, v + ring - 1, v + 2);

    int vMin = ring * (sizePerAxis + 1) - 1;
    int vMid = vMin + 1;
    int vMax = v + 2;

    for (int z = 1; z < sizePerAxis - 1; z++, vMin--, vMid++, vMax++)
    {
        t = roundedCubeSetQuad(data, t, vMin, vMid, vMin - 1, vMid + sizePerAxis - 1);
        for (int x = 1; x < sizePerAxis - 1; x++, vMid++)
        {
            t = roundedCubeSetQuad(
                data, t,
                vMid, vMid + 1, vMid + sizePerAxis - 1, vMid + sizePerAxis);
        }
        t = roundedCubeSetQuad(data, t, vMid, vMax, vMid + sizePerAxis - 1, vMax + 1);
    }

    int vTop = vMin - 2;
    t = roundedCubeSetQuad(data, t, vMin, vMid, vTop + 1, vTop);
    for (int x = 1; x < sizePerAxis - 1; x++, vTop--, vMid++)
    {
        t = roundedCubeSetQuad(data, t, vMid, vMid + 1, vTop, vTop - 1);
    }
    t = roundedCubeSetQuad(data, t, vMid, vTop - 2, vTop, vTop - 1);

    return t;
}

int roundedCubeCreateBottomFace(RoundedCubeData* data, int t, int ring)
{
    int sizePerAxis = (data->cornerDivisions + 2) * 2 - 1;
    int v = 1;
    int vMid = (int)data->positions.size() - (sizePerAxis - 1) * (sizePerAxis - 1);
    t = roundedCubeSetQuad(data, t, ring - 1, vMid, 0, 1);
    for (int x = 1; x < sizePerAxis - 1; x++, v++, vMid++)
    {
        t = roundedCubeSetQuad(data, t, vMid, vMid + 1, v, v + 1);
    }
    t = roundedCubeSetQuad(data, t, vMid, v + 2, v, v + 1);

    int vMin = ring - 2;
    vMid -= sizePerAxis - 2;
    int vMax = v + 2;

    for (int z = 1; z < sizePerAxis - 1; z++, vMin--, vMid++, vMax++)
    {
        t = roundedCubeSetQuad(data, t, vMin, vMid + sizePerAxis - 1, vMin + 1, vMid);
        for (int x = 1; x < sizePerAxis - 1; x++, vMid++)
        {
            t = roundedCubeSetQuad(
                data, t,
                vMid + sizePerAxis - 1, vMid + sizePerAxis, vMid, vMid + 1);
        }
        t = roundedCubeSetQuad(data, t, vMid + sizePerAxis - 1, vMax + 1, vMid, vMax);
    }

    int vTop = vMin - 1;
    t = roundedCubeSetQuad(data, t, vTop + 1, vTop, vTop + 2, vMid);
    for (int x = 1; x < sizePerAxis - 1; x++, vTop--, vMid++)
    {
        t = roundedCubeSetQuad(data, t, vTop, vTop - 1, vMid, vMid + 1);
    }
    t = roundedCubeSetQuad(data, t, vTop, vTop - 1, vMid, vTop - 2);

    return t;
}

MeshDeinterleaved createRoundedCube(id <MTLDevice> device, simd_float3 size, float cornerRadius, int cornerDivisions)
{
    float smallestSize = std::numeric_limits<float>::max();
    for (int i = 0; i < 3; i++)
    {
        if (size[i] < smallestSize)
        {
            smallestSize = size[i];
        }
    }

    RoundedCubeData data{};
    data.size = size;
    data.cornerRadius = clamp(cornerRadius, 0, smallestSize / 2.0f);
    data.cornerDivisions = cornerDivisions;
    data.cornerVertices = data.cornerDivisions + 2;
    data.positionPerIndex = data.cornerRadius / (float)(data.cornerVertices - 1);

    // create vertices
    {
        int ring = data.cornerVertices * 8 - 4;
        int around = ring * (data.cornerVertices * 2);
        int rowVertices = (data.cornerVertices * 2) - 2;
        int planeVertices = rowVertices * rowVertices;
        int totalVertices = 2 * planeVertices + around;
        data.positions.resize(totalVertices);
        data.normals.resize(totalVertices);

        int v = 0;
        for (int y = 0; y < data.cornerVertices; y++)
        {
            roundedCubeAddRow(
                &data,
                &v,
                (float)y * data.positionPerIndex);
        }
        for (int y = 0; y < data.cornerVertices; y++)
        {
            roundedCubeAddRow(
                &data,
                &v,
                size.y - data.cornerRadius + (float)y * data.positionPerIndex);
        }

        roundedCubeAddHorizontalPlane(&data, &v, data.size.y);
        roundedCubeAddHorizontalPlane(&data, &v, 0);
    }

    // create indices
    {
        int quadsPerCornerOneAxis = data.cornerDivisions + 1;
        int quadsPerRowOneFace = quadsPerCornerOneAxis * 2 + 1;
        int quadsPerFace = quadsPerRowOneFace * quadsPerRowOneFace;

        int quads = quadsPerFace * 6;
        data.indices.resize(quads * 6);

        int ring = data.cornerVertices * 8 - 4;
        int t = 0, v = 0;

        // Do the sides of the cube
        for (int y = 0; y < quadsPerRowOneFace; y++, v++)
        {
            for (int q = 0; q < ring - 1; q++, v++)
            {
                t = roundedCubeSetQuad(&data, t, v, v + 1, v + ring, v + ring + 1);
            }
            t = roundedCubeSetQuad(&data, t, v, v - ring + 1, v + ring, v + 1);
        }

        t = roundedCubeCreateTopFace(&data, t, ring);
        t = roundedCubeCreateBottomFace(&data, t, ring);
    }

    MeshDeinterleavedDescriptor descriptor{
        .positions = &data.positions,
        .normals = &data.normals,
        .indices = &data.indices,
        .primitiveType = MTLPrimitiveTypeTriangle
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// sphere
//-------------------------------

MeshDeinterleaved createUVSphere(id <MTLDevice> device, int horizontalDivisions, int verticalDivisions)
{
    constexpr float angleCorrectionForCenterAlign = -0.5f * pi_;

    std::vector<float3> positions;
    std::vector<float2> uv0s;
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

            positions.emplace_back(float3{x, y, z});
            uv0s.emplace_back(float2{u, v});

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

    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .uv0s = &uv0s,
        .indices = &indices,
        .primitiveType = MTLPrimitiveTypeTriangle
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// cube without uv
//-------------------------------

MeshDeinterleaved createCubeWithoutUV(id <MTLDevice> device)
{
    float s = 1.0f;
    std::vector<float3> positions{
        {-s, +s, -s},
        {-s, -s, -s},
        {+s, +s, -s},
        {+s, -s, -s},
        {-s, +s, +s},
        {-s, -s, +s},
        {+s, +s, +s},
        {+s, -s, +s},
    };

    std::vector<uint32_t> indices{
        2, 3, 0, 1, invalidMeshIndex,
        4, 5, 6, 7, invalidMeshIndex,
        4, 0, 5, 1, 7, 3, 6, 2, 4, 0,
    };

    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .indices = &indices,
        .primitiveType = MTLPrimitiveTypeTriangleStrip
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// cube
//-------------------------------

MeshDeinterleaved createCube(id <MTLDevice> device)
{
    float uvmin = 0.0f;
    float uvmax = 1.0f;
    float s = 1.0f;
    std::vector<float3> positions{
        {-s, -s, -s}, // A 0
        {+s, -s, -s}, // B 1
        {+s, +s, -s}, // C 2
        {-s, +s, -s}, // D 3
        {-s, -s, +s}, // E 4
        {+s, -s, +s}, // F 5
        {+s, +s, +s}, // G 6
        {-s, +s, +s}, // H 7
        {-s, +s, -s}, // D 8
        {-s, -s, -s}, // A 9
        {-s, -s, +s}, // E 10
        {-s, +s, +s}, // H 11
        {+s, -s, -s}, // B 12
        {+s, +s, -s}, // C 13
        {+s, +s, +s}, // G 14
        {+s, -s, +s}, // F 15
        {-s, -s, -s}, // A 16
        {+s, -s, -s}, // B 17
        {+s, -s, +s}, // F 18
        {-s, -s, +s}, // E 19
        {+s, +s, -s}, // C 20
        {-s, +s, -s}, // D 21
        {-s, +s, +s}, // H 22
        {+s, +s, +s}, // G 23
    };
    std::vector<float2> uv0s{
        {uvmin, uvmin},  // A 0
        {uvmax, uvmin},  // B 1
        {uvmax, uvmax},  // C 2
        {uvmin, uvmax},  // D 3
        {uvmin, uvmin},  // E 4
        {uvmax, uvmin},  // F 5
        {uvmax, uvmax},  // G 6
        {uvmin, uvmax},  // H 7
        {uvmin, uvmin},  // D 8
        {uvmax, uvmin},  // A 9
        {uvmax, uvmax},  // E 10
        {uvmin, uvmax},  // H 11
        {uvmin, uvmin},  // B 12
        {uvmax, uvmin},  // C 13
        {uvmax, uvmax},  // G 14
        {uvmin, uvmax},  // F 15
        {uvmin, uvmin},  // A 16
        {uvmax, uvmin},  // B 17
        {uvmax, uvmax},  // F 18
        {uvmin, uvmax},  // E 19
        {uvmin, uvmin},  // C 20
        {uvmax, uvmin},  // D 21
        {uvmax, uvmax},  // H 22
        {uvmin, uvmax},  // G 23
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

    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .uv0s = &uv0s,
        .indices = &indices,
        .primitiveType = MTLPrimitiveTypeTriangle
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// plane
//-------------------------------

MeshDeinterleaved createPlane(id <MTLDevice> device, RectMinMaxf extents)
{
    std::vector<float3> positions{
        {extents.minX, 0, extents.minY},
        {extents.minX, 0, extents.maxY},
        {extents.maxX, 0, extents.minY},
        {extents.maxX, 0, extents.maxY}
    };
    std::vector<float2> uv0s{
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 0}
    };
    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .uv0s = &uv0s,
        .primitiveType = MTLPrimitiveTypeTriangleStrip
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// tree
//-------------------------------

MeshDeinterleaved createTree(id <MTLDevice> device, float width, float height)
{
    std::vector<float3> positions{
        {-width / 2, 0, 0},
        {-width / 2, +height, 0},
        {+width / 2, 0, 0},
        {+width / 2, +height, 0},
        {0, 0, -width / 2},
        {0, +height, -width / 2},
        {0, 0, +width / 2},
        {0, +height, +width / 2},
    };
    std::vector<float2> uv0s{
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 0},
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 0}
    };
    std::vector<uint32_t> indices{
        0, 1, 2, 3, invalidMeshIndex, 4, 5, 6, 7
    };
    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .uv0s = &uv0s,
        .indices = &indices,
        .primitiveType = MTLPrimitiveTypeTriangleStrip
    };
    return createMeshDeinterleaved(device, &descriptor);
}

//-------------------------------
// terrain
//-------------------------------

void createTerrain(
    RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions,
    std::vector<float3>* outPositions, std::vector<uint32_t>* outIndices, MTLPrimitiveType* outPrimitiveType)
{
    float xSize = extents.maxX - extents.minX;
    float zSize = extents.maxY - extents.minY;
    uint32_t xCount = xSubdivisions + 1; // amount of vertices is subdivisions + 1
    uint32_t zCount = zSubdivisions + 1;

    outPositions->resize(xCount * zCount);

    float xStep = xSize / (float)xSubdivisions;
    float zStep = zSize / (float)zSubdivisions;

    for (uint32_t zIndex = 0; zIndex < zCount; zIndex++)
    {
        for (uint32_t xIndex = 0; xIndex < xCount; xIndex++)
        {
            float x = extents.minX + (float)xIndex * xStep;
            float z = extents.minY + (float)zIndex * zStep;

            float y = 0.1f * perlin(x * 8, z * 8) + 2.0f * perlin(x / 2, z / 2) + 10.0f * perlin(x / 9, z / 12);

            outPositions->at(zIndex * xCount + xIndex) = float3{x, y, z};
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
        outIndices->emplace_back(invalidMeshIndex);
    }

    *outPrimitiveType = MTLPrimitiveTypeTriangleStrip;
}

//-------------------------------
// axes
//-------------------------------

MeshDeinterleaved createAxes(id <MTLDevice> device)
{
    std::vector<uint32_t> indices;
    std::vector<uint32_t> indicesTemplate{
        0, 1, 2, 1, 3, 2
    };

    float w = 0.01f; // width
    float l = 0.75f; // length

    float4 red = {1, 0, 0, 1};
    float4 green = {0, 1, 0, 1};
    float4 blue = {0, 0, 1, 1};

    // positions
    std::vector<float3> positions{
        // x
        {l, -w, 0},
        {l, +w, 0},
        {0, -w, 0},
        {0, +w, 0},

        // y
        {-w, l, 0},
        {+w, l, 0},
        {-w, 0, 0},
        {+w, 0, 0},

        // z
        {0, -w, l},
        {0, +w, l},
        {0, -w, 0},
        {0, +w, 0}
    };
    std::vector<float4> colors{
        red, red, red, red, // x
        green, green, green, green, // y
        blue, blue, blue, blue // z
    };

    for (int i = 0; i <= 2; i++)
    {
        // indices
        for (auto& index: indicesTemplate)
        {
            indices.emplace_back(index + 4 * i);
        }
    }

    MeshDeinterleavedDescriptor descriptor{
        .positions = &positions,
        .colors = &colors,
        .indices = &indices,
        .primitiveType = MTLPrimitiveTypeTriangle
    };
    return createMeshDeinterleaved(device, &descriptor);
}
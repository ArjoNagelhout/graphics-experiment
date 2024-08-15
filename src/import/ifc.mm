//
// Created by Arjo Nagelhout on 11/08/2024.
//

#include "ifc.h"

#include <ifcgeom/Iterator.h>
#include <ifcgeom/ConversionSettings.h>
#include <ifcparse/IfcFile.h>

#include "glm/gtc/type_ptr.hpp"

bool importIfc(id <MTLDevice> device, std::filesystem::path const& path, IfcModel* outModel, IfcImportSettings settings)
{
    assert(exists(path));
    assert(outModel != nullptr);

    IfcParse::IfcFile ifcFile(path);
    if (!ifcFile.good())
    {
        switch (ifcFile.good().value())
        {
            //@formatter:off
            case IfcParse::file_open_status::READ_ERROR:std::cout << "ifc parse error: read error" << std::endl;break;
            case IfcParse::file_open_status::NO_HEADER:std::cout << "ifc parse error: no header" << std::endl;break;
            case IfcParse::file_open_status::UNSUPPORTED_SCHEMA:std::cout << "ifc parse error: unsupported schema" << std::endl;break;
            default:break;
            //@formatter:on
        }
    }
    assert(ifcFile.good() && "parsing failed");

    ifcopenshell::geometry::Settings geometrySettings;
    geometrySettings.get<ifcopenshell::geometry::UseWorldCoords>().value = false;
    geometrySettings.get<ifcopenshell::geometry::WeldVertices>().value = false;
    geometrySettings.get<ifcopenshell::geometry::ApplyDefaultMaterials>().value = false;
    geometrySettings.get<ifcopenshell::geometry::IteratorOutput>().value = ifcopenshell::geometry::IteratorOutputOptions::TRIANGULATED; // NATIVE = BRep
    IfcGeom::Iterator iterator{geometrySettings, &ifcFile};
    bool result = iterator.initialize();
    assert(result && "initializing iterator failed");

    do
    {
        IfcGeom::Element* element = iterator.get();
        auto const* triangulationElement = dynamic_cast<IfcGeom::TriangulationElement const*>(element);
        IfcGeom::Representation::Triangulation const& triangulation = triangulationElement->geometry();

        size_t meshIndex = invalidIndex;

        // create mesh
        {
            IfcMesh* outMesh = &outModel->meshes.emplace_back();
            meshIndex = outModel->meshes.size() - 1;

            // positions
            std::vector<double> const& verticesIn = triangulation.verts();
            assert(!verticesIn.empty());
            assert(verticesIn.size() % 3 == 0);
            size_t vertexCount = verticesIn.size() / 3;
            std::vector<float3> positionsOut(vertexCount);
            for (size_t i = 0; i < vertexCount; i++)
            {
                positionsOut[i] = float3{
                    static_cast<float>(verticesIn[i * 3]),
                    static_cast<float>(verticesIn[i * 3 + (settings.flipYAndZAxes ? 2 : 1)]),
                    static_cast<float>(verticesIn[i * 3 + (settings.flipYAndZAxes ? 1 : 2)])
                };
            }

            // normals
            std::vector<double> const& normalsIn = triangulation.normals();
            assert(normalsIn.size() == verticesIn.size());
            std::vector<float3> normalsOut(vertexCount);

            for (size_t i = 0; i < vertexCount; i++)
            {
                normalsOut[i] = float3{
                    static_cast<float>(normalsIn[i * 3]),
                    static_cast<float>(normalsIn[i * 3 + (settings.flipYAndZAxes ? 2 : 1)]),
                    static_cast<float>(normalsIn[i * 3 + (settings.flipYAndZAxes ? 1 : 2)])
                };
            }

            // indices
            std::vector<int> const& indicesIn = triangulation.faces();
            size_t indexCount = indicesIn.size();
            assert(indexCount % 3 == 0);
            std::vector<uint32_t> indicesOut(indexCount);
            if (settings.flipYAndZAxes)
            {
                // invert winding order
                size_t triangleCount = indexCount / 3;
                for (size_t i = 0; i < triangleCount; i++)
                {
                    indicesOut[i * 3 + 0] = indicesIn[i * 3 + 2];
                    indicesOut[i * 3 + 1] = indicesIn[i * 3 + 1];
                    indicesOut[i * 3 + 2] = indicesIn[i * 3 + 0];
                }
            }
            else
            {
                for (size_t i = 0; i < indexCount; i++)
                {
                    indicesOut[i] = static_cast<uint32_t>(indicesIn[i]);
                }
            }

            // create primitive
            // todo: split primitives on material
            PrimitiveDeinterleavedDescriptor descriptor{
                .positions = &positionsOut,
                .normals = &normalsOut,
                .indices = &indicesOut,
                .primitiveType = MTLPrimitiveTypeTriangle,
            };
            outMesh->primitive = createPrimitiveDeinterleaved(device, &descriptor);
        }

        // create node
        {
            IfcNode* outNode = &outModel->nodes.emplace_back();

            // get transform
            ifcopenshell::geometry::taxonomy::matrix4::ptr const& transform = triangulationElement->transformation().data();
            Eigen::Matrix<double, 4, 4>& m = transform->components();
            glm::mat4 outMatrix;
            for (int i = 0; i < 4 * 4; i++)
            {
                auto a = static_cast<float>(m(i));
                outMatrix[i / 4][i % 4] = a;
            }

            if (settings.flipYAndZAxes)
            {
                glm::mat4 flipMatrix = glm::mat4{
                    1, 0, 0, 0,
                    0, 0, 1, 0,
                    0, 1, 0, 0,
                    0, 0, 0, 1
                };
                outMatrix = flipMatrix * outMatrix * flipMatrix;
            }
            outNode->localTransform = outMatrix;

            assert(meshIndex != invalidIndex);
            outNode->meshIndex = meshIndex;
        }

        std::cout << "ifc: imported triangulation for " << element->name() << std::endl;
    }
    while (iterator.next());

    // create scene
    size_t sceneIndex = invalidIndex;
    {
        outModel->scenes.emplace_back();
        sceneIndex = outModel->scenes.size() - 1;
    }

    // create root node
    {
        assert(sceneIndex != invalidIndex);
        IfcScene* scene = &outModel->scenes[sceneIndex];

        std::vector<size_t> nodeIndices(outModel->nodes.size());
        std::iota(nodeIndices.begin(), nodeIndices.end(), 0);

        // create the root node
        // this makes iterating easier using a tree-traversal algorithm
        outModel->nodes.emplace_back(IfcNode{
            .meshIndex = invalidIndex,
            .localTransform = glm::mat4(1),
            .childNodes = nodeIndices
        });
        scene->rootNode = outModel->nodes.size() - 1;
    }

    return true;
}
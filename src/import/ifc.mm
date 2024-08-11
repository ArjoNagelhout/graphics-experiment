//
// Created by Arjo Nagelhout on 11/08/2024.
//

#include "ifc.h"

#include <ifcgeom/Iterator.h>
#include <ifcgeom/ConversionSettings.h>
#include <ifcparse/IfcFile.h>

bool importIfc(id <MTLDevice> device, std::filesystem::path const& path, IfcModel* outModel)
{
    assert(exists(path));
    assert(outModel != nullptr);

    IfcParse::IfcFile ifcFile(path);
    if (!ifcFile.good())
    {
        switch (ifcFile.good().value())
        {
            case IfcParse::file_open_status::READ_ERROR:std::cout << "ifc parse error: read error" << std::endl;
                break;
            case IfcParse::file_open_status::NO_HEADER:std::cout << "ifc parse error: no header" << std::endl;
                break;
            case IfcParse::file_open_status::UNSUPPORTED_SCHEMA:std::cout << "ifc parse error: unsupported schema" << std::endl;
                break;
            default:break;
        }
    }
    assert(ifcFile.good() && "parsing failed");

    ifcopenshell::geometry::Settings settings;
    settings.get<ifcopenshell::geometry::UseWorldCoords>().value = false;
    settings.get<ifcopenshell::geometry::WeldVertices>().value = false;
    settings.get<ifcopenshell::geometry::ApplyDefaultMaterials>().value = false;
    settings.get<ifcopenshell::geometry::IteratorOutput>().value = ifcopenshell::geometry::IteratorOutputOptions::TRIANGULATED; // NATIVE = BRep
    IfcGeom::Iterator iterator{settings, &ifcFile};
    bool result = iterator.initialize();
    assert(result && "initializing iterator failed");

    do
    {
        IfcGeom::Element* element = iterator.get();
        auto const* triangulationElement = dynamic_cast<IfcGeom::TriangulationElement const*>(element);
        IfcGeom::Representation::Triangulation const& triangulation = triangulationElement->geometry();

        // for brep:
        //IfcGeom::BRepElement const* bRepElement = static_cast<IfcGeom::BRepElement const*>(element);
        //IfcGeom::Representation::BRep const& bRep = bRepElement->geometry();

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
                static_cast<float>(verticesIn[i * 3 + 1]),
                static_cast<float>(verticesIn[i * 3 + 2])
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
                static_cast<float>(normalsIn[i * 3 + 1]),
                static_cast<float>(normalsIn[i * 3 + 2])
            };
        }

        // indices
        std::vector<int> const& indicesIn = triangulation.faces();
        size_t indexCount = indicesIn.size();
        std::vector<uint32_t> indicesOut(indexCount);
        for (size_t i = 0; i < indexCount; i++)
        {
            indicesOut[i] = static_cast<uint32_t>(indicesIn[i]);
        }

        PrimitiveDeinterleavedDescriptor descriptor{
            .positions = &positionsOut,
            .normals = &normalsOut,
            .indices = &indicesOut,
            .primitiveType = MTLPrimitiveTypeTriangle,
        };
        outModel->meshes.emplace_back(createPrimitiveDeinterleaved(device, &descriptor));

        std::cout << element->name() << std::endl;
    }
    while (iterator.next());

    return true;
}
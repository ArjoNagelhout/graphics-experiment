#include <iostream>

#include <ifcgeom/Iterator.h>
#include <ifcgeom/ConversionSettings.h>
#include <ifcparse/IfcFile.h>
#include <filesystem>

// definitions for globals declared in test_args.h
std::filesystem::path assetsPath;
std::filesystem::path privateAssetsPath;

int main(int argc, char** argv)
{
    assert(argc == 3);
    for (int i = 1; i < argc; ++i)
    {
        printf("arg %2d = %s\n", i, argv[i]);
    }
    assetsPath = argv[1];
    privateAssetsPath = argv[2];

    std::filesystem::path path = assetsPath / "ifc" / "AC20-FZK-Haus.ifc";
    IfcParse::IfcFile ifcFile(path);
    assert(ifcFile.good() && "parsing failed");

    ifcopenshell::geometry::Settings settings;
    settings.get<ifcopenshell::geometry::UseWorldCoords>().value = false;
    settings.get<ifcopenshell::geometry::WeldVertices>().value = false;
    settings.get<ifcopenshell::geometry::ApplyDefaultMaterials>().value = false;
    IfcGeom::Iterator iterator{settings, &ifcFile};
    bool result = iterator.initialize();
    assert(result && "initializing iterator failed");

    do
    {
        IfcGeom::Element* element = iterator.get();
        IfcGeom::TriangulationElement const* triangulationElement = static_cast<IfcGeom::TriangulationElement const*>(element);
        IfcGeom::Representation::Triangulation const& triangulation = triangulationElement->geometry();

        std::cout << element->name() << std::endl;
    }
    while (iterator.next());

    std::cout << "hello world" << std::endl;
}
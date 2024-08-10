#include <iostream>

#include <ifcgeom/ConversionSettings.h>
#include "ifcparse/IfcFile.h"

int main(int argc, char** argv)
{
    ifcopenshell::geometry::Settings settings;
    void* data = nullptr;
    int length = 10;
    IfcParse::IfcFile ifcFile(data, length);

    std::cout << "hello world" << std::endl;
}
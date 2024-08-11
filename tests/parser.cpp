//
// Created by Arjo Nagelhout on 11/08/2024.
//

#include <iostream>
#include <filesystem>
#include <cassert>

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

    // parsing:
    // 1. source file
    // 2. tokenizing (lexer / lexical analysis / lexical tokenization)
    // 3. parsing (to create AST?)

    // IFC is a text-based file format
    // its types / classes are defined in the EXPRESS definition language

    // what do we want to do with the IFC data?
    // look into ifcOpenShell's APIs
    // from the top of my head:
    // - inspecting properties / hierarchy of BIM information
    // - converting into geometry

    // IFC has multiple versions, which might contain additional types / classes
    // but each IFC file has the same layout and syntax. only its types change

    // do we want to represent this IFC data format in special C++ classes?
    // probably not.

    // first let's tokenize the main IFC file
    // IFC uses STEP file format (ISO 10303)

}
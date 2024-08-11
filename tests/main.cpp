//
// Created by Arjo Nagelhout on 09/07/2024.
//

// to add the assets directory as a program argument

#include "gtest/gtest.h"

#include "test_args.h"

// definitions for globals declared in test_args.h
std::filesystem::path assetsPath;
std::filesystem::path privateAssetsPath;

int main(int argc, char** argv)
{
    ::testing::InitGoogleTest(&argc, argv);

    assert(argc == 3);
    for (int i = 1; i < argc; ++i)
    {
        printf("arg %2d = %s\n", i, argv[i]);
    }
    assetsPath = argv[1];
    privateAssetsPath = argv[2];

    return RUN_ALL_TESTS();
}
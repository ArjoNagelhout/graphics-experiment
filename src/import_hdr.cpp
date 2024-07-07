#include "radiance.h"

#include <cassert>
#include <iostream>

int main(int argc, char const* argv[])
{
    assert(argc == 2); // we expect one additional argument: the assets folder
    std::filesystem::path assets_folder = argv[1];
    assert(exists(assets_folder) && is_directory(assets_folder));

    std::filesystem::path hdr = assets_folder / "skybox_test.hdr";

    assert(exists(hdr));
    assert(hdr.extension() == ".hdr");
    radiance::picture picture{};
    radiance::import_result result = radiance::import_picture(hdr, &picture);
    std::cout << to_string(result) << '\n';
    std::cout.flush();
}
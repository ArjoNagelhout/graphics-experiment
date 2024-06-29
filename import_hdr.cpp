#include <cassert>
#include <filesystem>
#include <iostream>
#include <fstream>

// https://paulbourke.net/dataformats/pic/
// https://radsite.lbl.gov/radiance/refer/filefmts.pdf (page 28)
// https://github.com/LBNL-ETA/Radiance/tree/master

using char_traits = std::char_traits<char>;
using int_type = char_traits::int_type;

void importHDR(std::filesystem::path const& path)
{
    assert(exists(path));
    assert(path.extension() == ".hdr");

    std::basic_ifstream<char> file(path);

    int_type a;
    while ((a = file.get()) != char_traits::eof())
    {
        char b = char_traits::to_char_type(a);
        std::cout << b;
    }
    std::cout << std::endl;

    // import hdr (radiance)
    {
        // 1. information header
        // Line 1: $?RADIANCE
        // Next lines are variables:
        // FORMAT=
        // EXPOSURE=
        // COLORCORR=
        // SOFTWARE=
        // PIXASPECT=
        // VIEW=
        // PRIMARIES=

        // 2. resolution string


        // 3. scanline records (three types:)
        //

    }

    std::cout << "imported hdr" << std::endl;
}

int main(int argc, char const* argv[])
{
    assert(argc == 2); // we expect one additional argument: the assets folder
    std::filesystem::path assetsFolder = argv[1];
    assert(exists(assetsFolder) && is_directory(assetsFolder));

    std::filesystem::path hdr = assetsFolder / "skybox.hdr";

    importHDR(hdr);
}
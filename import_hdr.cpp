#include <cassert>
#include <filesystem>
#include <iostream>
#include <fstream>

// https://paulbourke.net/dataformats/pic/
// https://radsite.lbl.gov/radiance/refer/filefmts.pdf (page 28)
// https://github.com/LBNL-ETA/Radiance/tree/master

using char_traits = std::char_traits<char>;
using int_type = char_traits::int_type;

struct HDRData
{
    uint32_t width;
    uint32_t height;
};

void importHDR(std::filesystem::path const& path)
{
    assert(exists(path));
    assert(path.extension() == ".hdr");

    std::basic_ifstream<char> file(path);

    // read one char at a time, until we hit the end of the file
    //int_type a;
//    while ((a = file.get()) != char_traits::eof())
//    {
//        char b = char_traits::to_char_type(a);
//        //std::cout << b;
//    }


    std::string line;
    std::getline(file, line);
    assert(line == "#?RADIANCE"); // first line

    // read information header until the resolution string
    bool foundResolutionString = false;
    while (!foundResolutionString)
    {
        std::getline(file, line);
        if (line.empty())
        {
            continue;
        }
        if (line.length() > 2
            && (line[0] == '-' || line[0] == '+')
            && (line[1] == 'X' || line[1] == 'Y'))
        {
            std::cout << "resolution string: \n";
            foundResolutionString = true;
        }

        std::cout << line << '\n';
    }
    std::cout.flush();

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
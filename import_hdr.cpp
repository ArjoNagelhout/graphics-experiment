#include <cassert>
#include <filesystem>
#include <iostream>
#include <fstream>
#include <cstdlib>

// https://paulbourke.net/dataformats/pic/
// https://radsite.lbl.gov/radiance/refer/filefmts.pdf (page 28)
// https://github.com/LBNL-ETA/Radiance/tree/master

using char_traits = std::char_traits<char>;
using int_type = char_traits::int_type;

enum class radiance_memory_layout
{
    row_major = 0,
    column_major
};

enum class radiance_format
{
    rgbe = 0,
    xyze
};

// hdr
struct radiance_picture
{
    uint32_t width; // X
    uint32_t height; // Y
    radiance_format format;
    radiance_memory_layout memory_layout;
    bool x_flipped;
    bool y_flipped;
    float exposure; // multiplied all exposure occurrences in header
};

enum class radiance_picture_result
{
    success = 0,
    error = 1,
    error_invalid_format = 2,
    error_invalid_exposure = 3
};

[[nodiscard]] radiance_picture_result import_radiance_picture(
    std::filesystem::path const& path,
    radiance_picture* out)
{
    std::basic_ifstream<char> file(path);
    std::string line;
    std::getline(file, line);
    assert(line == "#?RADIANCE"); // always first line

    out->exposure = 1.0f;

    // read information header until empty line (marks end of header)
    while ((std::getline(file, line) && !line.empty()))
    {
        // iterator at index of '=' character
        auto equal_it = std::find(line.begin(), line.end(), '=');
        assert(equal_it != line.end());
        for (auto it = line.begin(); it != equal_it; it++)
        {
            *it = (char)toupper(*it); // make uppercase
        }

        std::string_view value(equal_it + 1, line.end()); // skip the '=' character
        if (line.starts_with("FORMAT"))
        {
            if (value == "32-bit_rle_rgbe")
            {
                out->format = radiance_format::rgbe;
            }
            else if (value == "32-bit_rle_xyze")
            {
                out->format = radiance_format::xyze;
            }
            else
            {
                return radiance_picture_result::error_invalid_format;
            }
        }
        else if (line.starts_with("EXPOSURE"))
        {
            // exposure is cumulative (can be present multiple times in the header)
            // to get original pixel values, value in file must be divided by
            // all exposures multiplied together.

            // parse value
            char* end;
            float v = strtof(value.data(), &end);
            if (end != value.data() + value.size())
            {
                return radiance_picture_result::error_invalid_exposure;
            }
            out->exposure *= v;
        }
        else if (line.starts_with("COLORCORR"))
        {
            
        }
        else if (line.starts_with("PRIMARIES"))
        {

        }
        // other variables are not relevant

        //else if (line.)
        std::cout << line << '\n';
    }

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

    return radiance_picture_result::success;
}

int main(int argc, char const* argv[])
{
    assert(argc == 2); // we expect one additional argument: the assets folder
    std::filesystem::path assets_folder = argv[1];
    assert(exists(assets_folder) && is_directory(assets_folder));

    std::filesystem::path hdr = assets_folder / "skybox_test.hdr";

    assert(exists(hdr));
    assert(hdr.extension() == ".hdr");
    radiance_picture picture{};
    radiance_picture_result result = import_radiance_picture(hdr, &picture);
    std::cout << "imported hdr\n";

    std::cout.flush();
}
//
// Created by Arjo Nagelhout on 30/06/2024.
//

#include "radiance.h"

#include <fstream>
#include <cassert>
#include <iostream>

namespace radiance
{
    std::string_view to_string(import_result result)
    {
        switch (result)
        {
            case import_result::success: return "success";
            case import_result::error: return "error";
            case import_result::error_invalid_format: return "invalid format";
            case import_result::error_invalid_exposure: return "invalid exposure";
        }
    }

    import_result import_picture(
        std::filesystem::path const& path,
        picture* out)
    {
        std::basic_ifstream<char> file(path);
        std::string line;
        std::getline(file, line);
        assert(line == "#?RADIANCE"); // always first line

        // 1. read information header until empty line (marks end of header)
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
                    out->format = format::format_32_bit_rle_rgbe;
                }
                else if (value == "32-bit_rle_xyze")
                {
                    out->format = format::format_32_bit_rle_xyze;
                }
                else
                {
                    return import_result::error_invalid_format;
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
                    return import_result::error_invalid_exposure;
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
        }

        // 2. read resolution string


        return import_result::success;
    }
}
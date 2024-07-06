//
// Created by Arjo Nagelhout on 30/06/2024.
//

#ifndef BORED_C_RADIANCE_H
#define BORED_C_RADIANCE_H

#include <filesystem>

// reference:
// https://radsite.lbl.gov/radiance/refer/filefmts.pdf (page 28)
// https://radsite.lbl.gov/radiance/refer/Notes/picture_format.html
// https://github.com/LBNL-ETA/Radiance/tree/master

namespace radiance
{
    // constants

    struct color
    {
        unsigned char red;
        unsigned char green;
        unsigned char blue;
        unsigned char exponent;
    };

    enum class memory_layout
    {
        row_major = 0, // scanlines along X axis
        column_major // scanlines along Y axis
    };

    enum class format
    {
        format_32_bit_rle_rgbe = 0,
        format_32_bit_rle_xyze
    };

    struct picture
    {
        uint32_t width = 0; // X
        uint32_t height = 0; // Y
        format format = format::format_32_bit_rle_rgbe;
        memory_layout memory_layout = memory_layout::column_major;
        bool x_positive = true; // +X is default
        bool y_positive = false; // -Y is default
        float exposure = 1.0f; // result of multiplying all exposure occurrences in header
        color color_correction;
    };

    enum class import_result
    {
        success = 0,
        error = 1,
        error_invalid_format = 2,
        error_invalid_exposure = 3
    };

    [[nodiscard]] import_result import_picture(std::filesystem::path const& path, picture* out);

    [[nodiscard]] std::string_view to_string(import_result result);
}

#endif //BORED_C_RADIANCE_H

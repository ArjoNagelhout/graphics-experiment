//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef BORED_C_RECT_H
#define BORED_C_RECT_H

#include <cstdint>

// a rect defined by min and max coordinates
struct RectMinMaxf
{
    float minX;
    float minY;
    float maxX;
    float maxY;
};

struct RectMinMaxi
{
    uint32_t minX;
    uint32_t minY;
    uint32_t maxX;
    uint32_t maxY;
};

#endif //BORED_C_RECT_H

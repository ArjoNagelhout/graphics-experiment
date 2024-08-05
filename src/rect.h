//
// Created by Arjo Nagelhout on 07/07/2024.
//

#ifndef METAL_EXPERIMENT_RECT_H
#define METAL_EXPERIMENT_RECT_H

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

#endif //METAL_EXPERIMENT_RECT_H

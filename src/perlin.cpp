//
// Created by Arjo Nagelhout on 07/07/2024.
//

#include "simd/simd.h"

// perlin noise
// https://en.wikipedia.org/wiki/Perlin_noise

// Function to linearly interpolate between a0 and a1
// Weight w should be in the range [0.0, 1.0]
[[nodiscard]] float perlinInterpolate(float a0, float a1, float w)
{
    // clamp
    if (0.0f > w)
    { return a0; }
    if (1.0f < w)
    { return a1; }

    // Use Smootherstep for an even smoother result with a second derivative equal to zero on boundaries:
    return (a1 - a0) * ((w * (w * 6.0f - 15.0f) + 10.0f) * w * w * w) + a0;
}

// Create pseudorandom direction vector
[[nodiscard]] simd_float2 perlinRandomGradient(int ix, int iy)
{
    // No precomputed gradients mean this works for any number of grid coordinates
    const unsigned w = 8 * sizeof(unsigned);
    const unsigned s = w / 2; // rotation width
    unsigned a = ix, b = iy;
    a *= 3284157443;
    b ^= a << s | a >> (w - s);
    b *= 1911520717;
    a ^= b << s | b >> (w - s);
    a *= 2048419325;
    float random = (float)a * (3.14159265f / (float)~(~0u >> 1)); // in [0, 2*Pi]
    return simd_float2{cos(random), sin(random)};
}

// Computes the dot product of the distance and gradient vectors.
[[nodiscard]] float perlinDotGridGradient(int ix, int iy, float x, float y)
{
    // Get gradient from integer coordinates
    simd_float2 gradient = perlinRandomGradient(ix, iy);

    // Compute the distance vector
    float dx = x - (float)ix;
    float dy = y - (float)iy;

    // Compute the dot-product
    return (dx * gradient.x + dy * gradient.y);
}

// Compute Perlin noise at coordinates x, y
[[nodiscard]] float perlin(float x, float y)
{
    // Determine grid cell coordinates
    int x0 = (int)floor(x);
    int x1 = x0 + 1;
    int y0 = (int)floor(y);
    int y1 = y0 + 1;

    // Determine interpolation weights
    // Could also use higher order polynomial/s-curve here
    float sx = x - (float)x0;
    float sy = y - (float)y0;

    // Interpolate between grid point gradients
    float n0, n1, ix0, ix1, value;

    n0 = perlinDotGridGradient(x0, y0, x, y);
    n1 = perlinDotGridGradient(x1, y0, x, y);
    ix0 = perlinInterpolate(n0, n1, sx);

    n0 = perlinDotGridGradient(x0, y1, x, y);
    n1 = perlinDotGridGradient(x1, y1, x, y);
    ix1 = perlinInterpolate(n0, n1, sx);

    value = perlinInterpolate(ix0, ix1, sy);
    return value; // Will return in range -1 to 1. To make it in range 0 to 1, multiply by 0.5 and add 0.5
}
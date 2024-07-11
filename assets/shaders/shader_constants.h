#ifndef BORED_C_SHADER_CONSTANTS_H
#define BORED_C_SHADER_CONSTANTS_H

// used by both shader code and the main codebase

#ifdef SHADER_CONSTANTS_MAIN
// for in the main codebase
#define CONST_ID static constexpr
#else
// for inside shader
#define CONST_ID constant
#endif

namespace bindings
{
    // shader bindings
    CONST_ID int cameraData = 0;
    CONST_ID int instanceData = 1;

    // interleaved data
    CONST_ID int vertexData = 2;

    // non interleaved (partially non-interleaved is probably best)
    CONST_ID int positions = 2;
    CONST_ID int normals = 3;
    CONST_ID int uv0s = 4;
    CONST_ID int colors = 5;
    CONST_ID int lightMapUvs = 6;
}

#endif //BORED_C_SHADER_CONSTANTS_H

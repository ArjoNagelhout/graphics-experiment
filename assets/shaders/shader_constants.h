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
    // vertex bindings

    // shader bindings
    CONST_ID int cameraData = 0;
    CONST_ID int instanceData = 1;

    // interleaved data
    CONST_ID int vertexData = 2;

    // non interleaved (partially non-interleaved is probably best)
    // that would mean keeping the position buffer separate
    // but the normals, uv0s etc. in the same buffer when they're always used
    // in the same shader
    // keeping the position buffer separate is useful for for example rendering the
    // shadows
    // maybe the uv0 is also required when alpha testing is enabled for a shader.
    CONST_ID int positions = 2;
    CONST_ID int normals = 3;
    CONST_ID int uv0s = 4;
    CONST_ID int colors = 5;
    CONST_ID int lightMapUvs = 6;
    CONST_ID int tangents = 7;

    // fragment bindings
    CONST_ID int textureNormal = 0;
    CONST_ID int textureBaseColor = 1;
    CONST_ID int textureMetallic = 2;
    CONST_ID int textureRoughness = 3;
}

#endif //BORED_C_SHADER_CONSTANTS_H

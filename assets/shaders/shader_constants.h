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
    CONST_ID int cameraData = 0;
    CONST_ID int instanceData = 1;
    CONST_ID int lightData = 2;
    CONST_ID int globalVertexData = 3; // same for each vertex

    // interleaved data
    CONST_ID int vertexData = 4;

    // non interleaved (partially non-interleaved is probably best)
    // that would mean keeping the position buffer separate
    // but the normals, uv0s etc. in the same buffer when they're always used
    // in the same shader
    // keeping the position buffer separate is useful for for example rendering the
    // shadows
    // maybe the uv0 is also required when alpha testing is enabled for a shader.
    CONST_ID int positions = 4;
    CONST_ID int normals = 5;
    CONST_ID int uv0s = 6;
    CONST_ID int colors = 7;
    CONST_ID int lightMapUvs = 8;
    CONST_ID int tangents = 9;

    // fragment bindings
    CONST_ID int globalFragmentData = 0; // same for each fragment

    CONST_ID int texture = 1;
    CONST_ID int shadowMap = 2;
    CONST_ID int reflectionMap = 3; // skybox or reflection probe
}

#endif //BORED_C_SHADER_CONSTANTS_H

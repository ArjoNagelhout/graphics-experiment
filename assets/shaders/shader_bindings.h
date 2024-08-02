#ifndef BORED_C_SHADER_BINDINGS_H
#define BORED_C_SHADER_BINDINGS_H

// used by both shader code and the main codebase

#ifdef SHADER_BINDINGS_MAIN
// for in the main codebase
#define BINDING static constexpr
#else
// for inside shader
#define BINDING constant
#endif

namespace bindings
{
    BINDING int cameraData = 0;
    BINDING int instanceData = 1;
    BINDING int lightData = 2;
    BINDING int globalVertexData = 3; // same for each vertex

    // interleaved data
    BINDING int vertexData = 4;

    // non interleaved (partially non-interleaved is probably best)
    // that would mean keeping the position buffer separate
    // but the normals, uv0s etc. in the same buffer when they're always used
    // in the same shader
    // keeping the position buffer separate is useful for for example rendering the
    // shadows
    // maybe the uv0 is also required when alpha testing is enabled for a shader.
    BINDING int positions = 4;
    BINDING int normals = 5;
    BINDING int uv0s = 6;
    BINDING int colors = 7;
    BINDING int lightMapUvs = 8;
    BINDING int tangents = 9;

    // fragment bindings
    BINDING int globalFragmentData = 0; // same for each fragment

    BINDING int texture = 1;
    BINDING int shadowMap = 2;
    BINDING int reflectionMap = 3; // skybox or reflection probe
    BINDING int prefilteredEnvironmentMap = 4;
    BINDING int brdfLookupTexture = 5;
    BINDING int irradianceMap = 6;
}

#endif //BORED_C_SHADER_BINDINGS_H

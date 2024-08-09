cmake_minimum_required(VERSION 3.26)
project(metal_experiment)

set(CMAKE_CXX_STANDARD 20)

add_subdirectory(external)
add_subdirectory(tests)

set(SOURCES
        src/perlin.h
        src/perlin.cpp
        src/rect.h
        src/mesh.h
        src/mesh.mm
        src/procedural_mesh.h
        src/procedural_mesh.mm
        src/gltf.h
        src/gltf.mm
)

add_library(metal_experiment_lib ${SOURCES})
target_link_libraries(metal_experiment_lib PUBLIC lodepng glm fmt cgltf libjpeg-turbo ifcopenshell)
target_include_directories(metal_experiment_lib PUBLIC src)
target_include_directories(metal_experiment_lib PUBLIC assets/shaders)

target_link_libraries(metal_experiment_lib PUBLIC
        "-framework Cocoa"
        "-framework Foundation"
        "-framework AppKit"
        "-framework Metal"
        "-framework MetalKit"
)

add_executable(metal_experiment src/main.mm)

target_link_libraries(metal_experiment metal_experiment_lib)
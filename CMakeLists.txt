cmake_minimum_required(VERSION 3.28)
project(metal_experiment)

set(CMAKE_CXX_STANDARD 23)

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
        src/import/gltf.h
        src/import/gltf.mm
        src/import/ifc.h
        src/import/ifc.mm
)

add_library(metal_experiment_lib ${SOURCES})
target_link_libraries(metal_experiment_lib PUBLIC lodepng glm fmt cgltf libjpeg-turbo ifcopenshell imgui)
target_include_directories(metal_experiment_lib PUBLIC src)
target_include_directories(metal_experiment_lib PUBLIC assets/shaders)

target_link_libraries(metal_experiment_lib PUBLIC
        "-framework Cocoa"
        "-framework Foundation"
        "-framework AppKit"
        "-framework Metal"
        "-framework MetalKit"
)

target_link_libraries(imgui PUBLIC "-framework GameController")

add_executable(metal_experiment src/main.mm)

target_link_libraries(metal_experiment metal_experiment_lib)
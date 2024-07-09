cmake_minimum_required(VERSION 3.26)
project(bored_c)

set(CMAKE_CXX_STANDARD 20)

add_subdirectory(external)
add_subdirectory(lib)
add_subdirectory(tests)

set(SOURCES
        src/main.mm
        src/perlin.h
        src/perlin.cpp
        src/rect.h
        src/mesh.h
        src/mesh.mm
        src/procedural_mesh.h
        src/procedural_mesh.mm
        src/gltf.h
        src/gltf.cpp
)

add_executable(bored_c ${SOURCES})
target_link_libraries(bored_c lodepng glm fmt radiance tinygltf)

set_source_files_properties(src/main.mm PROPERTIES
        COMPILE_FLAGS "-x objective-c++")

target_link_libraries(bored_c
        "-framework Cocoa"
        "-framework Foundation"
        "-framework AppKit"
        "-framework Metal"
        "-framework MetalKit"
)

# experiments

set(IMPORT_HDR_SOURCES
        src/import_hdr.cpp
)

add_executable(import_hdr ${IMPORT_HDR_SOURCES})

target_link_libraries(import_hdr radiance)
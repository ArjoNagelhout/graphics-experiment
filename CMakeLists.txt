cmake_minimum_required(VERSION 3.26)
project(bored_c)

set(CMAKE_CXX_STANDARD 17)

add_subdirectory(external)

set(SOURCES
        main.mm
)

add_executable(bored_c ${SOURCES})
target_link_libraries(bored_c lodepng glm fmt)

set_source_files_properties(main.mm PROPERTIES
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
    import_hdr.cpp
)

add_executable(import_hdr ${IMPORT_HDR_SOURCES})
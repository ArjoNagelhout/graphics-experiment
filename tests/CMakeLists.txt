add_subdirectory(external/googletest)

set(TESTS_SOURCES
        main.cpp
        websockets.cpp
        gltf.mm
        json.cpp
        tests.cpp
)

add_executable(tests ${TESTS_SOURCES})

target_link_libraries(tests gtest metal_experiment_lib)

set_source_files_properties(main.cpp PROPERTIES
        COMPILE_FLAGS "-x objective-c++")

# ifc experiment
set(IFC_SOURCES
        ifc.cpp
)

add_executable(ifc ${IFC_SOURCES})
target_link_libraries(ifc PUBLIC ifcopenshell)

# parser experiment
set(PARSER_SOURCES
        parser.cpp
)

add_executable(parser ${PARSER_SOURCES})

# sdl window experiment
set(SDL_EXPERIMENT_SOURCES
        sdl.mm
)

add_executable(sdl_experiment ${SDL_EXPERIMENT_SOURCES})
target_link_libraries(sdl_experiment PRIVATE SDL3::SDL3)

# molten vk experiment
set(MOLTENVK_EXPERIMENT_SOURCES
        molten_vk.cpp
)

add_executable(moltenvk_experiment ${MOLTENVK_EXPERIMENT_SOURCES})
target_link_libraries(moltenvk_experiment PUBLIC moltenvk)
target_link_libraries(moltenvk_experiment PUBLIC
        "-framework Cocoa"
        "-framework Foundation"
        "-framework Metal"
        "-framework IOKit"
        "-framework IOSurface"
        "-framework QuartzCore"
)
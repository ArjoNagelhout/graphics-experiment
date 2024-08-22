add_subdirectory(external/googletest)

set(TESTS_SOURCES
        main.cpp
        gltf.mm
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
set(VULKAN_EXPERIMENT_SOURCES
        vulkan.cpp
)

add_executable(vulkan_experiment ${VULKAN_EXPERIMENT_SOURCES})
target_link_libraries(vulkan_experiment PUBLIC moltenvk SDL3::SDL3)
target_link_libraries(vulkan_experiment PUBLIC
        "-framework Cocoa"
        "-framework Foundation"
        "-framework Metal"
        "-framework IOKit"
        "-framework IOSurface"
        "-framework QuartzCore"
)

# vulkan sdl experiment
set(VULKAN_SDL_SOURCES
        vulkan_sdl.cpp
)
add_executable(vulkan_sdl ${VULKAN_SDL_SOURCES})
target_link_libraries(vulkan_sdl PUBLIC moltenvk SDL3::SDL3)
target_link_libraries(vulkan_sdl PUBLIC
        "-framework Cocoa"
        "-framework Foundation"
        "-framework Metal"
        "-framework IOKit"
        "-framework IOSurface"
        "-framework QuartzCore"
)

# vulkan loader experiment
set(CMAKE_MACOSX_RPATH 1)
set(VULKAN_LOADER_EXPERIMENT
        vulkan_loader.cpp
)
add_executable(vulkan_loader_experiment ${VULKAN_LOADER_EXPERIMENT})
target_link_libraries(vulkan_loader_experiment PUBLIC vulkan_headers vulkan_loader vulkan_validation_layers)

# purely for debug purposes
set_target_properties(vulkan_loader_experiment PROPERTIES
        BUILD_RPATH ${VULKAN_LOADER_INSTALL_DIR}/lib
)
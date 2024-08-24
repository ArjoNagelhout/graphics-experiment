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
add_executable(ifc ifc.cpp)
target_link_libraries(ifc PUBLIC ifcopenshell)

# parser experiment
add_executable(parser parser.cpp)

# sdl window experiment
add_executable(sdl_experiment sdl.mm)
target_link_libraries(sdl_experiment PRIVATE SDL3::SDL3)

# molten vk experiment
add_executable(vulkan_experiment vulkan.cpp)
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
add_executable(vulkan_sdl vulkan_sdl.cpp)
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

add_executable(vulkan_loader_experiment vulkan_loader.cpp)
target_link_libraries(vulkan_loader_experiment PUBLIC vulkan_headers vulkan_loader vulkan_validation_layers)

# purely for debug purposes
set_target_properties(vulkan_loader_experiment PROPERTIES
        BUILD_RPATH ${VULKAN_LOADER_INSTALL_DIR}/lib
)

# vulkan sdl loader experiment
add_executable(vulkan_sdl_loader_experiment vulkan_sdl_loader.cpp)
target_link_libraries(vulkan_sdl_loader_experiment PUBLIC SDL3::SDL3 vulkan_headers vulkan_loader vulkan_validation_layers glslang glslang-default-resource-limits)
set_target_properties(vulkan_sdl_loader_experiment PROPERTIES
        BUILD_RPATH ${VULKAN_LOADER_INSTALL_DIR}/lib
)
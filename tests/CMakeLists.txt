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

# sdl window experiment
add_executable(sdl_experiment sdl.mm)
target_link_libraries(sdl_experiment PRIVATE SDL3::SDL3)

# vulkan loader experiment
set(CMAKE_MACOSX_RPATH 1)

# vulkan sdl loader experiment
add_executable(vulkan_sdl_loader_experiment vulkan_sdl_loader.cpp)
target_link_libraries(vulkan_sdl_loader_experiment PUBLIC
        SDL3::SDL3
        glm
        VulkanMemoryAllocator
        vulkan_headers
        vulkan_loader
        vulkan_validation_layers
        glslang
        glslang-default-resource-limits
)
set_target_properties(vulkan_sdl_loader_experiment PROPERTIES
        BUILD_RPATH ${VULKAN_LOADER_INSTALL_DIR}/lib
)

# vulkan vr experiment
# we need to figure out some way to create an android project
add_executable(vulkan_meta_quest_open_xr vulkan_meta_quest_open_xr.cpp)
target_link_libraries(vulkan_meta_quest_open_xr PUBLIC
        SDL3::SDL3
        glm
        VulkanMemoryAllocator
        vulkan_headers
        vulkan_loader
        vulkan_validation_layers
        glslang
        glslang-default-resource-limits
)
set_target_properties(vulkan_meta_quest_open_xr PROPERTIES
        BUILD_RPATH ${VULKAN_LOADER_INSTALL_DIR}/lib
)
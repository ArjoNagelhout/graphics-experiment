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

# vulkan sdl loader experiment
find_package(Vulkan REQUIRED COMPONENTS glslang SPIRV-Tools)

find_library(GLSLANG_DEFAULT glslang-default-resource-limits)
find_library(SPIRV_TOOLS_OPT SPIRV-Tools-opt)

add_executable(vulkan_sdl_loader_experiment vulkan_sdl_loader.cpp)
target_link_libraries(vulkan_sdl_loader_experiment PUBLIC
        SDL3::SDL3
        glm
        Vulkan::Vulkan
        Vulkan::glslang
        Vulkan::SPIRV-Tools
        ${GLSLANG_DEFAULT}
        ${SPIRV_TOOLS_OPT}
        VulkanMemoryAllocator
)
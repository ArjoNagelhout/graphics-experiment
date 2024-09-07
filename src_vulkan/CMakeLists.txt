set(GRAPHICS_EXPERIMENT_SOURCES
        main.cpp
)

if (ANDROID)
    # for android we create a library that is used by the JNI (Java Native Interface)
    add_library(graphics_experiment SHARED ${GRAPHICS_EXPERIMENT_SOURCES})
else ()
    # otherwise, we create an executable
    add_executable(graphics_experiment ${GRAPHICS_EXPERIMENT_SOURCES})
endif ()

target_link_libraries(graphics_experiment PRIVATE
        SDL3::SDL3
        glm
        lodepng
        vulkan
        VulkanMemoryAllocator
)
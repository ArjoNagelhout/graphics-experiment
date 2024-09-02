add_library(graphics_experiment SHARED
        main.cpp
)

target_link_libraries(graphics_experiment PRIVATE
        SDL3::SDL3
        glm
        vulkan
        VulkanMemoryAllocator
)
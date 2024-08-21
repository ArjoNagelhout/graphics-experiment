//
// Created by Arjo Nagelhout on 17/08/2024.
//

#include <iostream>
#include <cassert>

#define VULKAN_HPP_ENABLE_DYNAMIC_LOADER_TOOL 0
#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_EXCEPTIONS
#define VK_ENABLE_BETA_EXTENSIONS 1 // for VK_KHR_portability_enumeration

#include <vulkan/vulkan_raii.hpp>
#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>

struct App
{
    // vulkan handles are simply pointers, do not contain any data
    // retrieving data needs to be done using functions
    vk::raii::Context context = &vkGetInstanceProcAddr;
    vk::raii::Instance instance = nullptr;
    vk::raii::PhysicalDevice physicalDevice = nullptr;
    vk::PhysicalDeviceProperties properties;
    vk::raii::Device device = nullptr;
};

[[nodiscard]] bool supportsExtension(std::vector<vk::ExtensionProperties>* supportedExtensions, char const* extensionName)
{
    auto it = std::find_if(
        supportedExtensions->begin(),
        supportedExtensions->end(),
        [extensionName](vk::ExtensionProperties p) { return strcmp(p.extensionName, extensionName) == 0; });
    return it != supportedExtensions->end();
}

[[nodiscard]] std::vector<char const*> getSdlVulkanExtensions()
{
    uint32_t count = 0;
    char const* const* sdlExtensions = SDL_Vulkan_GetInstanceExtensions(&count);
    std::vector<char const*> out(count);
    for (uint32_t i = 0; i < count; i++)
    {
        out[i] = sdlExtensions[i];
    }
    return out;
}

int main(int argc, char** argv)
{
    // initialize sdl
    {
        int result = SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER);
        assert(result >= 0);
    }

    App app;
    uint32_t version = app.context.enumerateInstanceVersion();
    std::cout << "vulkan version: " << version << std::endl;

    // create instance
    {

        std::vector<char const*> sdlExtensions = getSdlVulkanExtensions();

        std::vector<vk::ExtensionProperties> supportedExtensions = app.context.enumerateInstanceExtensionProperties(nullptr);

        std::vector<char const*> enabledExtensionNames;
        for (auto& sdlExtension: sdlExtensions)
        {
            if (supportsExtension(&supportedExtensions, sdlExtension))
            {
                enabledExtensionNames.emplace_back(sdlExtension);
            }
        }

        vk::ApplicationInfo appInfo(
            "App",
            {},
            {},
            {},
            vk::ApiVersion12
        );

        vk::InstanceCreateInfo info(
            {},
            &appInfo,
            nullptr,
            enabledExtensionNames
        );
        app.instance = app.context.createInstance(info).value();
    }

    // get physical device
    {
        std::vector<vk::raii::PhysicalDevice> physicalDevices = app.instance.enumeratePhysicalDevices().value();
        assert(!physicalDevices.empty());

        // todo: pick device that is the best suited for graphics (i.e. has a graphics queue / most memory)
        app.physicalDevice = physicalDevices[0];
        app.properties = app.physicalDevice.getProperties();
    }

    // create logical device
    // we need to specify which queues need to be created
    {
        std::vector<float> priorities{1.0f};
        vk::DeviceQueueCreateInfo graphicsQueue(
            {},
            0,
            priorities);

        std::vector<vk::DeviceQueueCreateInfo> queues{
            graphicsQueue
        };

        std::vector<char const*> enabledLayerNames;
        std::vector<char const*> enabledExtensionNames;
        vk::PhysicalDeviceFeatures enabledDeviceFeatures;

        vk::DeviceCreateInfo info(
            {},
            queues,
            enabledLayerNames,
            enabledExtensionNames,
            &enabledDeviceFeatures
        );
        app.device = app.physicalDevice.createDevice(info).value();
    }

    std::cout << "hello world" << std::endl;
}
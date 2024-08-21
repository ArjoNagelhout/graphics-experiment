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
//    vk::raii::Instance instance = nullptr;
//    vk::raii::PhysicalDevice physicalDevice = nullptr;
//    VkPhysicalDeviceProperties properties;
//    VkDevice_T* device;
};

int main(int argc, char** argv)
{
    // initialize sdl
    {
        int result = SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER);
        assert(result >= 0);
    }

    App app;
    uint32_t version = app.context.enumerateInstanceVersion();
    std::cout << "version: " << version << std::endl;

    // create instance
    if (0)
    {
//        uint32_t count = 0;
//        char const* const* extensions = SDL_Vulkan_GetInstanceExtensions(&count);
//
//        for (int i = 0; i < count; i++)
//        {
//            std::cout << extensions[i] << std::endl;
//        }

        //std::vector<vk::ExtensionProperties> supportedExtensions = app.context.enumerateInstanceExtensionProperties(nullptr);

        vk::ApplicationInfo appInfo(
            "App",
            {},
            {},
            {},
            vk::ApiVersion13
        );
        vk::InstanceCreateInfo info(
            {},
            &appInfo,
            0,
            nullptr,
            0,
            nullptr
        );
        //app.instance = app.context.createInstance(info).value();
    }

    // get physical device
    {
//        uint32_t count = 0;
//        vkEnumeratePhysicalDevices(app.instance, &count, nullptr);
//        assert(count > 0);
//        std::vector<VkPhysicalDevice_T*> devices(count);
//        vkEnumeratePhysicalDevices(app.instance, &count, devices.data());
//        app.physicalDevice = devices[0];
//
//        vkGetPhysicalDeviceProperties(app.physicalDevice, &app.properties);
    }

    // create device
    {
//        VkDeviceCreateInfo info{
//            .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
//        };
//        VkResult result = vkCreateDevice(app.physicalDevice, &info, nullptr, &app.device);
//        assert(result == VK_SUCCESS);
    }

    std::cout << "hello world" << std::endl;
}
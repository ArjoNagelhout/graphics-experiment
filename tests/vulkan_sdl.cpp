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

#define SDL_MAIN_USE_CALLBACKS 1 /* use the callbacks instead of main() */

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <SDL3/SDL_main.h>

// constants
// SDL
constexpr int stepRateInMilliseconds = 125;

// Vulkan
constexpr uint32_t graphicsQueueIndex = 0;

struct App
{
    // SDL
    SDL_Window* window = nullptr;
    SDL_TimerID stepTimer{};

    // Vulkan
    vk::raii::Context context = &vkGetInstanceProcAddr;
    vk::raii::Instance instance = nullptr;
    vk::raii::PhysicalDevice physicalDevice = nullptr;
    vk::PhysicalDeviceProperties properties;
    vk::raii::Device device = nullptr;
    vk::SurfaceKHR surface = nullptr;
    vk::SurfaceCapabilitiesKHR surfaceCapabilities;
    vk::SwapchainKHR swapchain = nullptr;
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

static Uint32 sdlTimerCallback(void* payload, SDL_TimerID timerId, Uint32 interval)
{
    SDL_UserEvent userEvent{
        .type = SDL_EVENT_USER,
        .code = 0,
        .data1 = nullptr,
        .data2 = nullptr
    };

    SDL_Event event{
        .type = SDL_EVENT_USER,
    };
    event.user = userEvent;
    SDL_PushEvent(&event);
    return interval;
}

// called each frame
SDL_AppResult SDL_AppIterate(void* appstate)
{
    App* app = (App*)appstate;

//    std::cout << "new frame" << std::endl;

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppInit(void** appstate, int argc, char* argv[])
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0)
    {
        return SDL_APP_FAILURE;
    }

    App* app = new App();
    *appstate = app;

    // create window
    {
        SDL_WindowFlags windowFlags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_VULKAN;
        app->window = SDL_CreateWindow("sdl window test", 600, 400, windowFlags);
        assert(app->window);
    }

    // initialize vulkan
    {
        uint32_t version = app->context.enumerateInstanceVersion();
        std::cout << "vulkan version: " << version << std::endl;

        // create instance
        {
            std::vector<char const*> sdlExtensions = getSdlVulkanExtensions();

            std::vector<vk::ExtensionProperties> supportedExtensions = app->context.enumerateInstanceExtensionProperties(nullptr);

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
            app->instance = app->context.createInstance(info).value();
        }

        // get physical device
        {
            std::vector<vk::raii::PhysicalDevice> physicalDevices = app->instance.enumeratePhysicalDevices().value();
            assert(!physicalDevices.empty());

            // todo: pick device that is the best suited for graphics (i.e. has a graphics queue / most memory)
            app->physicalDevice = physicalDevices[0];
            app->properties = app->physicalDevice.getProperties();
        }

        // create logical device
        {
            // we need to specify which queues need to be created
            std::vector<float> priorities{1.0f};
            vk::DeviceQueueCreateInfo graphicsQueue(
                {},
                graphicsQueueIndex,
                priorities);

            std::vector<vk::DeviceQueueCreateInfo> queues{
                graphicsQueue
            };

            std::vector<char const*> enabledLayerNames;
            std::vector<char const*> enabledExtensionNames{
                vk::KHRSwapchainExtensionName
            };
            vk::PhysicalDeviceFeatures enabledFeatures;

            vk::DeviceCreateInfo info(
                {},
                queues,
                enabledLayerNames,
                enabledExtensionNames,
                &enabledFeatures
            );
            app->device = app->physicalDevice.createDevice(info).value();
        }

        // create surface
        {
            VkSurfaceKHR surface;
            int result = SDL_Vulkan_CreateSurface(app->window, *app->instance, nullptr, &surface);
            assert(result == 0);
            app->surface = surface;
            app->surfaceCapabilities = app->physicalDevice.getSurfaceCapabilitiesKHR(app->surface);
        }

        // create swapchain
        {
            vk::SurfaceFormatKHR surfaceFormat(
                vk::Format::eB8G8R8A8Srgb,
                vk::ColorSpaceKHR::eSrgbNonlinear
            );

            std::vector<uint32_t> queueIndices{graphicsQueueIndex};
            vk::SwapchainCreateInfoKHR info{
                {},
                app->surface,
                2,
                surfaceFormat.format,
                surfaceFormat.colorSpace,
                app->surfaceCapabilities.currentExtent,
                1, // for stereoscopic rendering > 1
                vk::ImageUsageFlagBits::eColorAttachment,
                vk::SharingMode::eExclusive,
                queueIndices,
                app->surfaceCapabilities.currentTransform,
                vk::CompositeAlphaFlagBitsKHR::eOpaque,
                vk::PresentModeKHR::eFifo,
                true,
                nullptr
            };
            app->swapchain = app->device.createSwapchainKHR(info).value();
        }

        //SDL_Vulkan_GetPresentationSupport()
    }

    // create step timer
    {
        app->stepTimer = SDL_AddTimer(stepRateInMilliseconds, sdlTimerCallback, nullptr);
        assert(app->stepTimer != 0);
    }

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event const* event)
{
    switch (event->type)
    {
        case SDL_EVENT_QUIT:
            return SDL_APP_SUCCESS;
        case SDL_EVENT_USER:
        case SDL_EVENT_KEY_DOWN:
            break;
    }
    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate)
{
    if (appstate)
    {
        App* app = (App*)appstate;
        SDL_RemoveTimer(app->stepTimer);
        SDL_Vulkan_DestroySurface(*app->instance, app->surface, nullptr);
        SDL_DestroyWindow(app->window);
        delete app;
    }
}

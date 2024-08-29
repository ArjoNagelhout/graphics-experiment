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
constexpr int sdlTimerStepRateInMilliseconds = 125;
constexpr uint32_t maxConcurrentFrames = 2;

struct FrameData
{
    vk::raii::Semaphore acquiringImage; // don't go past if the swapchain image has not been acquired yet
    vk::raii::Semaphore rendering; // don't go past if we haven't completed rendering yet
    vk::raii::Fence gpuHasExecutedCommandBuffers;
};

struct App
{
    // sdl
    SDL_Window* window = nullptr;
    SDL_TimerID stepTimer{};

    // vulkan
    vk::raii::Context context = &vkGetInstanceProcAddr;
    vk::raii::Instance instance = nullptr;
    vk::raii::PhysicalDevice physicalDevice = nullptr;
    vk::PhysicalDeviceProperties properties;
    vk::raii::Device device = nullptr;

    // queues
    uint32_t graphicsQueueFamilyIndex = 0;
    vk::raii::Queue graphicsQueue = nullptr;

    // surface
    vk::SurfaceFormatKHR surfaceFormat{
        vk::Format::eB8G8R8A8Srgb,
        vk::ColorSpaceKHR::eSrgbNonlinear
    };
    vk::raii::SurfaceKHR surface = nullptr;
    vk::SurfaceCapabilitiesKHR surfaceCapabilities;

    // swapchain
    vk::raii::SwapchainKHR swapchain = nullptr;
    vk::Extent2D swapchainExtent;
    std::vector<vk::Image> swapchainImages;
    std::vector<vk::ImageView> swapchainImageViews;
    std::vector<FrameData> frames;
    size_t currentFrame = 0;

    // render pass
    vk::raii::RenderPass renderPassMain = nullptr;

    std::vector<vk::raii::Framebuffer> framebuffers;
};

void onLaunch(App* app);

void onDraw(App* app);

// SDL callbacks (instead of using a main function)

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

SDL_AppResult SDL_AppInit(void** appstate, int argc, char* argv[])
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0)
    {
        return SDL_APP_FAILURE;
    }

    App* app = new App();
    *appstate = app;
    onLaunch(app);
    return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate)
{
    if (appstate)
    {
        App* app = (App*)appstate;
        SDL_RemoveTimer(app->stepTimer);
        SDL_DestroyWindow(app->window);
        delete app;
    }
}

SDL_AppResult SDL_AppIterate(void* appstate)
{
    App* app = (App*)appstate;
    onDraw(app);
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

void onLaunch(App* app)
{
    // create sdl step timer
    {
        app->stepTimer = SDL_AddTimer(sdlTimerStepRateInMilliseconds, sdlTimerCallback, nullptr);
        assert(app->stepTimer != 0);
    }

    // create window
    {
        SDL_WindowFlags windowFlags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_VULKAN;
        app->window = SDL_CreateWindow("sdl window test", 600, 400, windowFlags);
        assert(app->window);
    }

    uint32_t version = app->context.enumerateInstanceVersion();
    std::cout << "vulkan version: " << version << std::endl;

    // create vulkan instance / create instance
    {
        std::vector<char const*> sdlExtensions = getSdlVulkanExtensions();

        std::vector<vk::ExtensionProperties> supportedExtensions = app->context.enumerateInstanceExtensionProperties(nullptr);

        std::vector<vk::LayerProperties> layers = app->context.enumerateInstanceLayerProperties();
        for (auto& layer: layers)
        {
            std::cout << "layer: " << layer.layerName << ", " << layer.description << std::endl;
        }

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
            app->graphicsQueueFamilyIndex,
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

    // create graphics queue
    {
        std::vector<vk::QueueFamilyProperties2> properties = app->physicalDevice.getQueueFamilyProperties2();
        for (int i = 0; i < properties.size(); i++)
        {
            vk::QueueFamilyProperties2 p = properties[i];
            if (p.queueFamilyProperties.queueFlags & vk::QueueFlagBits::eGraphics)
            {
                app->graphicsQueueFamilyIndex = i;
                break;
            }
        }
        vk::DeviceQueueInfo2 queueInfo(
            {},
            app->graphicsQueueFamilyIndex,
            0
        );
        std::cout << app->graphicsQueueFamilyIndex << std::endl;
        app->graphicsQueue = app->device.getQueue2(queueInfo).value();
    }

    // create surface
    {
        VkSurfaceKHR surface;
        int result = SDL_Vulkan_CreateSurface(app->window, *app->instance, nullptr, &surface);
        assert(result == 0);
        app->surface = vk::raii::SurfaceKHR(app->instance, surface);
        app->surfaceCapabilities = app->physicalDevice.getSurfaceCapabilitiesKHR(app->surface);
    }

    // create swapchain
    {
        std::vector<uint32_t> queueIndices{app->graphicsQueueFamilyIndex};
        app->swapchainExtent = app->surfaceCapabilities.currentExtent;
        vk::SwapchainCreateInfoKHR info{
            {},
            app->surface,
            2,
            app->surfaceFormat.format,
            app->surfaceFormat.colorSpace,
            app->swapchainExtent,
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
        app->swapchainImages = app->swapchain.getImages();
    }

    // create swapchain image views
    {
        app->swapchainImageViews.resize(app->swapchainImages.size());
        for (size_t i = 0; i < app->swapchainImages.size(); i++)
        {
            // create image view
            vk::Image* image = &app->swapchainImages[i];
            vk::ImageViewCreateInfo info(
                {},
                *image,
                vk::ImageViewType::e2D,
                app->surfaceFormat.format
            );
            app->swapchainImageViews[i] = app->device.createImageView(info).value();
        }
    }

    // create render pass
    {
        // attachments
        vk::AttachmentDescription2 colorAttachment(
            {},
            app->surfaceFormat.format,
            vk::SampleCountFlagBits::e1,
            vk::AttachmentLoadOp::eClear,
            vk::AttachmentStoreOp::eStore,
            vk::AttachmentLoadOp::eDontCare,
            vk::AttachmentStoreOp::eDontCare,
            vk::ImageLayout::eUndefined,
            vk::ImageLayout::ePresentSrcKHR
        );
        std::vector<vk::AttachmentDescription2> attachments{
            colorAttachment
        };

        // subpasses
        std::vector<vk::AttachmentReference2> subpassColorAttachments{
            vk::AttachmentReference2(
                0,
                vk::ImageLayout::eColorAttachmentOptimal
            )
        };
        vk::AttachmentReference2 subpassDepthAttachment(
            1,
            vk::ImageLayout::eDepthAttachmentOptimal
        );

        vk::SubpassDescription2 subpass(
            {},
            vk::PipelineBindPoint::eGraphics,
            {},
            {},
            subpassColorAttachments,
            {},
            &subpassDepthAttachment,
            {}
        );

        std::vector<vk::SubpassDescription2> subpasses{subpass};

        // subpass dependencies (glue between subpasses and external
        vk::SubpassDependency2 dependencyColor(
            vk::SubpassExternal,
            0,
            vk::PipelineStageFlagBits::eColorAttachmentOutput,
            vk::PipelineStageFlagBits::eColorAttachmentOutput,
            vk::AccessFlagBits::eNone,
            vk::AccessFlagBits::eColorAttachmentWrite
        );
        vk::SubpassDependency2 dependencyDepth(
            vk::SubpassExternal,
            0,
            vk::PipelineStageFlagBits::eEarlyFragmentTests | vk::PipelineStageFlagBits::eLateFragmentTests,
            vk::PipelineStageFlagBits::eEarlyFragmentTests | vk::PipelineStageFlagBits::eLateFragmentTests,
            vk::AccessFlagBits::eNone,
            vk::AccessFlagBits::eDepthStencilAttachmentWrite
        );

        std::vector<vk::SubpassDependency2> dependencies{dependencyColor, dependencyDepth};

        // create render pass
        vk::RenderPassCreateInfo2 info(
            {},
            attachments,
            subpasses,
            dependencies
        );
        app->renderPassMain = app->device.createRenderPass2(info).value();
    }

    // create framebuffers (one for each swapchain image)
    {
        app->framebuffers.reserve(app->swapchainImages.size());
        for (size_t i = 0; i < app->swapchainImages.size(); i++)
        {
            vk::FramebufferCreateInfo info(
                {},
                app->renderPassMain,
                app->swapchainImageViews[i],
                app->swapchainExtent.width,
                app->swapchainExtent.height,
                1
            );
            app->framebuffers[i] = app->device.createFramebuffer(info).value();
        }
    }

    // create frame data for each frame
    {
        for (size_t i = 0; i < 2; i++)
        {
            app->frames.emplace_back(FrameData{
                .acquiringImage = app->device.createSemaphore({}).value(),
                .rendering = app->device.createSemaphore({}).value(),
                .gpuHasExecutedCommandBuffers = app->device.createFence(
                    vk::FenceCreateInfo(vk::FenceCreateFlagBits::eSignaled)).value() // create in signaled state
            });
        }
    }
}

void onDraw(App* app)
{
    FrameData* frame = &app->frames[app->currentFrame];

    // wait for the GPU to be done with the submitted command buffers of this frame data
    assert(app->device.waitForFences(*frame->gpuHasExecutedCommandBuffers, true, std::numeric_limits<uint64_t>::max()) == vk::Result::eSuccess);
    app->device.resetFences(*frame->gpuHasExecutedCommandBuffers);

    // acquire image
    vk::AcquireNextImageInfoKHR info(
        app->swapchain,
        10 /*ms*/ * 1000000,
        frame->acquiringImage,
        nullptr
    );
    auto [result, imageIndex] = app->device.acquireNextImage2KHR(info);
    if (result == vk::Result::eErrorOutOfDateKHR || result == vk::Result::eSuboptimalKHR)
    {
        // recreate swapchain
    }

    // create command pool
    vk::CommandPoolCreateInfo graphicsPoolInfo(
        vk::CommandPoolCreateFlagBits::eTransient,
        app->graphicsQueueFamilyIndex
    );
    vk::raii::CommandPool graphicsPool = app->device.createCommandPool(graphicsPoolInfo).value();

    // create command buffers
    vk::CommandBufferAllocateInfo bufferInfo(
        graphicsPool,
        vk::CommandBufferLevel::ePrimary,
        1
    );
    std::vector<vk::raii::CommandBuffer> buffers = app->device.allocateCommandBuffers(bufferInfo).value();

    vk::raii::CommandBuffer* cmd = &buffers[0];
    cmd->begin({});

    // main render pass
    vk::ClearValue clear(vk::ClearColorValue(255, 0, 255, 1));
    vk::ClearValue clearDepth(vk::ClearDepthStencilValue(1.0f, 0));
    std::vector<vk::ClearValue> clearValues{clear, clearDepth};
    vk::RenderPassBeginInfo renderPassBeginInfo(
        app->renderPassMain,
        app->framebuffers[imageIndex],
        vk::Rect2D(vk::Offset2D{0, 0}, app->swapchainExtent),
        clearValues
    );
    vk::SubpassBeginInfo subpassBeginInfo(
        vk::SubpassContents::eInline
    );
//    cmd->beginRenderPass2(renderPassBeginInfo, subpassBeginInfo);

//    cmd->endRenderPass();
    cmd->end();
    vk::PipelineStageFlags flags = vk::PipelineStageFlagBits::eColorAttachmentOutput;
    vk::SubmitInfo submitInfo(
        *frame->acquiringImage,
        flags,
        **cmd,
        *frame->rendering
    );
    app->graphicsQueue.submit(submitInfo, frame->gpuHasExecutedCommandBuffers);

    // present queue
    // get queue
    vk::PresentInfoKHR presentInfo(
        *frame->rendering,
        *app->swapchain,
        imageIndex
    );
    vk::Result presentResult = app->graphicsQueue.presentKHR(presentInfo);
    assert(presentResult == vk::Result::eSuccess);

    if (app->currentFrame < app->frames.size() - 1)
    {
        app->currentFrame++;
    }
    else
    {
        app->currentFrame = 0;
    }
}

//
// Created by Arjo Nagelhout on 17/08/2024.
//

#include <iostream>
#include <cassert>

#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_EXCEPTIONS
#define VK_ENABLE_BETA_EXTENSIONS

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
    // semaphore is for synchronization / dictating ordering of GPU commands
    // a fence is for the cpu to wait on the gpu to have finished a specific task

    vk::raii::Semaphore acquiringImage; // don't go past if the swapchain image has not been acquired yet
    vk::raii::Semaphore rendering; // don't go past if we haven't completed rendering yet

    vk::raii::CommandBuffer commandBuffer;
    vk::raii::Fence gpuHasExecutedCommandBuffer;
};

struct App
{
    // sdl
    SDL_Window* window = nullptr;
    SDL_TimerID stepTimer{};

    // vulkan
    vk::raii::Context context;
    vk::raii::Instance instance = nullptr;
    vk::raii::PhysicalDevice physicalDevice = nullptr;
    vk::PhysicalDeviceProperties properties;
    uint32_t physicalDeviceIndex = 0;
    vk::raii::Device device = nullptr;

    // queues
    uint32_t graphicsQueueIndex = 0;
    vk::raii::Queue graphicsQueue = nullptr;

    // surface
    vk::SurfaceFormatKHR surfaceFormat{
        vk::Format::eB8G8R8A8Srgb,
        vk::ColorSpaceKHR::eSrgbNonlinear
    };
    vk::raii::SurfaceKHR surface = nullptr;
    vk::SurfaceCapabilitiesKHR surfaceCapabilities;

    // render pass
    vk::raii::RenderPass renderPass = nullptr;

    // swapchain
    vk::raii::SwapchainKHR swapchain = nullptr;
    vk::Extent2D swapchainExtent;
    std::vector<vk::Image> swapchainImages;
    std::vector<vk::raii::ImageView> swapchainImageViews;
    std::vector<vk::raii::Framebuffer> framebuffers;

    // command pools
    // because we're using raii, the allocated command buffers should come *after* the pool in the struct
    // otherwise, the command buffers will try to destroy after the pool has been destroyed,
    // which results in a segfault.
    vk::raii::CommandPool graphicsPool = nullptr;

    // frame data (for concurrent frame rendering)
    // i.e. we can already start recording in a command buffer while the GPU is still executing the previous frame
    // (i.e. executing the other command buffer)
    std::vector<FrameData> frames;
    size_t currentFrame = 0;
};

void onLaunch(App* app);

void onDraw(App* app);

void onQuit(App* app);

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
        onQuit(app);
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

void onResize(App* app)
{
    app->device.waitIdle();

    app->swapchain.clear();
    app->swapchainImageViews.clear();
    app->framebuffers.clear();

    // update surface capabilities (to retrieve width and height)
    app->surfaceCapabilities = app->physicalDevice.getSurfaceCapabilitiesKHR(app->surface);

    // create swapchain
    {
        std::vector<uint32_t> queueIndices{app->graphicsQueueIndex};
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
        app->swapchainImageViews.reserve(app->swapchainImages.size());
        for (size_t i = 0; i < app->swapchainImages.size(); i++)
        {
            // create image view
            vk::Image* image = &app->swapchainImages[i];
            vk::ImageViewCreateInfo info(
                {},
                *image,
                vk::ImageViewType::e2D,
                app->surfaceFormat.format,
                vk::ComponentMapping(
                    vk::ComponentSwizzle::eIdentity,
                    vk::ComponentSwizzle::eIdentity,
                    vk::ComponentSwizzle::eIdentity,
                    vk::ComponentSwizzle::eIdentity
                ),
                vk::ImageSubresourceRange(
                    vk::ImageAspectFlagBits::eColor,
                    0,
                    1,
                    0,
                    1
                )
            );
            app->swapchainImageViews.emplace_back(app->device.createImageView(info).value());
        }
    }

    // create framebuffers (one for each swapchain image)
    {
        app->framebuffers.reserve(app->swapchainImages.size());
        for (size_t i = 0; i < app->swapchainImages.size(); i++)
        {
            vk::FramebufferCreateInfo info(
                {},
                app->renderPass,
                *app->swapchainImageViews[i],
                app->swapchainExtent.width,
                app->swapchainExtent.height,
                1
            );
            app->framebuffers.emplace_back(app->device.createFramebuffer(info).value());
        }
    }
}

void onLaunch(App* app)
{
    // create sdl step timer
    {
        app->stepTimer = SDL_AddTimer(sdlTimerStepRateInMilliseconds, sdlTimerCallback, nullptr);
        assert(app->stepTimer != 0);
    }

    uint32_t version = app->context.enumerateInstanceVersion();
    std::cout << "vulkan version: " << version << std::endl;

    // create vulkan instance / create instance
    {
        std::vector<char const*> sdlExtensions = getSdlVulkanExtensions();

        std::vector<vk::ExtensionProperties> supportedExtensions = app->context.enumerateInstanceExtensionProperties();

        std::vector<vk::LayerProperties> layers = app->context.enumerateInstanceLayerProperties();
        for (auto& layer: layers)
        {
            std::cout << "layer: " << layer.layerName << ", " << layer.description << std::endl;
        }

        std::vector<char const*> enabledExtensions;
        for (auto& sdlExtension: sdlExtensions)
        {
            if (supportsExtension(&supportedExtensions, sdlExtension))
            {
                enabledExtensions.emplace_back(sdlExtension);
            }
        }

        enabledExtensions.emplace_back(vk::KHRPortabilityEnumerationExtensionName);

        std::vector<char const*> enabledLayers{"VK_LAYER_KHRONOS_validation"};

        vk::ApplicationInfo appInfo(
            "App",
            {},
            {},
            {},
            vk::ApiVersion12
        );

        vk::InstanceCreateInfo info(
            vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR,
            &appInfo,
            enabledLayers,
            enabledExtensions
        );
        auto result = app->context.createInstance(info);
        if (result.has_value())
        {
            app->instance = std::move(result.value());
        }
        else
        {
            std::cout << "error: " << to_string(result.error()) << std::endl;
            exit(1);
        }
    }

    // get physical device
    {
        std::vector<vk::raii::PhysicalDevice> physicalDevices = app->instance.enumeratePhysicalDevices().value();
        assert(!physicalDevices.empty());

        // todo: pick device that is the best suited for graphics (i.e. has a graphics queue / most memory)
        app->physicalDeviceIndex = 0;
        app->physicalDevice = physicalDevices[app->physicalDeviceIndex];
        app->properties = app->physicalDevice.getProperties();
    }

    // create logical device
    {
        // we need to specify which queues need to be created
        std::vector<float> priorities{1.0f};
        vk::DeviceQueueCreateInfo graphicsQueue(
            {},
            app->graphicsQueueIndex,
            priorities);

        std::vector<vk::DeviceQueueCreateInfo> queues{
            graphicsQueue
        };

        std::vector<char const*> enabledLayerNames;
        std::vector<char const*> enabledExtensionNames{
            vk::KHRSwapchainExtensionName,
            vk::KHRPortabilitySubsetExtensionName
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
            if (p.queueFamilyProperties.queueFlags | vk::QueueFlagBits::eGraphics)
            {
                app->graphicsQueueIndex = i;
                break;
            }
        }
        vk::DeviceQueueInfo2 queueInfo(
            {},
            app->graphicsQueueIndex,
            0
        );
        app->graphicsQueue = app->device.getQueue2(queueInfo).value();
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
//        vk::AttachmentDescription2 depthAttachment(
//
//            );
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
//        vk::AttachmentReference2 subpassDepthAttachment(
//            1,
//            vk::ImageLayout::eDepthAttachmentOptimal
//        );

        vk::SubpassDescription2 subpass(
            {},
            vk::PipelineBindPoint::eGraphics,
            {},
            {},
            subpassColorAttachments,
            {},
            nullptr,//&subpassDepthAttachment,
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
//        vk::SubpassDependency2 dependencyDepth(
//            vk::SubpassExternal,
//            0,
//            vk::PipelineStageFlagBits::eEarlyFragmentTests | vk::PipelineStageFlagBits::eLateFragmentTests,
//            vk::PipelineStageFlagBits::eEarlyFragmentTests | vk::PipelineStageFlagBits::eLateFragmentTests,
//            vk::AccessFlagBits::eNone,
//            vk::AccessFlagBits::eDepthStencilAttachmentWrite
//        );

        std::vector<vk::SubpassDependency2> dependencies{dependencyColor};//, dependencyDepth};

        // create render pass
        vk::RenderPassCreateInfo2 info(
            {},
            attachments,
            subpasses,
            dependencies
        );
        app->renderPass = app->device.createRenderPass2(info).value();
    }

    // create window
    {
        SDL_WindowFlags windowFlags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_VULKAN;
        app->window = SDL_CreateWindow("sdl window test", 600, 400, windowFlags);
        assert(app->window);
    }

    // create surface
    {
        VkSurfaceKHR surface;
        int result = SDL_Vulkan_CreateSurface(app->window, *app->instance, nullptr, &surface);
        assert(result == 0);
        app->surface = vk::raii::SurfaceKHR(app->instance, surface);
    }

    // create swapchain / swapchain image views and framebuffers
    onResize(app);

    // create command pool / graphics pool
    {
        vk::CommandPoolCreateInfo graphicsPoolInfo(
            vk::CommandPoolCreateFlagBits::eResetCommandBuffer,
            app->graphicsQueueIndex
        );
        app->graphicsPool = app->device.createCommandPool(graphicsPoolInfo).value();
    }

    // allocate command buffers
    std::vector<vk::raii::CommandBuffer> commandBuffers;
    {
        vk::CommandBufferAllocateInfo bufferInfo(
            app->graphicsPool,
            vk::CommandBufferLevel::ePrimary,
            maxConcurrentFrames
        );
        commandBuffers = app->device.allocateCommandBuffers(bufferInfo).value();
    }

    // create frame data for each frame
    {
        for (size_t i = 0; i < maxConcurrentFrames; i++)
        {
            app->frames.emplace_back(FrameData{
                .acquiringImage = app->device.createSemaphore({}).value(),
                .rendering = app->device.createSemaphore({}).value(),
                .commandBuffer = std::move(commandBuffers[i]),
                .gpuHasExecutedCommandBuffer = app->device.createFence(
                    vk::FenceCreateInfo(vk::FenceCreateFlagBits::eSignaled)).value() // create in signaled state
            });
        }
        commandBuffers.clear();
    }
}

void onDraw(App* app)
{
    FrameData* frame = &app->frames[app->currentFrame];

    // wait for the GPU to be done with the submitted command buffers of this frame data
    assert(app->device.waitForFences(*frame->gpuHasExecutedCommandBuffer, true, std::numeric_limits<uint64_t>::max()) == vk::Result::eSuccess);
    app->device.resetFences(*frame->gpuHasExecutedCommandBuffer);
    frame->commandBuffer.reset();

    // acquire image
    vk::AcquireNextImageInfoKHR info(
        app->swapchain,
        10 /*ms*/ * 1000000,
        frame->acquiringImage,
        nullptr,
        1 << app->physicalDeviceIndex
    );
    auto [result, imageIndex] = app->device.acquireNextImage2KHR(info);
    if (result == vk::Result::eErrorOutOfDateKHR || result == vk::Result::eSuboptimalKHR)
    {
        // recreate swapchain
    }

    vk::raii::CommandBuffer* cmd = &frame->commandBuffer;
    cmd->begin({});

    // main render pass
    vk::ClearValue clear(vk::ClearColorValue(255, 0, 255, 255));
    vk::ClearValue clearDepth(vk::ClearDepthStencilValue(1.0f, 0));
    std::vector<vk::ClearValue> clearValues{clear, clearDepth};
    vk::RenderPassBeginInfo renderPassBeginInfo(
        app->renderPass,
        app->framebuffers[imageIndex],
        vk::Rect2D(vk::Offset2D{0, 0}, app->swapchainExtent),
        clearValues
    );
    vk::SubpassBeginInfo subpassBeginInfo(
        vk::SubpassContents::eInline
    );
    cmd->beginRenderPass2(renderPassBeginInfo, subpassBeginInfo);

    cmd->endRenderPass();
    cmd->end();
    vk::PipelineStageFlags flags = vk::PipelineStageFlagBits::eColorAttachmentOutput;
    vk::SubmitInfo submitInfo(
        *frame->acquiringImage,
        flags,
        **cmd,
        *frame->rendering
    );
    app->graphicsQueue.submit(submitInfo, frame->gpuHasExecutedCommandBuffer);

    // present queue
    // get queue
    vk::PresentInfoKHR presentInfo(
        *frame->rendering,
        *app->swapchain,
        imageIndex
    );
    vk::Result presentResult = app->graphicsQueue.presentKHR(presentInfo);
    if (presentResult == vk::Result::eErrorOutOfDateKHR || presentResult == vk::Result::eSuboptimalKHR)
    {
        onResize(app);
    }

    app->currentFrame = (app->currentFrame + 1) % app->frames.size();
}

void onQuit(App* app)
{
    SDL_RemoveTimer(app->stepTimer);
    SDL_DestroyWindow(app->window);

    app->device.waitIdle();
}
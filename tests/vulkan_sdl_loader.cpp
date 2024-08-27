//
// Created by Arjo Nagelhout on 17/08/2024.
//

#include <iostream>
#include <cassert>
#include <filesystem>
#include <fstream>

#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_EXCEPTIONS
#define VK_ENABLE_BETA_EXTENSIONS

#include <vulkan/vulkan_raii.hpp>

#define SDL_MAIN_USE_CALLBACKS 1 /* use the callbacks instead of main() */

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <SDL3/SDL_main.h>

#include <glslang/Public/ShaderLang.h>
#include <glslang/Public/ResourceLimits.h>
#include <glslang/MachineIndependent/localintermediate.h>
#include <SPIRV/GlslangToSpv.h>

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

struct AppConfig
{
    std::filesystem::path assetsPath;
    std::filesystem::path privateAssetsPath;
};

// maybe shader variants can be stored directly inside this same structure?
struct Shader
{
    // add any metadata / reflection information here

    // descriptor sets
    std::vector<vk::raii::DescriptorSetLayout> descriptorSetLayouts;

    // pipeline
    vk::raii::PipelineLayout pipelineLayout = nullptr;
    vk::raii::Pipeline pipeline = nullptr;
};

struct App
{
    AppConfig config;

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
    vk::raii::RenderPass renderPassMain = nullptr;

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

    // pipeline
    vk::raii::PipelineCache pipelineCache = nullptr;
    std::unique_ptr<Shader> shader;
};

void onLaunch(App* app, int argc, char** argv);

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
    onLaunch(app, argc, argv);
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
                app->renderPassMain,
                *app->swapchainImageViews[i],
                app->swapchainExtent.width,
                app->swapchainExtent.height,
                1
            );
            app->framebuffers.emplace_back(app->device.createFramebuffer(info).value());
        }
    }
}

[[nodiscard]] vk::raii::ShaderModule createShaderModule(vk::raii::Device* device, std::filesystem::path const& path, EShLanguage stage)
{
    assert(std::filesystem::exists(path));

    std::ifstream file(path);
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string string = buffer.str();

    glslang::InitializeProcess();
    EShMessages messages = EShMessages::EShMsgDebugInfo;

    glslang::TShader shader(stage);

    std::vector<char const*> strings{string.c_str()};
    shader.setStrings(strings.data(), 1);
    shader.setEnvInput(glslang::EShSourceGlsl, stage, glslang::EShClientVulkan, 100);
    shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_2);
    shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_2);
    bool success = shader.parse(GetDefaultResources(), 110, false, messages);
    assert(success);

    glslang::TProgram program;
    program.addShader(&shader);
    success = program.link(messages);
    std::cout << program.getInfoDebugLog() << std::endl;
    assert(success);

    // loop through all shader stages and add if that stage exists
    glslang::TIntermediate* intermediate = program.getIntermediate(stage);

    std::vector<uint32_t> spirv;
    spv::SpvBuildLogger logger;
    glslang::SpvOptions options{
        .generateDebugInfo = false,
        .stripDebugInfo = false,
        .disableOptimizer = false,
        .optimizeSize = false,
        .disassemble = false,
        .validate = true,
        .emitNonSemanticShaderDebugInfo = false,
        .emitNonSemanticShaderDebugSource = false,
        .compileOnly = false,
        .optimizerAllowExpandedIDBound = false
    };
    glslang::GlslangToSpv(*intermediate, spirv, &logger, &options);
    std::cout << logger.getAllMessages() << std::endl;

    glslang::FinalizeProcess();

    vk::ShaderModuleCreateInfo moduleInfo({}, spirv);
    return device->createShaderModule(moduleInfo).value();
}

[[nodiscard]] std::unique_ptr<Shader> createShader(
    vk::raii::Device* device,
    vk::raii::PipelineCache* cache,
    vk::raii::RenderPass* renderPass,
    std::filesystem::path const& vertexPath,
    std::filesystem::path const& fragmentPath)
{
    std::unique_ptr<Shader> shader = std::make_unique<Shader>();

    // stages
    // vertex stage
    vk::raii::ShaderModule vertexModule = createShaderModule(device, vertexPath, EShLanguage::EShLangVertex);
    vk::PipelineShaderStageCreateInfo vertexStage(
        {},
        vk::ShaderStageFlagBits::eVertex,
        vertexModule,
        "vertex",
        nullptr
    );

    // fragment stage
    vk::raii::ShaderModule fragmentModule = createShaderModule(device, fragmentPath, EShLanguage::EShLangFragment);
    vk::PipelineShaderStageCreateInfo fragmentStage(
        {},
        vk::ShaderStageFlagBits::eFragment,
        fragmentModule,
        "fragment",
        nullptr
    );
    std::vector<vk::PipelineShaderStageCreateInfo> stages{vertexStage, fragmentStage};

    // states

    // vertex input
    // bindings
    vk::VertexInputBindingDescription binding(
        0,
        16,
        vk::VertexInputRate::eVertex
    );
    std::vector<vk::VertexInputBindingDescription> bindings{binding};

    // attributes
    vk::VertexInputAttributeDescription attribute(
        0,
        0,
        vk::Format::eR32G32B32A32Sfloat
    );
    std::vector<vk::VertexInputAttributeDescription> attributes{attribute};

    vk::PipelineVertexInputStateCreateInfo vertexInputState = vk::PipelineVertexInputStateCreateInfo(
        {},
        bindings,
        attributes
    );

    vk::PipelineInputAssemblyStateCreateInfo inputAssemblyState(
        {},
        vk::PrimitiveTopology::eTriangleList,
        true
    );

    vk::PipelineRasterizationStateCreateInfo rasterizationState(
        {},
        true,
        true,
        vk::PolygonMode::eFill,
        vk::CullModeFlagBits::eBack,
        vk::FrontFace::eClockwise,
        true,
        0.0f,
        1.0f,
        0.0f,
        1.0f
    );
    vk::PipelineMultisampleStateCreateInfo multisampleState(
        {},
        vk::SampleCountFlagBits::e1,
        false,
        0.0f,
        {},
        false,
        false
    );
    vk::PipelineDepthStencilStateCreateInfo depthStencilState(
        {},
        true,
        true,
        vk::CompareOp::eLessOrEqual,
        true,
        false,
        {},
        {},
        0.0f,
        1.0f
    );
    std::vector<vk::PipelineColorBlendAttachmentState> attachments;
    vk::PipelineColorBlendStateCreateInfo colorBlendState(
        {},
        false,
        vk::LogicOp::eClear,
        attachments,
        {0.0f, 0.0f, 0.0f, 0.0f}
    );

    std::vector<vk::DynamicState> dynamicStates{
        vk::DynamicState::eViewport,
        vk::DynamicState::eScissor
    };
    vk::PipelineDynamicStateCreateInfo dynamicState(
        {},
        dynamicStates
    );

    vk::DescriptorSetLayoutBinding descriptorSetBinding(
        0,
        vk::DescriptorType::eUniformBuffer,
        1,
        vk::ShaderStageFlagBits::eVertex
    );
    std::vector<vk::DescriptorSetLayoutBinding> descriptorSetBindings{descriptorSetBinding};
    vk::DescriptorSetLayoutCreateInfo descriptorSetInfo(
        {},
        descriptorSetBindings
    );
    vk::raii::DescriptorSetLayout descriptorSet1 = device->createDescriptorSetLayout(descriptorSetInfo).value();
    shader->descriptorSetLayouts.emplace_back(std::move(descriptorSet1));

    vk::PipelineLayoutCreateInfo layoutInfo(
        {},
        {},
        {}
        //shader->descriptorSetLayouts
    );
    shader->pipelineLayout = device->createPipelineLayout(layoutInfo).value();

    vk::GraphicsPipelineCreateInfo pipelineInfo(
        {},
        stages,
        &vertexInputState,
        &inputAssemblyState,
        nullptr,
        nullptr,
        &rasterizationState,
        &multisampleState,
        &depthStencilState,
        &colorBlendState,
        &dynamicState,
        shader->pipelineLayout,
        *renderPass,
        0
    );
    shader->pipeline = device->createGraphicsPipeline(cache, pipelineInfo).value();
    return shader;
}

void onLaunch(App* app, int argc, char** argv)
{
    // configure / set config
    {
        assert(argc == 3);
        for (int i = 1; i < argc; ++i)
        {
            printf("arg %2d = %s\n", i, argv[i]);
        }
        app->config.assetsPath = argv[1];
        app->config.privateAssetsPath = argv[2];
    }

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
            if (p.queueFamilyProperties.queueFlags & vk::QueueFlagBits::eGraphics)
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
        app->renderPassMain = app->device.createRenderPass2(info).value();
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

    // create pipeline cache
    {
        vk::PipelineCacheCreateInfo pipelineCacheInfo(
            {},
            {}
        );
        app->pipelineCache = app->device.createPipelineCache(pipelineCacheInfo).value();
    }

    // create graphics pipeline / create pipeline / create shader
    std::filesystem::path shadersPath = app->config.assetsPath / "shaders_vulkan";
    app->shader = createShader(
        &app->device,
        &app->pipelineCache,
        &app->renderPassMain,
        shadersPath / "shader_unlit.vert",
        shadersPath / "shader_unlit.frag"
    );
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
    vk::ClearValue clear(vk::ClearColorValue(0.0f, 1.0f, 1.0f, 1.0f));
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
    cmd->beginRenderPass2(renderPassBeginInfo, subpassBeginInfo);

    // set viewport
    vk::Viewport viewport(
        0, 0,
        (float)app->swapchainExtent.width,
        (float)app->swapchainExtent.height,
        0.0f, 1.0f
    );
    cmd->setViewport(0, viewport);

    // set scissor rect
    vk::Rect2D scissor(
        vk::Offset2D(0, 0),
        app->swapchainExtent
    );
    cmd->setScissor(0, scissor);

    cmd->bindPipeline(vk::PipelineBindPoint::eGraphics, app->shader->pipeline);
    //cmd->bindDescriptorSets(vk::PipelineBindPoint::eGraphics, app->pipelineLayout, 0, )
    vk::ArrayProxy<unsigned char const> constants;
    cmd->pushConstants(app->shader->pipelineLayout, vk::ShaderStageFlagBits::eVertex, 0, constants);

    //cmd->bindIndexBuffer()
    //cmd->bindVertexBuffers()
    //cmd->drawIndexed()

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
//
// Created by Arjo Nagelhout on 17/08/2024.
//

#include <iostream>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <string>
#include <array>

#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_STRUCT_CONSTRUCTORS
#define VULKAN_HPP_NO_EXCEPTIONS
#define VULKAN_HPP_NO_SMART_HANDLE
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

#define VMA_IMPLEMENTATION

#include <vk_mem_alloc.h>

// the following should be defined before including any headers that use glm, otherwise things break
#define GLM_ENABLE_EXPERIMENTAL
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_FORCE_LEFT_HANDED

//#include <glm/glm.hpp>
#include <glm/vec2.hpp>
#include <glm/vec3.hpp>

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

    uint32_t vulkanApiVersion = 0;
};

// maybe shader variants can be stored directly inside this same structure?
struct Shader
{
    // add any metadata / reflection information here

    // descriptor sets
    vk::raii::DescriptorSetLayout descriptorSetLayout = nullptr;
    vk::raii::DescriptorSet descriptorSet = nullptr;

    // pipeline
    vk::raii::PipelineLayout pipelineLayout = nullptr;
    vk::raii::Pipeline pipeline = nullptr;
};

struct VertexData
{
    glm::vec3 position;
    glm::vec2 uv;
    glm::vec3 normal;
};

// because I'm too lazy to call vmaDestroyAllocation for each allocation
namespace vma::raii
{
    struct Allocator
    {
        Allocator(VmaAllocator allocator_) : allocator(allocator_) {}

        Allocator(std::nullptr_t) {}

        ~Allocator()
        {
            if (allocator)
            {
                vmaDestroyAllocator(allocator);
            }
        }

        Allocator() = delete;

        Allocator(Allocator const&) = delete;

        Allocator& operator=(Allocator const&) = delete;

        Allocator& operator=(Allocator&& other) noexcept
        {
            std::swap(allocator, other.allocator);
            return *this;
        }

        [[nodiscard]] VmaAllocator operator*() const
        {
            return allocator;
        }

        VmaAllocator allocator = nullptr;
    };

    struct Allocation
    {
        Allocation(VmaAllocator allocator_, VmaAllocation allocation_) : allocator(allocator_), allocation(allocation_) {}

        Allocation(std::nullptr_t) {}

        ~Allocation()
        {
            if (allocation)
            {
                vmaFreeMemory(allocator, allocation);
            }
        }

        Allocation() = delete;

        Allocation(Allocation const&) = delete;

        Allocation& operator=(Allocation const&) = delete;

        Allocation& operator=(Allocation&& other) noexcept
        {
            // if we don't swap, the other one will still be valid and destroyed on move,
            // which would cause UB due to it freeing the memory in the destructor
            std::swap(allocator, other.allocator);
            std::swap(allocation, other.allocation);
            return *this;
        }

        [[nodiscard]] VmaAllocation operator*() const
        {
            return allocation;
        }

        VmaAllocator allocator = nullptr;
        VmaAllocation allocation = nullptr;
    };
}

struct BufferDescriptor
{
    size_t size = 0;
    // if update frequently is turned on, we don't use a staging buffer
    bool updateFrequently = false; // update or accessed frequently
    vk::BufferUsageFlags usage;
};

struct Buffer
{
    BufferDescriptor descriptor; // we simply keep the descriptor
    vk::raii::Buffer buffer = nullptr;
    vma::raii::Allocation allocation = nullptr;
};

struct Mesh
{
    uint32_t vertexCount = 0;
    uint32_t indexCount = 0;
    vk::IndexType indexType = vk::IndexType::eUint32;
    Buffer vertexBuffer;
    Buffer indexBuffer;
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
    uint32_t transferQueueFamilyIndex = 0;
    uint32_t graphicsQueueFamilyIndex = 0;
    vk::raii::Queue graphicsQueue = nullptr;
    vk::raii::Queue transferQueue = nullptr;

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
    vk::raii::DescriptorPool descriptorPool = nullptr;
    std::unique_ptr<Shader> shader;

    // memory allocator
    vma::raii::Allocator allocator = nullptr;

    // uploading from CPU to GPU
    vk::raii::CommandPool uploadPool = nullptr;
    vk::raii::CommandBuffer uploadBuffer = nullptr;
    vk::raii::Fence gpuHasFinishedExecutingUploadBuffer = nullptr;

    // mesh
    Mesh mesh;
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
        std::vector<uint32_t> queueIndices{app->graphicsQueueFamilyIndex};
        app->swapchainExtent = app->surfaceCapabilities.currentExtent;
        vk::SwapchainCreateInfoKHR info{
            .surface = app->surface,
            .minImageCount = 2,
            .imageFormat = app->surfaceFormat.format,
            .imageColorSpace = app->surfaceFormat.colorSpace,
            .imageExtent = app->swapchainExtent,
            .imageArrayLayers = 1, // for stereoscopic rendering > 1
            .imageUsage = vk::ImageUsageFlagBits::eColorAttachment,
            .imageSharingMode = vk::SharingMode::eExclusive,
            .queueFamilyIndexCount = (uint32_t)queueIndices.size(),
            .pQueueFamilyIndices = queueIndices.data(),
            .preTransform = app->surfaceCapabilities.currentTransform,
            .compositeAlpha = vk::CompositeAlphaFlagBitsKHR::eOpaque,
            .presentMode = vk::PresentModeKHR::eFifo,
            .clipped = true,
            .oldSwapchain = nullptr
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
            vk::ImageViewCreateInfo info{
                .image = *image,
                .viewType = vk::ImageViewType::e2D,
                .format = app->surfaceFormat.format,
                .components = vk::ComponentMapping{
                    .r = vk::ComponentSwizzle::eIdentity,
                    .g = vk::ComponentSwizzle::eIdentity,
                    .b = vk::ComponentSwizzle::eIdentity,
                    .a = vk::ComponentSwizzle::eIdentity
                },
                .subresourceRange = vk::ImageSubresourceRange{
                    .aspectMask = vk::ImageAspectFlagBits::eColor,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1
                }
            };
            app->swapchainImageViews.emplace_back(app->device.createImageView(info).value());
        }
    }

    // create framebuffers (one for each swapchain image)
    {
        app->framebuffers.reserve(app->swapchainImages.size());
        for (size_t i = 0; i < app->swapchainImages.size(); i++)
        {
            vk::FramebufferCreateInfo info{
                .renderPass = app->renderPassMain,
                .attachmentCount = 1,
                .pAttachments = &*app->swapchainImageViews[i],
                .width = app->swapchainExtent.width,
                .height = app->swapchainExtent.height,
                .layers = 1
            };
            app->framebuffers.emplace_back(app->device.createFramebuffer(info).value());
        }
    }
}

[[nodiscard]] vk::raii::ShaderModule createShaderModule(vk::raii::Device const* device, std::filesystem::path const& path, EShLanguage stage)
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

    vk::ShaderModuleCreateInfo moduleInfo{
        .codeSize = spirv.size() * sizeof(uint32_t),
        .pCode = spirv.data()
    };
    return device->createShaderModule(moduleInfo).value();
}

[[nodiscard]] std::unique_ptr<Shader> createShader(
    vk::raii::Device const* device,
    vk::raii::DescriptorPool const* descriptorPool,
    vk::raii::PipelineCache const* cache,
    vk::raii::RenderPass const* renderPass,
    std::filesystem::path const& vertexPath,
    std::filesystem::path const& fragmentPath,
    std::string const& vertexName,
    std::string const& fragmentName)
{
    std::unique_ptr<Shader> shader = std::make_unique<Shader>();

    // stages
    // vertex stage
    vk::raii::ShaderModule vertexModule = createShaderModule(device, vertexPath, EShLanguage::EShLangVertex);
    vk::PipelineShaderStageCreateInfo vertexStage{
        .stage = vk::ShaderStageFlagBits::eVertex,
        .module = *vertexModule,
        .pName = vertexName.c_str(),
        .pSpecializationInfo = nullptr
    };

    // fragment stage
    vk::raii::ShaderModule fragmentModule = createShaderModule(device, fragmentPath, EShLanguage::EShLangFragment);
    vk::PipelineShaderStageCreateInfo fragmentStage{
        .stage = vk::ShaderStageFlagBits::eFragment,
        .module = *fragmentModule,
        .pName = fragmentName.c_str(),
        .pSpecializationInfo = nullptr
    };
    std::vector<vk::PipelineShaderStageCreateInfo> stages{vertexStage, fragmentStage};

    // states

    // vertex input
    // bindings
    vk::VertexInputBindingDescription binding{
        .binding = 0,
        .stride = sizeof(float) * (3 + 2 + 3),
        .inputRate = vk::VertexInputRate::eVertex
    };
    std::vector<vk::VertexInputBindingDescription> bindings{binding};

    // attributes
    // layout(location = 0) in vec3 v_Position;
    // layout(location = 1) in vec2 v_UV;
    // layout(location = 2) in vec3 v_Normal;
    vk::VertexInputAttributeDescription position{
        .location = 0,
        .binding = 0,
        .format = vk::Format::eR32G32B32Sfloat
    };
    vk::VertexInputAttributeDescription uv{
        .location = 1,
        .binding = 0,
        .format = vk::Format::eR32G32Sfloat
    };
    vk::VertexInputAttributeDescription normal{
        .location = 2,
        .binding = 0,
        .format = vk::Format::eR32G32B32Sfloat
    };
    std::vector<vk::VertexInputAttributeDescription> attributes{position, uv, normal};

    vk::PipelineVertexInputStateCreateInfo vertexInputState{
        .vertexBindingDescriptionCount = (uint32_t)bindings.size(),
        .pVertexBindingDescriptions = bindings.data(),
        .vertexAttributeDescriptionCount = (uint32_t)attributes.size(),
        .pVertexAttributeDescriptions = attributes.data()
    };

    vk::PipelineInputAssemblyStateCreateInfo inputAssemblyState{
        .topology = vk::PrimitiveTopology::eTriangleList,
        .primitiveRestartEnable = false
    };
    vk::Viewport viewport{
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 0,
        .minDepth = 0.0f,
        .maxDepth = 1.0f
    };
    vk::Rect2D scissor{
        .offset = vk::Offset2D{
            .x = 0,
            .y = 0
        },
        .extent = vk::Extent2D{
            .width = 0,
            .height = 0
        }
    };
    vk::PipelineViewportStateCreateInfo viewportState{
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor
    };
    vk::PipelineRasterizationStateCreateInfo rasterizationState{
        .depthClampEnable = false,
        .rasterizerDiscardEnable = false,
        .polygonMode = vk::PolygonMode::eFill,
        .cullMode = vk::CullModeFlagBits::eBack,
        .frontFace = vk::FrontFace::eClockwise,
        .depthBiasEnable = false,
        .depthBiasConstantFactor = 0.0f,
        .depthBiasClamp = 0.0f,
        .depthBiasSlopeFactor = 0.0f,
        .lineWidth = 1.0f
    };
    vk::PipelineMultisampleStateCreateInfo multisampleState{
        .rasterizationSamples = vk::SampleCountFlagBits::e1,
        .sampleShadingEnable = false,
        .minSampleShading = 0.0f,
        .pSampleMask = nullptr,
        .alphaToCoverageEnable = false,
        .alphaToOneEnable = false
    };
    vk::PipelineDepthStencilStateCreateInfo depthStencilState{
        .depthTestEnable = true,
        .depthWriteEnable = true,
        .depthCompareOp = vk::CompareOp::eLessOrEqual,
        .depthBoundsTestEnable = true,
        .stencilTestEnable = false,
        .front = {},
        .back = {},
        .minDepthBounds = 0.0f,
        .maxDepthBounds = 1.0f
    };
    vk::PipelineColorBlendAttachmentState colorBlendAttachment{
        .blendEnable = true,
        .srcColorBlendFactor = vk::BlendFactor::eSrcAlpha,
        .dstColorBlendFactor = vk::BlendFactor::eOneMinusSrcAlpha,
        .colorBlendOp = vk::BlendOp::eAdd,
        .srcAlphaBlendFactor = vk::BlendFactor::eOne,
        .dstAlphaBlendFactor = vk::BlendFactor::eZero,
        .alphaBlendOp = vk::BlendOp::eAdd,
        .colorWriteMask = vk::ColorComponentFlagBits::eR | vk::ColorComponentFlagBits::eG | vk::ColorComponentFlagBits::eB | vk::ColorComponentFlagBits::eA
    };
    std::vector<vk::PipelineColorBlendAttachmentState> colorBlendAttachments{colorBlendAttachment};
    vk::PipelineColorBlendStateCreateInfo colorBlendState{
        .logicOpEnable = false,
        .logicOp = vk::LogicOp::eCopy,
        .attachmentCount = (uint32_t)colorBlendAttachments.size(),
        .pAttachments = colorBlendAttachments.data(),
        .blendConstants = std::array<float, 4>{0.0f, 0.0f, 0.0f, 0.0f}
    };

    std::vector<vk::DynamicState> dynamicStates{
        vk::DynamicState::eViewport,
        vk::DynamicState::eScissor
    };
    vk::PipelineDynamicStateCreateInfo dynamicState{
        .dynamicStateCount = (uint32_t)dynamicStates.size(),
        .pDynamicStates = dynamicStates.data()
    };

    // descriptor sets
    // vertex stage:
    vk::DescriptorSetLayoutBinding vertexCameraBuffer{
        .binding = 0,
        .descriptorType = vk::DescriptorType::eUniformBuffer,
        .descriptorCount = 1,
        .stageFlags = vk::ShaderStageFlagBits::eVertex
    };
    vk::DescriptorSetLayoutBinding fragmentTexture{
        .binding = 1,
        .descriptorType = vk::DescriptorType::eCombinedImageSampler,
        .descriptorCount = 1,
        .stageFlags = vk::ShaderStageFlagBits::eFragment
    };
    std::vector<vk::DescriptorSetLayoutBinding> descriptorSetBindings{vertexCameraBuffer, fragmentTexture};
    vk::DescriptorSetLayoutCreateInfo descriptorSet1Info{
        .bindingCount = (uint32_t)descriptorSetBindings.size(),
        .pBindings = descriptorSetBindings.data()
    };
    shader->descriptorSetLayout = device->createDescriptorSetLayout(descriptorSet1Info).value();

    // create descriptor sets based on layout
    vk::DescriptorSetAllocateInfo info{
        .descriptorPool = *descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &*shader->descriptorSetLayout
    };
    std::vector<vk::raii::DescriptorSet> sets = device->allocateDescriptorSets(info).value();
    assert(sets.size() == 1);
    shader->descriptorSet = std::move(sets[0]);

    vk::PushConstantRange vertexPushConstants{
        .stageFlags = vk::ShaderStageFlagBits::eVertex,
        .offset = 0,
        .size = 64
    };
    std::vector<vk::PushConstantRange> pushConstants{vertexPushConstants};

    // create pipeline layout

    vk::PipelineLayoutCreateInfo layoutInfo{
        .setLayoutCount = 1,
        .pSetLayouts = &*shader->descriptorSetLayout,
        .pushConstantRangeCount = (uint32_t)pushConstants.size(),
        .pPushConstantRanges = pushConstants.data()
    };
    shader->pipelineLayout = device->createPipelineLayout(layoutInfo).value();

    vk::GraphicsPipelineCreateInfo pipelineInfo{
        .stageCount = (uint32_t)stages.size(),
        .pStages = stages.data(),
        .pVertexInputState = &vertexInputState,
        .pInputAssemblyState = &inputAssemblyState,
        .pTessellationState = nullptr,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizationState,
        .pMultisampleState = &multisampleState,
        .pDepthStencilState = &depthStencilState,
        .pColorBlendState = &colorBlendState,
        .pDynamicState = &dynamicState,
        .layout = shader->pipelineLayout,
        .renderPass = *renderPass,
        .subpass = 0,
        .basePipelineHandle = nullptr,
        .basePipelineIndex = -1
    };
    shader->pipeline = device->createGraphicsPipeline(cache, pipelineInfo).value();
    return shader;
}

Buffer createBuffer(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    BufferDescriptor descriptor)
{
    vk::BufferCreateInfo info{
        .size = descriptor.size,
        .usage = descriptor.usage
    };
    VmaAllocationCreateInfo allocationInfo{};
    if (descriptor.updateFrequently)
    {
        allocationInfo.requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    }
    else
    {
        // if it's not frequently updated, we can keep it local in GPU memory
        allocationInfo.requiredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    }

    VkBuffer buffer;
    VmaAllocation allocation;
    vmaCreateBuffer(
        allocator,
        (VkBufferCreateInfo*)&info,
        &allocationInfo,
        &buffer,
        &allocation,
        nullptr
    );

    return Buffer{
        .descriptor = descriptor,
        .buffer = vk::raii::Buffer(*device, buffer),
        .allocation = vma::raii::Allocation(allocator, allocation)
    };
}

void uploadToBuffer(
    VmaAllocator allocator,
    Buffer* buffer, void* data, size_t length)
{
    assert(buffer);
    if (buffer->descriptor.updateFrequently)
    {
        // map memory directly
        void* destination = nullptr;
        vmaMapMemory(allocator, *buffer->allocation, &destination);
        memcpy(destination, data, buffer->descriptor.size);
        vmaUnmapMemory(allocator, *buffer->allocation);
    }
    else
    {
        // use staging buffer
        assert(false);

        // get queue
    }
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

        app->config.vulkanApiVersion = vk::ApiVersion12;
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

        vk::ApplicationInfo appInfo{
            .pApplicationName = "App",
            .applicationVersion = vk::makeApiVersion(1, 1, 0, 0),
            .pEngineName = nullptr,
            .engineVersion = vk::makeApiVersion(1, 1, 0, 0),
            .apiVersion = app->config.vulkanApiVersion
        };

        vk::InstanceCreateInfo info{
            .flags = vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR,
            .pApplicationInfo = &appInfo,
            .enabledLayerCount = (uint32_t)enabledLayers.size(),
            .ppEnabledLayerNames = enabledLayers.data(),
            .enabledExtensionCount = (uint32_t)enabledExtensions.size(),
            .ppEnabledExtensionNames = enabledExtensions.data()
        };
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

    // get queues family indices / get graphics queue and upload queue family indices
    {
        // loop through all available families
        bool foundGraphics = false;
        bool foundTransfer = false;

        std::vector<vk::QueueFamilyProperties> families = app->physicalDevice.getQueueFamilyProperties();
        for (int i = 0; i < families.size(); i++)
        {
            vk::QueueFamilyProperties family = families[i];

            if (!foundGraphics && family.queueFlags & vk::QueueFlagBits::eGraphics)
            {
                app->graphicsQueueFamilyIndex = i;
                foundGraphics = true;
            }
            else if (!foundTransfer && family.queueFlags & vk::QueueFlagBits::eTransfer)
            {
                app->transferQueueFamilyIndex = i;
                foundTransfer = true;
            }
        }

        // for now
        assert(app->graphicsQueueFamilyIndex != app->transferQueueFamilyIndex);
    }

    // create logical device / create device
    {
        // we need to specify which queues need to be created
        float priority = 1.0f;
        vk::DeviceQueueCreateInfo graphicsQueue{
            .queueFamilyIndex = app->graphicsQueueFamilyIndex,
            .queueCount = 1,
            .pQueuePriorities = &priority
        };

        vk::DeviceQueueCreateInfo transferQueue{
            .queueFamilyIndex = app->transferQueueFamilyIndex,
            .queueCount = 1,
            .pQueuePriorities = &priority
        };

        std::vector<vk::DeviceQueueCreateInfo> queues{
            graphicsQueue,
            transferQueue
        };

        std::vector<char const*> enabledLayerNames;
        std::vector<char const*> enabledExtensionNames{
            vk::KHRSwapchainExtensionName,
            vk::KHRPortabilitySubsetExtensionName
        };
        vk::PhysicalDeviceFeatures enabledFeatures;

        vk::DeviceCreateInfo info{
            .queueCreateInfoCount = (uint32_t)queues.size(),
            .pQueueCreateInfos = queues.data(),
            .enabledLayerCount = (uint32_t)enabledLayerNames.size(),
            .ppEnabledLayerNames = enabledLayerNames.data(),
            .enabledExtensionCount = (uint32_t)enabledExtensionNames.size(),
            .ppEnabledExtensionNames = enabledExtensionNames.data(),
            .pEnabledFeatures = &enabledFeatures
        };
        app->device = app->physicalDevice.createDevice(info).value();
    }

    // get queues
    {
        app->graphicsQueue = app->device.getQueue(app->graphicsQueueFamilyIndex, 0).value();
        app->transferQueue = app->device.getQueue(app->transferQueueFamilyIndex, 0).value();
    }

    // create render pass
    {
        // attachments
        vk::AttachmentDescription colorAttachment{
            .format = app->surfaceFormat.format,
            .samples = vk::SampleCountFlagBits::e1,
            .loadOp = vk::AttachmentLoadOp::eClear,
            .storeOp = vk::AttachmentStoreOp::eStore,
            .stencilLoadOp = vk::AttachmentLoadOp::eDontCare,
            .stencilStoreOp = vk::AttachmentStoreOp::eDontCare,
            .initialLayout = vk::ImageLayout::eUndefined,
            .finalLayout = vk::ImageLayout::ePresentSrcKHR
        };
        std::vector<vk::AttachmentDescription> attachments{
            colorAttachment
        };

        // subpasses
        std::vector<vk::AttachmentReference> subpassColorAttachments{
            vk::AttachmentReference{
                .attachment = 0,
                .layout = vk::ImageLayout::eColorAttachmentOptimal
            }
        };

        vk::SubpassDescription subpass{
            .pipelineBindPoint = vk::PipelineBindPoint::eGraphics,
            .inputAttachmentCount = 0,
            .pInputAttachments = nullptr,
            .colorAttachmentCount = (uint32_t)subpassColorAttachments.size(),
            .pColorAttachments = subpassColorAttachments.data(),
            .pResolveAttachments = nullptr,
            .pDepthStencilAttachment = nullptr,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = nullptr
        };

        std::vector<vk::SubpassDescription> subpasses{subpass};

        // subpass dependencies (glue between subpasses and external
        vk::SubpassDependency dependencyColor{
            .srcSubpass = vk::SubpassExternal,
            .dstSubpass = 0,
            .srcStageMask = vk::PipelineStageFlagBits::eColorAttachmentOutput,
            .dstStageMask = vk::PipelineStageFlagBits::eColorAttachmentOutput,
            .srcAccessMask = vk::AccessFlagBits::eNone,
            .dstAccessMask = vk::AccessFlagBits::eColorAttachmentWrite
        };

        std::vector<vk::SubpassDependency> dependencies{dependencyColor};//, dependencyDepth};

        // create render pass
        vk::RenderPassCreateInfo info{
            .attachmentCount = (uint32_t)attachments.size(),
            .pAttachments = attachments.data(),
            .subpassCount = (uint32_t)subpasses.size(),
            .pSubpasses = subpasses.data(),
            .dependencyCount = (uint32_t)dependencies.size(),
            .pDependencies = dependencies.data()
        };
        app->renderPassMain = app->device.createRenderPass(info).value();
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
        vk::CommandPoolCreateInfo graphicsPoolInfo{
            .flags = vk::CommandPoolCreateFlagBits::eResetCommandBuffer,
            .queueFamilyIndex = app->graphicsQueueFamilyIndex
        };
        app->graphicsPool = app->device.createCommandPool(graphicsPoolInfo).value();
    }

    // allocate command buffers
    std::vector<vk::raii::CommandBuffer> commandBuffers;
    {
        vk::CommandBufferAllocateInfo bufferInfo{
            .commandPool = app->graphicsPool,
            .level = vk::CommandBufferLevel::ePrimary,
            .commandBufferCount = maxConcurrentFrames
        };
        commandBuffers = app->device.allocateCommandBuffers(bufferInfo).value();
    }

    // create frame data for each frame
    {
        for (size_t i = 0; i < maxConcurrentFrames; i++)
        {
            vk::raii::Fence fence = app->device.createFence(vk::FenceCreateInfo{.flags = vk::FenceCreateFlagBits::eSignaled}).value();

            FrameData frameData{
                .acquiringImage = app->device.createSemaphore({}).value(),
                .rendering = app->device.createSemaphore({}).value(),
                .commandBuffer = std::move(commandBuffers[i]),
                .gpuHasExecutedCommandBuffer = std::move(fence) // create in signaled state
            };
            app->frames.emplace_back(std::move(frameData));
        }
        commandBuffers.clear();
    }

    // create pipeline cache
    {
        vk::PipelineCacheCreateInfo pipelineCacheInfo{};
        app->pipelineCache = app->device.createPipelineCache(pipelineCacheInfo).value();
    }

    // create descriptor pool
    {
        std::vector<vk::DescriptorPoolSize> pools{
            {
                .type = vk::DescriptorType::eUniformBuffer,
                .descriptorCount = 1
            },
            {
                .type = vk::DescriptorType::eCombinedImageSampler,
                .descriptorCount = 1
            }
        };
        vk::DescriptorPoolCreateInfo info{
            .maxSets = 10,
            .poolSizeCount = (uint32_t)pools.size(),
            .pPoolSizes = pools.data()
        };
        app->descriptorPool = app->device.createDescriptorPool(info).value();
    }

    // create graphics pipeline / create pipeline / create shader
    {
        std::filesystem::path shadersPath = app->config.assetsPath / "shaders_vulkan";
        app->shader = createShader(
            &app->device,
            &app->descriptorPool,
            &app->pipelineCache,
            &app->renderPassMain,
            shadersPath / "shader_unlit.vert",
            shadersPath / "shader_unlit.frag",
            "main",
            "main"
        );
    }

    // create allocator
    {
        VmaAllocatorCreateInfo info{
            .flags = {},
            .physicalDevice = *app->physicalDevice,
            .device = *app->device,
            .preferredLargeHeapBlockSize = 0,
            .pAllocationCallbacks = nullptr,
            .pDeviceMemoryCallbacks = nullptr,
            .pHeapSizeLimit = nullptr,
            .pVulkanFunctions = nullptr,
            .instance = *app->instance,
            .vulkanApiVersion = app->config.vulkanApiVersion
        };
        VmaAllocator allocator;
        VkResult result = vmaCreateAllocator(&info, &allocator);
        app->allocator = vma::raii::Allocator(allocator);
        assert(result == VK_SUCCESS);
    }

    // create upload context (for uploading from CPU to GPU using staging buffers)
    {
        // create pool
        vk::CommandPoolCreateInfo uploadPoolInfo{
            .flags = vk::CommandPoolCreateFlagBits::eResetCommandBuffer,
            .queueFamilyIndex = app->transferQueueFamilyIndex
        };
        app->uploadPool = app->device.createCommandPool(uploadPoolInfo).value();

        // create command buffer
        vk::CommandBufferAllocateInfo bufferInfo{
            .commandPool = app->uploadPool,
            .level = vk::CommandBufferLevel::ePrimary,
            .commandBufferCount = 1
        };
        std::vector<vk::raii::CommandBuffer> buffer = app->device.allocateCommandBuffers(bufferInfo).value();
        app->uploadBuffer = std::move(buffer[0]);
    }

    std::cout << "graphics queue family index: " << app->graphicsQueueFamilyIndex << std::endl;
    std::cout << "transfer queue family index: " << app->transferQueueFamilyIndex << std::endl;

    // create mesh
    {
        Mesh mesh;

        // vertices
        float minX = -0.5f;
        float minY = -0.5f;
        float maxX = 0.5f;
        float maxY = 0.5f;
        std::vector<VertexData> vertices = std::vector<VertexData>{
            VertexData{.position{minX, minY, 0.0f}},
            VertexData{.position{maxX, minY, 0.0f}},
            VertexData{.position{minX, maxY, 0.0f}},
            VertexData{.position{maxX, maxY, 0.0f}},
        };
        mesh.vertexCount = vertices.size();

        // indices
        std::vector<uint32_t> indices = std::vector<uint32_t>{
            0, 1, 3,
            1, 2, 3
        };
        mesh.indexCount = indices.size();
        mesh.indexType = vk::IndexType::eUint32;

        size_t vertexBufferSize = vertices.size() * sizeof(VertexData);
        size_t indexBufferSize = indices.size() * sizeof(uint32_t);

        // create vertex buffer
        BufferDescriptor vertexBufferInfo{
            .size = vertexBufferSize,
            .updateFrequently = true,
            .usage = vk::BufferUsageFlagBits::eVertexBuffer
        };
        mesh.vertexBuffer = createBuffer(&app->device, *app->allocator, vertexBufferInfo);

        // create index buffer
        BufferDescriptor indexBufferInfo{
            .size = indexBufferSize,
            .updateFrequently = true,
            .usage = vk::BufferUsageFlagBits::eIndexBuffer
        };
        mesh.indexBuffer = createBuffer(&app->device, *app->allocator, indexBufferInfo);

        // copy data from CPU to GPU
        uploadToBuffer(*app->allocator, &mesh.vertexBuffer, vertices.data(), vertexBufferSize);
        uploadToBuffer(*app->allocator, &mesh.indexBuffer, indices.data(), indexBufferSize);

        app->mesh = std::move(mesh);
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
    vk::AcquireNextImageInfoKHR info{
        .swapchain = app->swapchain,
        .timeout = 10 /*ms*/ * 1000000,
        .semaphore = frame->acquiringImage,
        .fence = nullptr,
        .deviceMask = 1u << app->physicalDeviceIndex
    };
    auto [result, imageIndex] = app->device.acquireNextImage2KHR(info);
    if (result == vk::Result::eErrorOutOfDateKHR || result == vk::Result::eSuboptimalKHR)
    {
        // recreate swapchain
    }

    vk::raii::CommandBuffer* cmd = &frame->commandBuffer;
    cmd->begin({});

    // main render pass
    vk::ClearValue clear(vk::ClearColorValue{0.0f, 1.0f, 1.0f, 1.0f});
    vk::ClearValue clearDepth(vk::ClearDepthStencilValue{1.0f, 0});
    std::vector<vk::ClearValue> clearValues{clear, clearDepth};
    vk::RenderPassBeginInfo renderPassBeginInfo{
        .renderPass = app->renderPassMain,
        .framebuffer = app->framebuffers[imageIndex],
        .renderArea = vk::Rect2D{vk::Offset2D{0, 0}, app->swapchainExtent},
        .clearValueCount = (uint32_t)clearValues.size(),
        .pClearValues = clearValues.data()
    };
    vk::SubpassBeginInfo subpassBeginInfo{.contents = vk::SubpassContents::eInline};
    cmd->beginRenderPass2(renderPassBeginInfo, subpassBeginInfo);

    // set viewport
    vk::Viewport viewport{
        .x = 0,
        .y = 0,
        .width = (float)app->swapchainExtent.width,
        .height = (float)app->swapchainExtent.height,
        .minDepth = 0.0f,
        .maxDepth = 1.0f
    };
    cmd->setViewport(0, viewport);

    // set scissor rect
    vk::Rect2D scissor{
        .offset = vk::Offset2D{.x = 0, .y = 0},
        .extent = app->swapchainExtent
    };
    cmd->setScissor(0, scissor);

    cmd->bindPipeline(vk::PipelineBindPoint::eGraphics, app->shader->pipeline);

    vk::ArrayProxy<unsigned char const> constants{'a', 'a', 'a', 'a'};
    cmd->pushConstants(app->shader->pipelineLayout, vk::ShaderStageFlagBits::eVertex, 0, constants);

    // bind descriptor sets
    cmd->bindDescriptorSets(vk::PipelineBindPoint::eGraphics, app->shader->pipelineLayout, 0, *app->shader->descriptorSet, {});

    // draw mesh
    cmd->bindIndexBuffer(*app->mesh.indexBuffer.buffer, 0, vk::IndexType::eUint32);
    cmd->bindVertexBuffers(0, *app->mesh.vertexBuffer.buffer, {0});
    cmd->drawIndexed(app->mesh.indexCount, 1, 0, 0, 0);

    cmd->endRenderPass();
    cmd->end();
    vk::PipelineStageFlags waitDestinationStageMask = vk::PipelineStageFlagBits::eColorAttachmentOutput;
    vk::SubmitInfo submitInfo{
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &*frame->acquiringImage,
        .pWaitDstStageMask = &waitDestinationStageMask,
        .commandBufferCount = 1,
        .pCommandBuffers = &**cmd,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &*frame->rendering
    };
    app->graphicsQueue.submit(submitInfo, frame->gpuHasExecutedCommandBuffer);

    // present queue
    // get queue
    vk::PresentInfoKHR presentInfo{
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &*frame->rendering,
        .swapchainCount = 1,
        .pSwapchains = &*app->swapchain,
        .pImageIndices = &imageIndex
    };
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
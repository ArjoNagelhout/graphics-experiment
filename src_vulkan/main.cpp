//
// Created by Arjo Nagelhout on 17/08/2024.
//
// Goal: Build a VR design application using OpenXR and Vulkan for AEC use cases
// - render and enable editing of BIM files (e.g. IFC)
// - for design review / conceptual design (for presentation purposes existing architectural
//   visualization solutions should suffice)
// - simple CAD editing operations
// - build on open source libraries (ifcOpenShell, OpenCascade, etc.)
// - collaborative, multi-user (requires server / client split)
// - model optimisations and streaming from central server (as on-board processing of Meta Quest Pro / 3 might
//   not be powerful enough. (interesting to experiment with))
//
// this scope is rather large, so it can be implemented in small steps, shipping a small part of this larger vision
// to ensure I'm building the right thing / receive feedback.
//
// first thing I want to have working:
// a simple VR app with some user interactions (e.g. scaling an imported scene)

#include <iostream>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <string>
#include <array>
#include <unordered_set>

#define VULKAN_HPP_RAII_NO_EXCEPTIONS
#define VULKAN_HPP_NO_STRUCT_CONSTRUCTORS
#define VULKAN_HPP_NO_EXCEPTIONS
#define VULKAN_HPP_NO_SMART_HANDLE
#define VK_ENABLE_BETA_EXTENSIONS

#define VK_VERSION

#include <vulkan/vulkan_raii.hpp>

#define SDL_MAIN_USE_CALLBACKS 1 /* use the callbacks instead of main() */

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <SDL3/SDL_main.h>

#include <shaderc/shaderc.hpp>

#define VMA_VULKAN_VERSION 1002000
#define VMA_IMPLEMENTATION

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

#include <vk_mem_alloc.h>

#pragma clang diagnostic pop

// the following should be defined before including any headers that use glm, otherwise things break
#define GLM_ENABLE_EXPERIMENTAL
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_FORCE_LEFT_HANDED

#include <glm/vec2.hpp>
#include <glm/vec3.hpp>
#include <glm/mat4x4.hpp>
#include <glm/gtx/quaternion.hpp>
#include <glm/gtx/transform.hpp>

#include <lodepng.h>

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
    // different for each operating system
    std::filesystem::path assetsPath;

    uint32_t vulkanApiVersion = 0;
    bool vulkanPortability = false; // for macOS / MoltenVK

    float cameraFov = 90.0f;
    float cameraNear = 0.1f;
    float cameraFar = 1000.0f;
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

struct BufferInfo
{
    size_t size = 0;
    // if update frequently is turned on, we don't use a staging buffer
    bool gpuOnly = false; // update or accessed frequently
    vk::BufferUsageFlags usage;
};

struct Buffer
{
    BufferInfo info{}; // we simply keep the info used to create this buffer
    vk::raii::Buffer buffer = nullptr;
    vma::raii::Allocation allocation = nullptr;
};

// texture is assumed to be gpu local, so will be uploaded to via a staging buffer
struct TextureInfo
{
    uint32_t width;
    uint32_t height;
    vk::Format format;
};

struct Texture
{
    TextureInfo info{};
    vk::raii::Image image = nullptr;
    vma::raii::Allocation allocation = nullptr;
    vk::raii::ImageView imageView = nullptr;
    vk::raii::Sampler sampler = nullptr;
};

struct Mesh
{
    uint32_t vertexCount = 0;
    uint32_t indexCount = 0;
    vk::IndexType indexType = vk::IndexType::eUint32;
    Buffer vertexBuffer;
    Buffer indexBuffer;
};

struct Transform
{
    glm::vec3 position{0, 0, 0};
    glm::quat rotation{1, 0, 0, 0};
    glm::vec3 scale{1};
};

[[nodiscard]] glm::mat4 transformToMatrix(Transform const* transform)
{
    glm::mat4 translation = glm::translate(glm::mat4(1), transform->position);
    glm::mat4 rotation = glm::toMat4(transform->rotation);
    glm::mat4 scale = glm::scale(transform->scale);
    return translation * rotation * scale;
}

struct CameraData
{
    glm::mat4 viewProjection = glm::mat4(1);
};

struct Queues
{
    // graphics queue
    uint32_t graphicsQueueFamilyIndex = 0;
    vk::raii::Queue graphicsQueue = nullptr;

    bool separateTransferQueue = false;
    uint32_t transferQueueFamilyIndex = 0;
    vk::raii::Queue transferQueue = nullptr;
};

struct UploadContext
{
    Queues* queues = nullptr;
    vk::raii::CommandBuffer transferCommandBuffer = nullptr; // if not separate transfer queue, this will be allocated from the graphicsCommandPool
    vk::raii::CommandBuffer graphicsCommandBuffer = nullptr; // only set if separate transfer queue
    vk::raii::Fence gpuHasExecutedTransferCommandBuffer = nullptr;
    vk::raii::Fence gpuHasExecutedGraphicsCommandBuffer = nullptr; // only if separate transfer queue
    vk::raii::Semaphore uploadCompleted = nullptr; // for when the transfer is completed, and we can run the queue family ownership transfer to the graphics queue
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
    Queues queues;

    // command pools (one per queue and set of required flags, these now contain the ability to reset the allocated command buffers)
    vk::raii::CommandPool graphicsCommandPool = nullptr;
    vk::raii::CommandPool transferCommandPool = nullptr;

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
    UploadContext uploadContext;

    // mesh
    Mesh mesh;

    // camera
    Transform cameraTransform{
        glm::vec3{-0.5f, 0, -0.8f}
    }; // for calculating the camera data (which contains the viewProjection matrix)
    float cameraYaw = 25.0f;
    float cameraPitch = 0.0f;
    float cameraRoll = 0.0f;
    CameraData cameraData; // data for GPU
    Buffer cameraDataBuffer;

    // image
    Texture texture;

    // input
    std::bitset<static_cast<size_t>(SDL_NUM_SCANCODES)> keys;
};

[[nodiscard]] bool isKeyPressed(App* app, SDL_Keycode key)
{
    SDL_Scancode scancode = SDL_GetScancodeFromKey(key, nullptr);
    return app->keys[scancode];
}

SDL_AppResult onLaunch(App* app, int argc, char** argv);

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
    return onLaunch(app, argc, argv);
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

void onKeyDown(App* app, SDL_Scancode scancode)
{
    app->keys[scancode] = true;
}

void onKeyUp(App* app, SDL_Scancode scancode)
{
    app->keys[scancode] = false;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event const* event)
{
    App* app = (App*)appstate;

    switch (event->type)
    {
        case SDL_EVENT_QUIT:
            return SDL_APP_SUCCESS;
        case SDL_EVENT_USER:
        case SDL_EVENT_KEY_DOWN:
            onKeyDown(app, event->key.scancode);
            break;
        case SDL_EVENT_KEY_UP:
            onKeyUp(app, event->key.scancode);
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

[[nodiscard]] bool supportsLayer(std::vector<vk::LayerProperties>* supportedLayers, char const* layerName)
{
    auto it = std::find_if(
        supportedLayers->begin(),
        supportedLayers->end(),
        [layerName](vk::LayerProperties p) { return strcmp(p.layerName, layerName) == 0; }
    );
    return it != supportedLayers->end();
}

[[nodiscard]] std::unordered_set<char const*> getSdlVulkanExtensions()
{
    uint32_t count = 0;
    char const* const* sdlExtensions = SDL_Vulkan_GetInstanceExtensions(&count);
    std::unordered_set<char const*> out(count);
    for (uint32_t i = 0; i < count; i++)
    {
        out.emplace(sdlExtensions[i]);
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

    // update surface format based on supported surface formats
    {
        std::vector<vk::SurfaceFormatKHR> supportedSurfaceFormats = app->physicalDevice.getSurfaceFormatsKHR(app->surface);

        // in order
        std::vector<vk::Format> desiredFormats{vk::Format::eR8G8B8A8Srgb, vk::Format::eB8G8R8A8Srgb};
        bool foundDesiredFormat = false;
        for (vk::Format desiredFormat: desiredFormats)
        {
            auto it = std::find_if(
                supportedSurfaceFormats.begin(),
                supportedSurfaceFormats.end(),
                [desiredFormat](vk::SurfaceFormatKHR f) { return f.format == desiredFormat; }
            );
            if (it != supportedSurfaceFormats.end())
            {
                app->surfaceFormat = *it;
                foundDesiredFormat = true;
                break;
            }
        }
        if (!foundDesiredFormat)
        {
            assert(!supportedSurfaceFormats.empty());
            app->surfaceFormat = supportedSurfaceFormats[0];
        }
    }

    // create swapchain
    {
        std::vector<uint32_t> queueIndices{app->queues.graphicsQueueFamilyIndex};
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

//
[[nodiscard]] bool importPng(std::filesystem::path const& path, TextureInfo* outInfo, std::vector<unsigned char>* outData)
{
    assert(outInfo);
    assert(outData);

    SDL_IOStream* stream = SDL_IOFromFile(path.c_str(), "r");
    if (!stream)
    {
        return false;
    }

    Sint64 fileSize = SDL_GetIOSize(stream);
    if (fileSize < 0)
    {
        SDL_CloseIO(stream);
        return false;
    }

    // import png using lodepng
    std::vector<unsigned char> png(fileSize);
    lodepng::State state;

    if (SDL_ReadIO(stream, png.data(), fileSize) != fileSize)
    {
        SDL_CloseIO(stream);
        return false;
    }

    unsigned int error = lodepng::decode(*outData, outInfo->width, outInfo->height, state, png);
    if (error != 0)
    {
        std::cout << lodepng_error_text(error) << std::endl;
        return false;
    }
    LodePNGColorMode color = state.info_png.color;
    assert(color.bitdepth == 8);
    assert(color.colortype == LCT_RGBA);

    outInfo->format = vk::Format::eR8G8B8A8Srgb;

    return true;
}

// returns whether successful
[[nodiscard]] bool readStringFromFile(std::filesystem::path const& path, std::string* outString)
{
    SDL_IOStream* stream = SDL_IOFromFile(path.c_str(), "r");
    if (!stream)
    {
        return false;
    }

    Sint64 fileSize = SDL_GetIOSize(stream);
    if (fileSize < 0)
    {
        SDL_CloseIO(stream);
        return false;
    }

    *outString = std::string(fileSize, '\0');
    if (SDL_ReadIO(stream, outString->data(), fileSize) != fileSize)
    {
        SDL_CloseIO(stream);
        return false;
    }

    SDL_CloseIO(stream);

    return true;
}

[[nodiscard]] vk::raii::ShaderModule createShaderModule(vk::raii::Device const* device, std::filesystem::path const& path, shaderc_shader_kind stage)
{
    std::string string;
    bool success = readStringFromFile(path, &string);
    assert(success);

    shaderc::Compiler compiler;
    shaderc::CompileOptions options;

    shaderc::SpvCompilationResult module = compiler.CompileGlslToSpv(
        string.c_str(), string.size(), stage, path.filename().c_str(), options);

    if (module.GetCompilationStatus() !=
        shaderc_compilation_status_success)
    {
        std::cerr << module.GetErrorMessage();
    }

    std::vector<uint32_t> spirv(module.cbegin(), module.cend());

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
    vk::raii::ShaderModule vertexModule = createShaderModule(device, vertexPath, shaderc_glsl_default_vertex_shader);
    vk::PipelineShaderStageCreateInfo vertexStage{
        .stage = vk::ShaderStageFlagBits::eVertex,
        .module = *vertexModule,
        .pName = vertexName.c_str(),
        .pSpecializationInfo = nullptr
    };

    // fragment stage
    vk::raii::ShaderModule fragmentModule = createShaderModule(device, fragmentPath, shaderc_glsl_default_fragment_shader);
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
        .cullMode = vk::CullModeFlagBits::eNone,
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
        .blendConstants = std::array < float, 4 > {0.0f, 0.0f, 0.0f, 0.0f}
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
    std::vector<vk::DescriptorSetLayoutBinding> descriptorSetBindings{vertexCameraBuffer};//, fragmentTexture};
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

[[nodiscard]] Buffer createBuffer(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    BufferInfo info)
{
    vk::BufferCreateInfo bufferInfo{
        .size = info.size,
        .usage = info.usage,
        .sharingMode = vk::SharingMode::eExclusive
    };
    VmaAllocationCreateInfo allocationInfo{};
    if (info.gpuOnly)
    {
        // local in GPU memory (most performant, unless data needs to be frequently accessed)
        allocationInfo.requiredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        bufferInfo.usage |= vk::BufferUsageFlagBits::eTransferDst; // otherwise we can't copy to the buffer
    }
    else
    {
        allocationInfo.requiredFlags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    }

    VkBuffer buffer;
    VmaAllocation allocation;
    vmaCreateBuffer(
        allocator,
        reinterpret_cast<VkBufferCreateInfo*>(&bufferInfo),
        &allocationInfo,
        &buffer,
        &allocation,
        nullptr
    );

    return Buffer{
        .info = info,
        .buffer = vk::raii::Buffer(*device, buffer),
        .allocation = vma::raii::Allocation(allocator, allocation)
    };
}

// if the buffer is not gpu only, we can copy to it directly
// assumed for now that the data is the size of the buffer
void copyToBufferCpuVisible(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    Buffer* buffer, void* data)
{
    assert(buffer);
    assert(!buffer->info.gpuOnly);

    // map memory directly
    void* destination = nullptr;
    vmaMapMemory(allocator, *buffer->allocation, &destination);
    memcpy(destination, data, buffer->info.size);
    vmaUnmapMemory(allocator, *buffer->allocation);
}

// if the buffer is gpu only, we need to first create a staging buffer
void copyToBufferGpuOnly(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    UploadContext* uploadContext,
    Buffer* buffer, void* data)
{
    assert(buffer);
    assert(buffer->info.gpuOnly);
    assert(uploadContext);

    // if there is a separate transfer queue, we should perform a queue family ownership transfer (QFOT) operation
    bool separateTransferQueue = uploadContext->queues->separateTransferQueue;

    // create staging buffer
    BufferInfo stagingBufferInfo{
        .size = buffer->info.size,
        .gpuOnly = false,
        .usage = vk::BufferUsageFlagBits::eTransferSrc
    };
    Buffer stagingBuffer = createBuffer(device, allocator, stagingBufferInfo);
    copyToBufferCpuVisible(device, allocator, &stagingBuffer, data);

    // upload
    // wait for the fence to be signaled
    assert(device->waitForFences(*uploadContext->gpuHasExecutedTransferCommandBuffer, true, UINT64_MAX) == vk::Result::eSuccess);
    device->resetFences(*uploadContext->gpuHasExecutedTransferCommandBuffer); // reset fence back to unsignaled state

    // get command buffer, record to it, and submit it
    vk::raii::CommandBuffer* cmd = &uploadContext->transferCommandBuffer;
    cmd->reset();

    cmd->begin({});

    // copy buffer
    vk::BufferCopy region{
        .srcOffset = 0,
        .dstOffset = 0,
        .size = buffer->info.size
    };
    cmd->copyBuffer(*stagingBuffer.buffer, buffer->buffer, region);

    // Resources created with a VkSharingMode of VK_SHARING_MODE_EXCLUSIVE must have their ownership explicitly
    // transferred from one queue family to another in order to access their content in a well-defined manner
    // on a queue in a different queue family.
    // See https://www.khronos.org/blog/understanding-vulkan-synchronization and the spec

    // "must be executed on both the source and destination queues"
    // see: https://github.com/KhronosGroup/Vulkan-Docs/wiki/Synchronization-Examples-(Legacy-synchronization-APIs)#transfer-dependencies

    if (separateTransferQueue)
    {
        vk::BufferMemoryBarrier barrier{
            .srcAccessMask = vk::AccessFlagBits::eTransferWrite,
            .dstAccessMask = vk::AccessFlagBits::eNone,
            .srcQueueFamilyIndex = uploadContext->queues->transferQueueFamilyIndex,
            .dstQueueFamilyIndex = uploadContext->queues->graphicsQueueFamilyIndex,
            .buffer = buffer->buffer,
            .offset = 0,
            .size = buffer->info.size
        };
        cmd->pipelineBarrier(
            vk::PipelineStageFlagBits::eTransfer, // execute after transfer has completed
            vk::PipelineStageFlagBits::eBottomOfPipe, // and before the pipeline is completed
            vk::DependencyFlagBits::eDeviceGroup,
            {},
            barrier,
            {});
    }
    cmd->end();

    vk::SubmitInfo submitInfo{
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = nullptr,
        .pWaitDstStageMask = nullptr,
        .commandBufferCount = 1,
        .pCommandBuffers = &**cmd,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = nullptr
    };

    if (separateTransferQueue)
    {
        submitInfo.signalSemaphoreCount = 1;
        submitInfo.pSignalSemaphores = &*uploadContext->uploadCompleted;
    }
    uploadContext->queues->transferQueue.submit(submitInfo, uploadContext->gpuHasExecutedTransferCommandBuffer);

    if (separateTransferQueue)
    {

    }

    vk::SubmitInfo graphicsSubmitInfo{

    };
    uploadContext->queues->graphicsQueue.submit(graphicsSubmitInfo);
}

// either uses staging buffer or copies directly depending on the buffer's gpuOnly property
void copyToBuffer(vk::raii::Device const* device,
                  VmaAllocator allocator,
                  UploadContext* uploadContext,
                  Buffer* buffer, void* data)
{
    assert(buffer);
    if (buffer->info.gpuOnly)
    {
        copyToBufferGpuOnly(device, allocator, uploadContext, buffer, data);
    }
    else
    {
        copyToBufferCpuVisible(device, allocator, buffer, data);
    }
}

[[nodiscard]] Texture createTexture(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    TextureInfo info)
{
    // how do we create a texture in Vulkan?
    // Image, ImageView, Sampler

    // create image
    vk::ImageCreateInfo imageInfo{
        .imageType = vk::ImageType::e2D,
        .format = info.format,
        .extent = vk::Extent3D{.width = info.width, .height = info.height, .depth = 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk::SampleCountFlagBits::e1,
        .tiling = vk::ImageTiling::eOptimal,
        .usage = vk::ImageUsageFlagBits::eSampled,
        .sharingMode = vk::SharingMode::eExclusive,
        .initialLayout = vk::ImageLayout::eUndefined
    };

    VmaAllocationCreateInfo allocationInfo{
        .requiredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    };

    VmaAllocation allocation;
    VkImage image;
    vmaCreateImage(allocator,
                   reinterpret_cast<VkImageCreateInfo*>(&imageInfo),
                   &allocationInfo,
                   &image,
                   &allocation,
                   nullptr);

    // create image view
    vk::ImageViewCreateInfo imageViewInfo{
        .image = image,
        .viewType = vk::ImageViewType::e2D,
        .format = info.format,
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
    vk::raii::ImageView imageView = device->createImageView(imageViewInfo).value();

    // create sampler
    vk::SamplerCreateInfo samplerInfo{
        .magFilter = vk::Filter::eLinear,
        .minFilter = vk::Filter::eLinear,
        .mipmapMode = vk::SamplerMipmapMode::eLinear,
        .addressModeU = vk::SamplerAddressMode::eClampToEdge,
        .addressModeV = vk::SamplerAddressMode::eClampToEdge,
        .addressModeW = vk::SamplerAddressMode::eClampToEdge,
        .mipLodBias = 0.0f,
        .anisotropyEnable = false,
        .maxAnisotropy = 0.0f,
        .compareEnable = false,
        .compareOp = vk::CompareOp::eLessOrEqual,
        .minLod = 0.0f,
        .maxLod = 1.0f,
        .borderColor = vk::BorderColor::eFloatOpaqueWhite,
        .unnormalizedCoordinates = false
    };
    vk::raii::Sampler sampler = device->createSampler(samplerInfo).value();

    return Texture{
        .info = info,
        .image = vk::raii::Image(*device, image),
        .allocation = vma::raii::Allocation(allocator, allocation),
        .imageView = std::move(imageView),
        .sampler = std::move(sampler)
    };
}

// creates a staging buffer and uploads data to it
void uploadToTexture(
    vk::raii::Device const* device,
    VmaAllocator allocator,
    UploadContext* uploadContext,
    Texture* texture,
    std::vector<unsigned char>* data)
{
    assert(device);
    assert(allocator);
    assert(texture);
    assert(data);

    // create staging buffer
    BufferInfo stagingBufferInfo{
        .size = data->size(),
        .gpuOnly = false,
        .usage = vk::BufferUsageFlagBits::eTransferSrc
    };
    Buffer stagingBuffer = createBuffer(device, allocator, stagingBufferInfo);
    copyToBufferCpuVisible(device, allocator, &stagingBuffer, data->data());
}

// allocates a single command buffer from the pool
[[nodiscard]] vk::raii::CommandBuffer allocateCommandBuffer(vk::raii::Device const* device, vk::raii::CommandPool* pool)
{
    vk::CommandBufferAllocateInfo info{
        .commandPool = *pool,
        .level = vk::CommandBufferLevel::ePrimary,
        .commandBufferCount = 1
    };
    std::vector<vk::raii::CommandBuffer> buffers = device->allocateCommandBuffers(info).value();
    return std::move(buffers[0]);
}

SDL_AppResult onLaunch(App* app, int argc, char** argv)
{
    // configure / set config
    {
#if defined(__ANDROID__)
        app->config.assetsPath = "";
#else
        // desktop requires the assetsPath to be supplied as a program argument
        assert(argc > 1);
        app->config.assetsPath = argv[1];
#endif
        app->config.vulkanApiVersion = vk::ApiVersion12;

#if defined(__APPLE__)
        app->config.vulkanPortability = true;
#endif
    }

    // create sdl step timer
    {
        app->stepTimer = SDL_AddTimer(sdlTimerStepRateInMilliseconds, sdlTimerCallback, nullptr);
        assert(app->stepTimer != 0);
    }

    uint32_t version = app->context.enumerateInstanceVersion();
    std::cout << "vulkan version: " << version << std::endl; // version 4206592

    // create vulkan instance / create instance
    {
        // set extensions
        std::unordered_set<char const*> requiredExtensions = getSdlVulkanExtensions();
        if (app->config.vulkanPortability)
        {
            requiredExtensions.emplace(vk::KHRPortabilityEnumerationExtensionName);
        }
        std::vector<vk::ExtensionProperties> supportedExtensions = app->context.enumerateInstanceExtensionProperties();
        std::vector<char const*> enabledExtensions;
        for (auto& requiredExtension: requiredExtensions)
        {
            if (supportsExtension(&supportedExtensions, requiredExtension))
            {
                enabledExtensions.emplace_back(requiredExtension);
            }
        }

        // set layers
        std::vector<char const*> desiredLayers{"VK_LAYER_KHRONOS_validation"};
        std::vector<vk::LayerProperties> supportedLayers = app->context.enumerateInstanceLayerProperties();

        std::vector<char const*> enabledLayers;
        for (auto& desiredLayer: desiredLayers)
        {
            if (supportsLayer(&supportedLayers, desiredLayer))
            {
                enabledLayers.emplace_back(desiredLayer);
            }
        }

        vk::ApplicationInfo appInfo{
            .pApplicationName = "App",
            .applicationVersion = vk::makeApiVersion(1, 1, 0, 0),
            .pEngineName = nullptr,
            .engineVersion = vk::makeApiVersion(1, 1, 0, 0),
            .apiVersion = app->config.vulkanApiVersion
        };

        vk::InstanceCreateInfo info{
            .flags = app->config.vulkanPortability ? vk::InstanceCreateFlagBits::eEnumeratePortabilityKHR : (vk::InstanceCreateFlags)0,
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
            return SDL_APP_FAILURE;
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
        std::vector<vk::QueueFamilyProperties> families = app->physicalDevice.getQueueFamilyProperties();
        assert(!families.empty());

        if (families.size() > 1)
        {
            bool foundGraphics = false;
            bool foundTransfer = false;

            // see if we can get a separate transfer family
            // when do we want a separate transfer family?
            // let's say we have 4 queues, that all support transfer *and* graphics
            // then we want 1 graphics queue and separate 1 transfer queue
            for (int i = 0; i < families.size(); i++)
            {
                vk::QueueFamilyProperties family = families[i];
                if (!foundGraphics && family.queueFlags & vk::QueueFlagBits::eGraphics)
                {
                    app->queues.graphicsQueueFamilyIndex = i;
                    foundGraphics = true;
                }
                else if (!foundTransfer && family.queueFlags & vk::QueueFlagBits::eTransfer)
                {
                    app->queues.transferQueueFamilyIndex = i;
                    foundTransfer = true;
                }

                if (foundGraphics && foundTransfer)
                {
                    break;
                }
            }

            if (foundTransfer)
            {
                app->queues.separateTransferQueue = true;
            }
            else
            {
                // if we have 1 graphics queue, but haven't found a separate transfer queue,
                // then we want to see if the graphics queue supports transfer
                assert(families[app->queues.graphicsQueueFamilyIndex].queueFlags & vk::QueueFlagBits::eTransfer);
            }
        }
        else
        {
            // only one queue, so we assume it can handle everything we want to do
            app->queues.graphicsQueueFamilyIndex = 0;
            app->queues.transferQueueFamilyIndex = 0;

            vk::QueueFamilyProperties family = families[0];
            assert((family.queueFlags & vk::QueueFlagBits::eGraphics) && (family.queueFlags & vk::QueueFlagBits::eTransfer));
        }

        std::cout << "graphics queue family index: " << app->queues.graphicsQueueFamilyIndex << std::endl;
        std::cout << "transfer queue family index: " << app->queues.transferQueueFamilyIndex << std::endl;
    }

    // create logical device / create device
    {
        // we need to specify which queues need to be created
        float priority = 1.0f;
        vk::DeviceQueueCreateInfo graphicsQueue{
            .queueFamilyIndex = app->queues.graphicsQueueFamilyIndex,
            .queueCount = 1,
            .pQueuePriorities = &priority
        };

        std::vector<vk::DeviceQueueCreateInfo> queues{
            graphicsQueue
        };

        if (app->queues.separateTransferQueue)
        {
            vk::DeviceQueueCreateInfo transferQueue{
                .queueFamilyIndex = app->queues.transferQueueFamilyIndex,
                .queueCount = 1,
                .pQueuePriorities = &priority
            };
            queues.emplace_back(transferQueue);
        }

        std::vector<char const*> enabledLayers;
        std::vector<char const*> enabledExtensions{
            vk::KHRSwapchainExtensionName
        };
        if (app->config.vulkanPortability)
        {
            enabledExtensions.emplace_back(vk::KHRPortabilitySubsetExtensionName);
        }
        vk::PhysicalDeviceFeatures enabledFeatures;

        vk::DeviceCreateInfo info{
            .queueCreateInfoCount = (uint32_t)queues.size(),
            .pQueueCreateInfos = queues.data(),
            .enabledLayerCount = (uint32_t)enabledLayers.size(),
            .ppEnabledLayerNames = enabledLayers.data(),
            .enabledExtensionCount = (uint32_t)enabledExtensions.size(),
            .ppEnabledExtensionNames = enabledExtensions.data(),
            .pEnabledFeatures = &enabledFeatures
        };
        app->device = app->physicalDevice.createDevice(info).value();
    }

    // get queues
    {
        app->queues.graphicsQueue = app->device.getQueue(app->queues.graphicsQueueFamilyIndex, 0).value();
        if (app->queues.separateTransferQueue)
        {
            app->queues.transferQueue = app->device.getQueue(app->queues.transferQueueFamilyIndex, 0).value();
        }
    }

    // create command pools
    {
        vk::CommandPoolCreateInfo graphicsPoolInfo{
            .flags = vk::CommandPoolCreateFlagBits::eResetCommandBuffer,
            .queueFamilyIndex = app->queues.graphicsQueueFamilyIndex
        };
        app->graphicsCommandPool = app->device.createCommandPool(graphicsPoolInfo).value();

        if (app->queues.separateTransferQueue)
        {
            // also create a transfer pool
            vk::CommandPoolCreateInfo transferPoolInfo{
                .flags = vk::CommandPoolCreateFlagBits::eResetCommandBuffer,
                .queueFamilyIndex = app->queues.transferQueueFamilyIndex
            };
            app->transferCommandPool = app->device.createCommandPool(graphicsPoolInfo).value();
        }
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
        app->window = SDL_CreateWindow("vulkan sld loader experiment", 600, 400, windowFlags);
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

    // allocate command buffers for draw loop
    std::vector<vk::raii::CommandBuffer> commandBuffers;
    {
        vk::CommandBufferAllocateInfo bufferInfo{
            .commandPool = app->graphicsCommandPool,
            .level = vk::CommandBufferLevel::ePrimary,
            .commandBufferCount = maxConcurrentFrames
        };
        commandBuffers = app->device.allocateCommandBuffers(bufferInfo).value();
    }

    // create frame data for each frame
    {
        for (size_t i = 0; i < maxConcurrentFrames; i++)
        {
            // create fence in signaled state
            vk::raii::Fence fence = app->device.createFence(vk::FenceCreateInfo{.flags = vk::FenceCreateFlagBits::eSignaled}).value();

            FrameData frameData{
                .acquiringImage = app->device.createSemaphore({}).value(),
                .rendering = app->device.createSemaphore({}).value(),
                .commandBuffer = std::move(commandBuffers[i]),
                .gpuHasExecutedCommandBuffer = std::move(fence)
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
            .flags = vk::DescriptorPoolCreateFlagBits::eFreeDescriptorSet,
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
        // allocate transfer command buffer from graphics command pool if no separate transfer queue, otherwise use the transfer command pool
        vk::raii::CommandPool* pool = app->queues.separateTransferQueue ? &app->transferCommandPool : &app->graphicsCommandPool;

        app->uploadContext = UploadContext{
            .queues = &app->queues,
            .transferCommandBuffer = allocateCommandBuffer(&app->device, pool),
            // create fence in signaled state (signal means it is done)
            .gpuHasExecutedTransferCommandBuffer = app->device.createFence(vk::FenceCreateInfo{.flags = vk::FenceCreateFlagBits::eSignaled}).value(),
        };

        if (app->queues.separateTransferQueue)
        {
            // create semaphore to synchronize between transfer and graphics queue
            app->uploadContext.uploadCompleted = app->device.createSemaphore({}).value();

            // create graphics command buffer (for queue family ownership transfer)
            app->uploadContext.graphicsCommandBuffer = allocateCommandBuffer(&app->device, &app->graphicsCommandPool);

            // create fence to make sure we know it has finished executing when accessing (might be redundant in this case)
            app->uploadContext.gpuHasExecutedGraphicsCommandBuffer =
                app->device.createFence(vk::FenceCreateInfo{.flags = vk::FenceCreateFlagBits::eSignaled}).value();
        }
    }

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
            VertexData{.position{maxX, maxY, 0.0f}},
            VertexData{.position{minX, maxY, 0.0f}},
        };
        mesh.vertexCount = vertices.size();

        // indices
        std::vector<uint32_t> indices = std::vector<uint32_t>{
            0, 1, 2,
            0, 2, 3
        };
        mesh.indexCount = indices.size();
        mesh.indexType = vk::IndexType::eUint32;

        // create vertex buffer
        BufferInfo vertexBufferInfo{
            .size = vertices.size() * sizeof(VertexData),
            .gpuOnly = false,
            .usage = vk::BufferUsageFlagBits::eVertexBuffer
        };
        mesh.vertexBuffer = createBuffer(&app->device, *app->allocator, vertexBufferInfo);

        // create index buffer
        BufferInfo indexBufferInfo{
            .size = indices.size() * sizeof(uint32_t),
            .gpuOnly = false,
            .usage = vk::BufferUsageFlagBits::eIndexBuffer
        };
        mesh.indexBuffer = createBuffer(&app->device, *app->allocator, indexBufferInfo);

        // copy data from CPU to GPU
        copyToBuffer(&app->device, *app->allocator, &app->uploadContext, &mesh.vertexBuffer, vertices.data());
        copyToBuffer(&app->device, *app->allocator, &app->uploadContext, &mesh.indexBuffer, indices.data());

        app->mesh = std::move(mesh);
    }

    // create camera data buffer
    {
        BufferInfo descriptor{
            .size = sizeof(CameraData),
            .gpuOnly = false,
            .usage = vk::BufferUsageFlagBits::eUniformBuffer
        };
        app->cameraDataBuffer = createBuffer(&app->device, *app->allocator, descriptor);
        copyToBufferCpuVisible(&app->device, *app->allocator, &app->cameraDataBuffer, &app->cameraData);
    }

    // update descriptor sets (to point to the buffers with the relevant data)
    {
        vk::DescriptorBufferInfo bufferInfo{
            .buffer = app->cameraDataBuffer.buffer,
            .offset = 0,
            .range = vk::WholeSize
        };
        vk::WriteDescriptorSet cameraData{
            .dstSet = app->shader->descriptorSet,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = vk::DescriptorType::eUniformBuffer,
            .pBufferInfo = &bufferInfo
        };
        app->device.updateDescriptorSets(cameraData, {});
    }

    // import texture
    {
        TextureInfo info{};
        std::vector<unsigned char> data;
        bool result = importPng(app->config.assetsPath / "textures" / "terrain.png", &info, &data);
        assert(result);
        app->texture = createTexture(&app->device, *app->allocator, info);
        uploadToTexture(&app->device, *app->allocator, &app->uploadContext, &app->texture, &data);
    }

    // wait for the app to be done with any upload tasks
    {
        std::vector<vk::Fence> fences{app->uploadContext.gpuHasExecutedTransferCommandBuffer};
        if (app->queues.separateTransferQueue)
        {
            fences.emplace_back(app->uploadContext.gpuHasExecutedGraphicsCommandBuffer);
        }
        assert(app->device.waitForFences(fences, true, UINT64_MAX) == vk::Result::eSuccess);
    }

    return SDL_APP_CONTINUE;
}

void onDraw(App* app)
{
    FrameData* frame = &app->frames[app->currentFrame];

    // wait for the GPU to be done with the submitted command buffers of this frame data
    {
        // wait for the fence to be signaled
        assert(app->device.waitForFences(*frame->gpuHasExecutedCommandBuffer, true, std::numeric_limits<uint64_t>::max()) == vk::Result::eSuccess);
        app->device.resetFences(*frame->gpuHasExecutedCommandBuffer); // set back to unsignaled state
        frame->commandBuffer.reset();
    }

    // update camera transform / update camera data
    {
        float speed = 0.05f;
        float rotationSpeed = 1.0f;

        // update position
        auto const dx = static_cast<float>(isKeyPressed(app, SDLK_D) - isKeyPressed(app, SDLK_A));
        auto const dy = static_cast<float>(isKeyPressed(app, SDLK_E) - isKeyPressed(app, SDLK_Q));
        auto const dz = static_cast<float>(isKeyPressed(app, SDLK_W) - isKeyPressed(app, SDLK_S));
        glm::vec3 delta{dx, dy, dz};

        delta *= speed;

        // update rotation
        auto const dyaw = static_cast<float>(isKeyPressed(app, SDLK_RIGHT) - isKeyPressed(app, SDLK_LEFT));
        auto const dpitch = static_cast<float>(isKeyPressed(app, SDLK_UP) - isKeyPressed(app, SDLK_DOWN));
        auto const droll = static_cast<float>(isKeyPressed(app, SDLK_RIGHTBRACKET) - isKeyPressed(app, SDLK_LEFTBRACKET));
        app->cameraYaw += dyaw * rotationSpeed;
        app->cameraPitch += dpitch * rotationSpeed;
        app->cameraRoll += droll * rotationSpeed;

        glm::quat pitch = glm::angleAxis(glm::radians(-app->cameraPitch), glm::vec3(1, 0, 0));
        glm::quat yaw = glm::angleAxis(glm::radians(app->cameraYaw), glm::vec3(0, 1, 0));
        glm::quat roll = glm::angleAxis(glm::radians(app->cameraRoll), glm::vec3(0, 0, 1));
        glm::quat rotation = yaw * pitch * roll;

        Transform& c = app->cameraTransform;
        c.position += rotation * delta;
        c.rotation = rotation;
        c.scale = glm::vec3{1, 1, 1};

        //std::cout << "camera position: x: " << c.position.x << ", y: " << c.position.y << ", z: " << c.position.z << std::endl;

        // calculate
        vk::Extent2D size = app->surfaceCapabilities.currentExtent;
        glm::mat4 projection = glm::perspective(
            glm::radians(app->config.cameraFov),
            (float)size.width / (float)size.height,
            app->config.cameraNear, app->config.cameraFar);
        glm::mat4 view = glm::inverse(transformToMatrix(&app->cameraTransform));
        app->cameraData.viewProjection = projection * view;

        // copy data to buffer
        copyToBufferCpuVisible(&app->device, *app->allocator, &app->cameraDataBuffer, &app->cameraData);
    }

    // acquire image
    vk::AcquireNextImageInfoKHR info{
        .swapchain = app->swapchain,
        .timeout = UINT64_MAX,
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

    cmd->beginRenderPass(renderPassBeginInfo, vk::SubpassContents::eInline);

    // set dynamic viewport and scissor rect
    {
        vk::Viewport viewport{
            .x = 0,
            .y = (float)app->swapchainExtent.height,
            .width = (float)app->swapchainExtent.width,
            .height = -(float)app->swapchainExtent.height,
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
    }

    cmd->bindPipeline(vk::PipelineBindPoint::eGraphics, app->shader->pipeline);

    glm::mat4 localToWorld(1); // identity

    vkCmdPushConstants(**cmd, *app->shader->pipelineLayout, (VkShaderStageFlags)vk::ShaderStageFlagBits::eVertex, 0, sizeof(glm::mat4), &localToWorld);

    cmd->bindDescriptorSets(vk::PipelineBindPoint::eGraphics, app->shader->pipelineLayout, 0, *app->shader->descriptorSet, {});

    // draw mesh
    {
        cmd->bindIndexBuffer(*app->mesh.indexBuffer.buffer, 0, vk::IndexType::eUint32);
        cmd->bindVertexBuffers(0, *app->mesh.vertexBuffer.buffer, {0});
        cmd->drawIndexed(app->mesh.indexCount, 1, 0, 0, 0);
    }

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
    app->queues.graphicsQueue.submit(submitInfo, frame->gpuHasExecutedCommandBuffer);

    // present queue
    // get queue
    vk::PresentInfoKHR presentInfo{
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &*frame->rendering,
        .swapchainCount = 1,
        .pSwapchains = &*app->swapchain,
        .pImageIndices = &imageIndex
    };
    vk::Result presentResult = app->queues.graphicsQueue.presentKHR(presentInfo);
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

    if (*app->device != nullptr)
    {
        app->device.waitIdle();
    }
}
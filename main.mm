// let's add perlin noise
// how:
// https://developer.nvidia.com/gpugems/gpugems2/part-iii-high-quality-rendering/chapter-26-implementing-improved-perlin-noise

// we can do it on the GPU,
// but for now we can also implement it on CPU.

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <filesystem>

#import "Cocoa/Cocoa.h"
#import "MetalKit/MTKView.h"
#import "Metal/MTLDevice.h"
#import "Metal/MTLDrawable.h"
#import "simd/simd.h"

#include "lodepng.h"

#define GLM_ENABLE_EXPERIMENTAL
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_FORCE_LEFT_HANDED

#include "glm/glm.hpp"
#include "glm/detail/type_quat.hpp"
#include "glm/gtx/transform.hpp"
#include "glm/gtx/quaternion.hpp"

struct App;

void onLaunch(App*);

void onTerminate(App*);

void onDraw(App*);

void onSizeChanged(App*, CGSize size);

// implements NSApplicationDelegate protocol
// @interface means defining a subclass
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(unsafe_unretained, nonatomic) App* app;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    auto* app = (NSApplication*)notification.object;
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app activateIgnoringOtherApps:YES];

    onLaunch(_app);
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    onTerminate(_app);
}

- (bool)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}
@end

@interface MetalViewDelegate : NSObject <MTKViewDelegate>
@property(unsafe_unretained, nonatomic) App* app;
@end

@implementation MetalViewDelegate
- (void)drawInMTKView:(MTKView*)view {
    onDraw(_app);
}

- (void)mtkView:(nonnull MTKView*)view drawableSizeWillChange:(CGSize)size {
    onSizeChanged(_app, size);
}

@end

@interface TextViewDelegate : NSObject <NSTextViewDelegate>
@property(unsafe_unretained, nonatomic) App* app;
@end

struct AppConfig
{
    NSRect windowRect;
    NSSize windowMinSize;
    float sidepanelWidth;
    MTLClearColor clearColor;
    std::filesystem::path assetsPath;
    std::string fontCharacterMap;
    float cameraFov;
    float cameraNear;
    float cameraFar;
};

struct VertexData
{
    simd_float4 position;
    simd_float4 color;
    simd_float2 uv0;
};

struct CameraData
{
    glm::mat4 viewProjection;
};

struct InstanceData
{
    glm::mat4 localToWorld;
};

// sprite sheet
struct Sprite
{
    uint32_t x;
    uint32_t y;
    uint32_t width;
    uint32_t height;
};

struct TextureAtlas
{
    id <MTLTexture> texture;
    std::vector<Sprite> sprites;
};

struct Font
{
    std::unordered_map<char, size_t> map; // mapping of character to index in atlas
    TextureAtlas* atlas;
};

// a rect defined by min and max coordinates
struct RectMinMaxf
{
    float minX;
    float minY;
    float maxX;
    float maxY;
};

struct RectMinMaxi
{
    uint32_t minX;
    uint32_t minY;
    uint32_t maxX;
    uint32_t maxY;
};

// perlin noise
// https://en.wikipedia.org/wiki/Perlin_noise

// Function to linearly interpolate between a0 and a1
// Weight w should be in the range [0.0, 1.0]
[[nodiscard]] float perlinInterpolate(float a0, float a1, float w)
{
    // clamp
    if (0.0f > w)
    { return a0; }
    if (1.0f < w)
    { return a1; }

    // Use Smootherstep for an even smoother result with a second derivative equal to zero on boundaries:
    return (a1 - a0) * ((w * (w * 6.0f - 15.0f) + 10.0f) * w * w * w) + a0;
}

// Create pseudorandom direction vector
[[nodiscard]] glm::vec2 perlinRandomGradient(int ix, int iy)
{
    // No precomputed gradients mean this works for any number of grid coordinates
    const unsigned w = 8 * sizeof(unsigned);
    const unsigned s = w / 2; // rotation width
    unsigned a = ix, b = iy;
    a *= 3284157443;
    b ^= a << s | a >> (w - s);
    b *= 1911520717;
    a ^= b << s | b >> (w - s);
    a *= 2048419325;
    float random = (float)a * (3.14159265f / (float)~(~0u >> 1)); // in [0, 2*Pi]
    return {cos(random), sin(random)};
}

// Computes the dot product of the distance and gradient vectors.
[[nodiscard]] float perlinDotGridGradient(int ix, int iy, float x, float y)
{
    // Get gradient from integer coordinates
    glm::vec2 gradient = perlinRandomGradient(ix, iy);

    // Compute the distance vector
    float dx = x - (float)ix;
    float dy = y - (float)iy;

    // Compute the dot-product
    return (dx * gradient.x + dy * gradient.y);
}

// Compute Perlin noise at coordinates x, y
[[nodiscard]] float perlin(float x, float y)
{
    // Determine grid cell coordinates
    int x0 = (int)floor(x);
    int x1 = x0 + 1;
    int y0 = (int)floor(y);
    int y1 = y0 + 1;

    // Determine interpolation weights
    // Could also use higher order polynomial/s-curve here
    float sx = x - (float)x0;
    float sy = y - (float)y0;

    // Interpolate between grid point gradients
    float n0, n1, ix0, ix1, value;

    n0 = perlinDotGridGradient(x0, y0, x, y);
    n1 = perlinDotGridGradient(x1, y0, x, y);
    ix0 = perlinInterpolate(n0, n1, sx);

    n0 = perlinDotGridGradient(x0, y1, x, y);
    n1 = perlinDotGridGradient(x1, y1, x, y);
    ix1 = perlinInterpolate(n0, n1, sx);

    value = perlinInterpolate(ix0, ix1, sy);
    return value; // Will return in range -1 to 1. To make it in range 0 to 1, multiply by 0.5 and add 0.5
}

// texture coordinates: (top left = 0, 0) (bottom right = 1, 1)
RectMinMaxf getTextureCoordsForSprite(id <MTLTexture> texture, Sprite* sprite)
{
    float minX = (float)sprite->x / (float)texture.width;
    float minY = (float)sprite->y / (float)texture.height;
    float width = (float)sprite->width / (float)texture.width;
    float height = (float)sprite->height / (float)texture.height;

    return RectMinMaxf{
        .minX = minX,
        .minY = minY,
        .maxX = minX + width,
        .maxY = minY + height
    };
}

void createFontMap(Font* font, std::string const& characterMap)
{
    font->map.clear();
    size_t index = 0;
    for (char character: characterMap)
    {
        font->map[character] = index;
        index++;
    }
}

void createSprites(TextureAtlas* atlas, uint32_t spriteWidth, uint32_t spriteHeight, uint32_t xSpriteCount, uint32_t ySpriteCount)
{
    atlas->sprites.clear();
    atlas->sprites.resize(xSpriteCount * ySpriteCount);
    for (uint32_t xIndex = 0; xIndex < xSpriteCount; xIndex++)
    {
        for (uint32_t yIndex = 0; yIndex < ySpriteCount; yIndex++)
        {
            atlas->sprites[yIndex * xSpriteCount + xIndex] = Sprite{
                .x = xIndex * spriteWidth,
                .y = yIndex * spriteHeight,
                .width = spriteWidth,
                .height = spriteHeight
            };
        }
    }
}

struct Camera
{
    glm::vec3 position;
    glm::quat rotation;
    glm::vec3 scale;
};

struct Mesh
{
    id <MTLBuffer> vertexBuffer;
    id <MTLBuffer> indexBuffer;
    MTLIndexType indexType;
    size_t vertexCount;
    size_t indexCount;
};

struct App
{
    AppConfig* config;

    // window and view
    NSWindow* window;
    NSSplitView* splitView;
    MTKView* view;
    MetalViewDelegate* viewDelegate;
    NSView* sidepanel;
    TextViewDelegate* textViewDelegate;

    // metal objects
    id <MTLDevice> device;
    id <MTLLibrary> library; // shader library
    id <MTLCommandQueue> commandQueue;
    id <MTLDepthStencilState> depthStencilStateDefault;
    id <MTLRenderPipelineState> uiRenderPipelineState;
    id <MTLRenderPipelineState> threeDRenderPipelineState;
    id <MTLRenderPipelineState> terrainRenderPipelineState;

    // for clearing the depth buffer (https://stackoverflow.com/questions/58964035/in-metal-how-to-clear-the-depth-buffer-or-the-stencil-buffer)
    id <MTLDepthStencilState> depthStencilStateClear;
    id <MTLRenderPipelineState> clearDepthRenderPipelineState;

    // font rendering
    TextureAtlas fontAtlas;
    Font font;

    // axes
    Mesh axes;

    // 3D
    Camera camera;

    // terrain
    Mesh terrain;

    // silly timer
    float time = 0.0f;

    std::string currentText;
};

@implementation TextViewDelegate
- (void)textDidChange:(NSNotification*)obj {
    // https://developer.apple.com/documentation/appkit/nstextdidchangenotification
    auto* v = (NSTextView*)(obj.object);
    NSString* aa = [[v textStorage] string];
    _app->currentText = [aa cStringUsingEncoding:NSUTF8StringEncoding];
}
@end

Mesh createMesh(App* app, std::vector<VertexData>* vertices, std::vector<uint32_t>* indices)
{
    Mesh mesh{};

    // create vertex buffer
    MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
    mesh.vertexBuffer = [app->device newBufferWithBytes:vertices->data() length:vertices->size() * sizeof(VertexData) options:options];
    [mesh.vertexBuffer retain];
    mesh.vertexCount = vertices->size();

    // create index buffer
    mesh.indexBuffer = [app->device newBufferWithBytes:indices->data() length:indices->size() * sizeof(uint32_t) options:options];
    [mesh.indexBuffer retain];
    mesh.indexCount = indices->size();

    // 16 bits = 2 bytes
    // 32 bits = 4 bytes
    mesh.indexType = MTLIndexTypeUInt32;
    return mesh;
}

void destroyMesh(Mesh* mesh)
{
    assert(mesh->vertexBuffer != nullptr);
    assert(mesh->indexBuffer != nullptr);
    [mesh->vertexBuffer release];
    [mesh->indexBuffer release];
}

id <MTLRenderPipelineState> createRenderPipelineState(App* app, NSString* vertexFunctionName, NSString* fragmentFunctionName)
{
    // use function specialization to create shader variants
    id <MTLFunction> vertexFunction = [app->library newFunctionWithName:vertexFunctionName];
    assert(vertexFunction != nullptr);
    id <MTLFunction> fragmentFunction = [app->library newFunctionWithName:fragmentFunctionName];
    assert(fragmentFunction != nullptr);

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    id <CAMetalDrawable> drawable = [app->view currentDrawable];
    descriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;

    NSError* error = nullptr;
    id <MTLRenderPipelineState> renderPipelineState = [app->device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (error)
    {
        std::cout << [error.debugDescription cStringUsingEncoding:NSUTF8StringEncoding] << std::endl;
    }
    [vertexFunction release];
    [fragmentFunction release];
    return renderPipelineState;
}

[[nodiscard]] Mesh createAxes(App* app)
{
    std::vector<VertexData> vertices;
    std::vector<uint32_t> indices;
    std::vector<uint32_t> indicesTemplate{
        0, 1, 2, 1, 3, 2
    };

    float w = 0.01f; // width
    float l = 0.75f; // length

    simd_float4 red = {1, 0, 0, 1};
    simd_float4 green = {0, 1, 0, 1};
    simd_float4 blue = {0, 0, 1, 1};

    // positions
    vertices = {
        // x
        {.position = {l, -w, 0, 1}, .color = red},
        {.position = {l, +w, 0, 1}, .color = red},
        {.position = {0, -w, 0, 1}, .color = red},
        {.position = {0, +w, 0, 1}, .color = red},

        // y
        {.position = {-w, l, 0, 1}, .color = green},
        {.position = {+w, l, 0, 1}, .color = green},
        {.position = {-w, 0, 0, 1}, .color = green},
        {.position = {+w, 0, 0, 1}, .color = green},

        // z
        {.position = {-w, 0, l, 1}, .color = blue},
        {.position = {+w, 0, l, 1}, .color = blue},
        {.position = {-w, 0, 0, 1}, .color = blue},
        {.position = {+w, 0, 0, 1}, .color = blue},
    };

    for (int i = 0; i <= 2; i++)
    {
        // indices
        for (auto& index: indicesTemplate)
        {
            indices.emplace_back(index + 4 * i);
        }
    }

    return createMesh(app, &vertices, &indices);
}

[[nodiscard]] Mesh createTerrain(App* app, RectMinMaxf extents, uint32_t xSubdivisions, uint32_t zSubdivisions)
{
    float xSize = extents.maxX - extents.minX;
    float zSize = extents.maxY - extents.minY;
    uint32_t xCount = xSubdivisions + 1; // amount of vertices is subdivisions + 1
    uint32_t zCount = zSubdivisions + 1;
    std::vector<VertexData> vertices(xCount * zCount);

    float xStep = xSize / (float)xSubdivisions;
    float zStep = zSize / (float)zSubdivisions;

    for (uint32_t zIndex = 0; zIndex < zCount; zIndex++)
    {
        for (uint32_t xIndex = 0; xIndex < xCount; xIndex++)
        {
            float x = extents.minX + (float)xIndex * xStep;
            float z = extents.minY + (float)zIndex * zStep;

            float y = 0.1f * perlin(x * 8, z * 8);// + 0.1f * perlin(x * 4, z * 4);

            vertices[zIndex * xCount + xIndex] = VertexData{
                .position{x, y, z, 1}, .color{0, 1, 0, 1}
            };
        }
    }

    // triangle strip

    std::vector<uint32_t> indices{};
    for (uint32_t zIndex = 0; zIndex < zCount - 1; zIndex++)
    {
        for (uint32_t xIndex = 0; xIndex < xCount; xIndex++)
        {
            uint32_t offset = zIndex * xCount;
            indices.emplace_back(offset + xIndex);
            indices.emplace_back(offset + xIndex + xCount);
        }
        // reset primitive
        indices.emplace_back(0xFFFFFFFF);
    }

    return createMesh(app, &vertices, &indices);
}

void onLaunch(App* app)
{
    // create MTLDevice
    id <MTLDevice> device = MTLCreateSystemDefaultDevice();
    app->device = device;
    [device retain];

    // create window
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:app->config->windowRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setMinSize:app->config->windowMinSize];
    [window setTitle:@"bored_c"];
    [window setBackgroundColor:[NSColor blueColor]];
    [window center];
    app->window = window;
    [window retain];

    // create split view
    NSSplitView* splitView = [[NSSplitView alloc] initWithFrame:window.contentView.frame];
    [window setContentView:splitView];
    [splitView setVertical:YES];
    [splitView setDividerStyle:NSSplitViewDividerStylePaneSplitter];
    [splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    app->splitView = splitView;
    [splitView retain];

    // create metal kit view delegate
    {
        MetalViewDelegate* viewDelegate = [[MetalViewDelegate alloc] init];
        viewDelegate.app = app;
        app->viewDelegate = viewDelegate;
        [viewDelegate retain];
    }

    // create metal kit view and add to window
    {
        MTKView* view = [[MTKView alloc] initWithFrame:splitView.frame device:device];
        view.delegate = app->viewDelegate;
        view.clearColor = app->config->clearColor;
        view.depthStencilPixelFormat = MTLPixelFormatDepth16Unorm;
        [splitView addSubview:view];
        [window makeFirstResponder:view];
        app->view = view;
        [view retain];
    }

    // create text field delegate
    {
        TextViewDelegate* textViewDelegate = [[TextViewDelegate alloc] init];
        app->textViewDelegate = textViewDelegate;
        textViewDelegate.app = app;
        [textViewDelegate retain];
    }

    // create UI sidepanel
    {
        NSTextView* textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, app->config->sidepanelWidth, splitView.frame.size.height)];
        [textView setDelegate:app->textViewDelegate];
        [textView setAutomaticTextCompletionEnabled:NO];
        [textView setString:[[NSString alloc] initWithCString:app->currentText.c_str()]];
        [splitView addSubview:textView];
        app->sidepanel = textView;
        [textView retain];
    }

    [splitView adjustSubviews];

    // create command queue
    {
        id <MTLCommandQueue> commandQueue = [device newCommandQueue];
        app->commandQueue = commandQueue;
        [commandQueue retain];
    }

    // create depth stencil state
    {
        MTLDepthStencilDescriptor* descriptor = [[MTLDepthStencilDescriptor alloc] init];
        descriptor.depthWriteEnabled = YES;
        descriptor.depthCompareFunction = MTLCompareFunctionLess;
        id <MTLDepthStencilState> depthStencilState = [device newDepthStencilStateWithDescriptor:descriptor];
        app->depthStencilStateDefault = depthStencilState;
        [depthStencilState retain];
    }

    // create shader library
    {
        // read shader source from metal source file (Metal Shading Language, MSL)
        std::filesystem::path shadersPath = app->config->assetsPath / "shaders";
        std::vector<std::filesystem::path> paths{
            shadersPath / "shader_common.h",
            shadersPath / "shader_3d.metal",
            shadersPath / "shader_ui.metal",
            shadersPath / "shader_terrain.metal",
            shadersPath / "shader_clear_depth.metal"
        };
        std::stringstream buffer;
        for (std::filesystem::path& path: paths)
        {
            assert(std::filesystem::exists(path));
            std::ifstream file(path);
            buffer << file.rdbuf();
            buffer << "\n";
        }

        std::string s = buffer.str();
        NSString* shaderSource = [NSString stringWithCString:s.c_str()];

        NSError* error = nullptr;
        MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
        id <MTLLibrary> library = [device newLibraryWithSource:shaderSource options:options error:&error];
        if (error)
        {
            std::cout << [error.debugDescription cStringUsingEncoding:NSUTF8StringEncoding] << std::endl;
        }
        app->library = library;
        [library retain];
    }

    // create render pipeline states
    id <MTLRenderPipelineState> uiRenderPipelineState = createRenderPipelineState(app, @"ui_vertex", @"ui_fragment");
    [uiRenderPipelineState retain];
    app->uiRenderPipelineState = uiRenderPipelineState;

    id <MTLRenderPipelineState> threeDRenderPipelineState = createRenderPipelineState(app, @"main_vertex", @"main_fragment");
    [threeDRenderPipelineState retain];
    app->threeDRenderPipelineState = threeDRenderPipelineState;

    id <MTLRenderPipelineState> terrainRenderPipelineState = createRenderPipelineState(app, @"terrain_vertex", @"terrain_fragment");
    [terrainRenderPipelineState retain];
    app->terrainRenderPipelineState = terrainRenderPipelineState;

    // create depth clear pipeline state and depth stencil state
    {
        MTLDepthStencilDescriptor* depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionAlways; // always write to buffer, no depth test
        depthStencilDescriptor.depthWriteEnabled = YES;
        app->depthStencilStateClear = [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
        [app->depthStencilStateClear retain];

        MTLRenderPipelineDescriptor* renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDescriptor.depthAttachmentPixelFormat = app->view.depthStencilPixelFormat;
        renderPipelineDescriptor.vertexFunction = [app->library newFunctionWithName:@"depth_clear_vertex"];
        renderPipelineDescriptor.fragmentFunction = [app->library newFunctionWithName:@"depth_clear_fragment"];

        MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
        vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
        vertexDescriptor.attributes[0].offset = 0;
        vertexDescriptor.attributes[0].bufferIndex = 0;
        vertexDescriptor.layouts[0].stepRate = 1;
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
        vertexDescriptor.layouts[0].stride = 8;

        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;

        NSError* error;
        app->clearDepthRenderPipelineState = [device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];
        if (error)
        {
            std::cout << [error.debugDescription cStringUsingEncoding:NSUTF8StringEncoding] << std::endl;
            exit(1);
        }
        [app->clearDepthRenderPipelineState retain];
    }

    // import texture atlas
    {
        std::filesystem::path path = app->config->assetsPath / "texturemap.png";
        assert(std::filesystem::exists(path));

        // import png using lodepng
        std::vector<unsigned char> png;
        unsigned int width;
        unsigned int height;
        lodepng::State state;
        lodepng::load_file(png, path.c_str());

        std::vector<unsigned char> image;
        unsigned int error = lodepng::decode(image, width, height, state, png);
        if (error != 0)
        {
            std::cout << lodepng_error_text(error) << std::endl;
        }
        LodePNGColorMode color = state.info_png.color;
        assert(color.bitdepth == 8);
        assert(color.colortype == LCT_RGBA);
        MTLPixelFormat pixelFormat = MTLPixelFormatRGBA8Unorm;

        MTLTextureDescriptor* descriptor = [[MTLTextureDescriptor alloc] init];
        descriptor.width = width;
        descriptor.height = height;
        descriptor.pixelFormat = pixelFormat;
        descriptor.arrayLength = 1;
        descriptor.textureType = MTLTextureType2D;
        descriptor.usage = MTLTextureUsageShaderRead;
        id <MTLTexture> texture = [device newTextureWithDescriptor:descriptor];

        size_t strideInBytes = 4; // for each component 1 byte = 8 bits

        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [texture
            replaceRegion:region
            mipmapLevel:0
            slice:0
            withBytes:image.data()
            bytesPerRow:width * strideInBytes
            bytesPerImage:0]; // only single image

        app->fontAtlas.texture = texture;
        [texture retain];

        // create sprites from texture
        uint32_t spriteSize = 32;
        createSprites(&app->fontAtlas, spriteSize, spriteSize, width / spriteSize, height / spriteSize);
    }

    // create font
    {
        app->font.atlas = &app->fontAtlas;
        createFontMap(&app->font, app->config->fontCharacterMap);
    }

    // create axes
    app->axes = createAxes(app);

    // create terrain
    app->terrain = createTerrain(app, RectMinMaxf{-2, -2, 2, 2}, 100, 100);

    // make window active
    [window makeKeyAndOrderFront:NSApp];
}

void onTerminate(App* app)
{
    destroyMesh(&app->terrain);
    destroyMesh(&app->axes);
    [app->threeDRenderPipelineState release];
    [app->uiRenderPipelineState release];
    [app->depthStencilStateDefault release];
    [app->depthStencilStateClear release];
    [app->clearDepthRenderPipelineState release];
    [app->view release];
    [app->sidepanel release];
    [app->splitView release];
    [app->window release];
    [app->commandQueue release];
    [app->device release];
    [app->viewDelegate release];
}

void addQuad(App* app, std::vector<VertexData>* vertices, RectMinMaxf position, RectMinMaxf uv)
{
    VertexData topLeft{.position = {position.minX, position.minY, 0.0f, 1.0f}, .uv0 = {uv.minX, uv.minY}};
    VertexData topRight{.position = {position.maxX, position.minY, 0.0f, 1.0f}, .uv0 = {uv.maxX, uv.minY}};
    VertexData bottomLeft{.position = {position.minX, position.maxY, 0.0f, 1.0f}, .uv0 = {uv.minX, uv.maxY}};
    VertexData bottomRight{.position = {position.maxX, position.maxY, 0.0f, 1.0f}, .uv0 = {uv.maxX, uv.maxY}};
    vertices->emplace_back(topLeft);
    vertices->emplace_back(topRight);
    vertices->emplace_back(bottomRight);
    vertices->emplace_back(topLeft);
    vertices->emplace_back(bottomRight);
    vertices->emplace_back(bottomLeft);
}

RectMinMaxf getNormalizedPositionCoords(App* app, RectMinMaxi rect)
{
    // NDC: (top left = -1, 1), (bottom right = 1, -1)
    // z: from 0 (near) to 1 (far)
    CGSize viewSize = app->view.frame.size;
    return RectMinMaxf{
        .minX = -1.0f + (float)rect.minX / (float)viewSize.width * 2.0f,
        .minY = 1.0f - (float)rect.minY / (float)viewSize.height * 2.0f,
        .maxX = -1.0f + (float)rect.maxX / (float)viewSize.width * 2.0f,
        .maxY = 1.0f - (float)rect.maxY / (float)viewSize.height * 2.0f
    };
}

void drawText(App* app, std::string const& text, std::vector<VertexData>* vertices, uint32_t x, uint32_t y, uint32_t characterSize)
{
    vertices->reserve(vertices->size() + text.size() * 6);

    uint32_t i = 0;
    uint32_t line = 0;
    for (char character: text)
    {
        if (character == '\n')
        {
            line++;
            i = 0;
            continue;
        }
        size_t index = app->font.map[character];
        auto position = RectMinMaxi{
            .minX = x + i * characterSize,
            .minY = y + line * characterSize,
            .maxX = x + i * characterSize + characterSize,
            .maxY = y + line * characterSize + characterSize
        };
        RectMinMaxf positionCoords = getNormalizedPositionCoords(app, position);
        RectMinMaxf textureCoords = getTextureCoordsForSprite(app->fontAtlas.texture, &app->fontAtlas.sprites[index]);

        // create quad at pixel positions
        addQuad(app, vertices, positionCoords, textureCoords);

        i++;
    }
}

// sets: triangle fill mode, cull mode, depth stencil state and render pipeline state
void clearDepthBuffer(App* app, id <MTLRenderCommandEncoder> encoder)
{
    // Set up the pipeline and depth/stencil state to write a clear value to only the depth buffer.
    [encoder setDepthStencilState:app->depthStencilStateClear];
    [encoder setRenderPipelineState:app->clearDepthRenderPipelineState];

    // Normalized Device Coordinates of a tristrip we'll draw to clear the buffer
    // (the vertex shader set in pipelineDepthClear ignores all transforms and just passes these through)
    float clearCoords[8] = {
        -1, -1,
        1, -1,
        -1, 1,
        1, 1
    };

    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBytes:clearCoords length:sizeof(float) * 8 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

void onDraw(App* app)
{
    // main render loop
    MTLRenderPassDescriptor* renderPass = [app->view currentRenderPassDescriptor];
    assert(renderPass);
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;

    id <MTLCommandBuffer> cmd = [app->commandQueue commandBuffer];
    assert(cmd);
    id <MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:renderPass];
    assert(encoder);

    [encoder setFrontFacingWinding:MTLWindingClockwise];
    [encoder setCullMode:MTLCullModeBack];

    app->time += 0.025f;
    if (app->time > 2.0f * (float)pi)
    {
        app->time -= 2.0f * (float)pi;
    }

    // update camera position
    {
        Camera& camera = app->camera;

        float currentX = 0.05f * sin(app->time);
        float currentY = 0.4f + 0.05f * cos(app->time);

        camera.position = glm::vec3{currentX, currentY, -1.0f};
        camera.rotation = glm::quat{1.0f, 0.0f, 0.0f, 0.0f};
        camera.scale = glm::vec3{1, 1, 1};

        CGSize size = app->view.frame.size;
        glm::mat4 projection = glm::perspective(glm::radians(app->config->cameraFov),
                                                (float)(size.width / size.height),
                                                app->config->cameraNear, app->config->cameraFar);

        glm::mat4 translation = glm::translate(glm::mat4(1), camera.position);
        glm::mat4 rotation = glm::toMat4(camera.rotation);
        glm::mat4 scale = glm::scale(camera.scale);

        glm::mat4 cameraTransform = translation * rotation * scale;
        glm::mat4 view = glm::inverse(cameraTransform);

        CameraData cameraData{
            .viewProjection = projection * view
        };

        [encoder setVertexBytes:&cameraData length:sizeof(CameraData) atIndex:1];
    }

    // draw terrain
    {
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:app->terrainRenderPipelineState];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->fontAtlas.texture atIndex:0];
        std::vector<InstanceData> instances{
            {.localToWorld = glm::scale(glm::vec3(1))},
            {.localToWorld = glm::translate(glm::vec3(0, 0, 4))},
            {.localToWorld = glm::translate(glm::vec3(0.01f, 1, 0))}
        };
        [encoder setVertexBytes:instances.data() length:instances.size() * sizeof(InstanceData) atIndex:2];
        [encoder setVertexBuffer:app->terrain.vertexBuffer offset:0 atIndex:0];
        [encoder
            drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
            indexCount:app->terrain.indexCount
            indexType:app->terrain.indexType
            indexBuffer:app->terrain.indexBuffer
            indexBufferOffset:0
            instanceCount:instances.size()
            baseVertex:0
            baseInstance:0
        ];
    }

    // clear depth buffer
    clearDepthBuffer(app, encoder);

    // draw axes
    {
        [encoder setCullMode:MTLCullModeNone];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setRenderPipelineState:app->threeDRenderPipelineState];
        float angle = app->time;

        glm::vec3 t = glm::vec3(0, 0, 0);
        glm::quat r = glm::angleAxis(angle, glm::vec3(0, 1, 0));
        glm::vec3 s = glm::vec3(1, 1, 1);

        glm::mat4 translation = glm::translate(glm::mat4(1), t);
        glm::mat4 rotation = glm::toMat4(r);
        glm::mat4 scale = glm::scale(s);

        glm::mat4 transform = translation * rotation * scale;

        InstanceData instance{
            .localToWorld = glm::mat4(1) //transform
        };
        [encoder setVertexBytes:&instance length:sizeof(InstanceData) atIndex:2];
        [encoder setVertexBuffer:app->axes.vertexBuffer offset:0 atIndex:0];
        [encoder
            drawIndexedPrimitives:MTLPrimitiveTypeTriangle
            indexCount:app->axes.indexCount
            indexType:app->axes.indexType
            indexBuffer:app->axes.indexBuffer
            indexBufferOffset:0
            instanceCount:1
            baseVertex:0
            baseInstance:0
        ];
    }

    // draw UI

    [encoder setCullMode:MTLCullModeBack];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setRenderPipelineState:app->uiRenderPipelineState];
    [encoder setFragmentTexture:app->fontAtlas.texture atIndex:0];

    // draw text
    id <MTLBuffer> textBuffer;
    {
        // 6 vertices for each character in the string
        std::vector<VertexData> vertices;

        drawText(app, app->currentText, &vertices, 0, 0, 14);

        // create vertex buffer
        MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        textBuffer = [app->device newBufferWithBytes:vertices.data() length:vertices.size() * sizeof(VertexData) options:options];
        [textBuffer retain];

        // draw
        [encoder setVertexBuffer:textBuffer offset:0 atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
    }

    [encoder endEncoding];
    assert(app->view.currentDrawable);
    [cmd presentDrawable:app->view.currentDrawable];
    [cmd commit];

    [textBuffer release];
}

void onSizeChanged(App* app, CGSize size)
{

}

int main(int argc, char const* argv[])
{
    assert(argc == 2); // we expect one additional argument: the assets folder
    char const* assetsFolder = argv[1];

    std::string fontCharacterMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?/_[]{}'\"()&^#@%*=+-;:<>~`abcdefghijklmnopqrstuvwxyz0123456789 ";

    AppConfig config{
        .windowRect = NSMakeRect(0, 0, 1200, 800),
        .windowMinSize = NSSize{100.0f, 50.0f},
        .sidepanelWidth = 300.0f,
        .clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0),
        .assetsPath = argv[1],
        .fontCharacterMap = fontCharacterMap,
        .cameraFov = 60.0f,
        .cameraNear = 0.1f,
        .cameraFar = 1000.0f
    };

    // load text
    std::stringstream buffer;
    std::filesystem::path path(config.assetsPath / "shaders" / "shader_common.h");
    assert(std::filesystem::exists(path));
    std::ifstream file(path);
    buffer << file.rdbuf();

    App app{
        .config = &config,
        .currentText = buffer.str()
    };

    AppDelegate* appDelegate = [[AppDelegate alloc] init];
    appDelegate.app = &app;
    [appDelegate retain];
    NSApplication* nsApp = [NSApplication sharedApplication];
    [nsApp setDelegate:appDelegate];
    [nsApp run];
    [nsApp release];
    [appDelegate release];
    return 0;
}

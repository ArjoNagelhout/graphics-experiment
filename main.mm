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
    id <MTLDepthStencilState> depthStencilState;
    id <MTLRenderPipelineState> uiRenderPipelineState;
    id <MTLRenderPipelineState> threeDRenderPipelineState;

    // font rendering
    TextureAtlas fontAtlas;
    Font font;

    // axes
    Mesh axes;

    // 3D
    Camera camera;

    std::string currentText;
};

@implementation TextViewDelegate
// https://developer.apple.com/documentation/appkit/nstextdidchangenotification
- (void)textDidChange:(NSNotification*)obj
{
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

void createAxes(App* app)
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

    app->axes = createMesh(app, &vertices, &indices);
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
    [window setBackgroundColor:[NSColor systemPinkColor]];
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
        app->depthStencilState = depthStencilState;
        [depthStencilState retain];
    }

    // create shader library
    {
        // read shader source from metal source file (Metal Shading Language, MSL)
        std::filesystem::path shadersPath = app->config->assetsPath / "shaders";
        std::vector<std::filesystem::path> paths{
            shadersPath / "shader_common.h",
            shadersPath / "shader_3d.metal",
            shadersPath / "shader_ui.metal"
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
    createAxes(app);

    // make window active
    [window makeKeyAndOrderFront:NSApp];
}

void onTerminate(App* app)
{
    destroyMesh(&app->axes);
    [app->threeDRenderPipelineState release];
    [app->uiRenderPipelineState release];
    [app->depthStencilState release];
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

void onDraw(App* app)
{
    // main render loop
    MTLRenderPassDescriptor* renderPass = [app->view currentRenderPassDescriptor];
    assert(renderPass);

    id <MTLCommandBuffer> cmd = [app->commandQueue commandBuffer];
    assert(cmd);
    id <MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:renderPass];
    assert(encoder);

    [encoder setFrontFacingWinding:MTLWindingClockwise];
    [encoder setCullMode:MTLCullModeBack];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setDepthStencilState:app->depthStencilState];

    // update camera position
    {
        Camera& camera = app->camera;

        camera.position = glm::vec3{0.3f, 0.3f, -1.0f};
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

    [encoder setRenderPipelineState:app->threeDRenderPipelineState];

    // draw axes
    {
        [encoder setCullMode:MTLCullModeNone];
        glm::vec3 position = glm::vec3(0.0f, 0.0f, 0.0f);
        InstanceData instance{
            .localToWorld = glm::translate(glm::mat4(1), position)
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

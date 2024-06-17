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

#include "fmt/format.h"

struct App;

void onLaunch(App*);

void onTerminate(App*);

void onDraw(App*);

void onSizeChanged(App*, CGSize size);

uint32_t invalidIndex = 0xFFFFFFFF;

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

@interface MetalView : MTKView
@property(unsafe_unretained, nonatomic) App* app;
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

/*
 *  Summary:
 *    Virtual keycodes
 *
 *  Discussion:
 *    These constants are the virtual keycodes defined originally in
 *    Inside Mac Volume V, pg. V-191. They identify physical keys on a
 *    keyboard. Those constants with "ANSI" in the name are labeled
 *    according to the key position on an ANSI-standard US keyboard.
 *    For example, kVK_ANSI_A indicates the virtual keycode for the key
 *    with the letter 'A' in the US keyboard layout. Other keyboard
 *    layouts may have the 'A' key label on a different physical key;
 *    in this case, pressing 'A' will generate a different virtual
 *    keycode.
 *
 *    retrieved from /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h
 */
enum class CocoaKeyCode : unsigned short
{
    kVK_ANSI_A = 0x00,
    kVK_ANSI_S = 0x01,
    kVK_ANSI_D = 0x02,
    kVK_ANSI_F = 0x03,
    kVK_ANSI_H = 0x04,
    kVK_ANSI_G = 0x05,
    kVK_ANSI_Z = 0x06,
    kVK_ANSI_X = 0x07,
    kVK_ANSI_C = 0x08,
    kVK_ANSI_V = 0x09,
    kVK_ANSI_B = 0x0B,
    kVK_ANSI_Q = 0x0C,
    kVK_ANSI_W = 0x0D,
    kVK_ANSI_E = 0x0E,
    kVK_ANSI_R = 0x0F,
    kVK_ANSI_Y = 0x10,
    kVK_ANSI_T = 0x11,
    kVK_ANSI_1 = 0x12,
    kVK_ANSI_2 = 0x13,
    kVK_ANSI_3 = 0x14,
    kVK_ANSI_4 = 0x15,
    kVK_ANSI_6 = 0x16,
    kVK_ANSI_5 = 0x17,
    kVK_ANSI_Equal = 0x18,
    kVK_ANSI_9 = 0x19,
    kVK_ANSI_7 = 0x1A,
    kVK_ANSI_Minus = 0x1B,
    kVK_ANSI_8 = 0x1C,
    kVK_ANSI_0 = 0x1D,
    kVK_ANSI_RightBracket = 0x1E,
    kVK_ANSI_O = 0x1F,
    kVK_ANSI_U = 0x20,
    kVK_ANSI_LeftBracket = 0x21,
    kVK_ANSI_I = 0x22,
    kVK_ANSI_P = 0x23,
    kVK_ANSI_L = 0x25,
    kVK_ANSI_J = 0x26,
    kVK_ANSI_Quote = 0x27,
    kVK_ANSI_K = 0x28,
    kVK_ANSI_Semicolon = 0x29,
    kVK_ANSI_Backslash = 0x2A,
    kVK_ANSI_Comma = 0x2B,
    kVK_ANSI_Slash = 0x2C,
    kVK_ANSI_N = 0x2D,
    kVK_ANSI_M = 0x2E,
    kVK_ANSI_Period = 0x2F,
    kVK_ANSI_Grave = 0x32,
    kVK_ANSI_KeypadDecimal = 0x41,
    kVK_ANSI_KeypadMultiply = 0x43,
    kVK_ANSI_KeypadPlus = 0x45,
    kVK_ANSI_KeypadClear = 0x47,
    kVK_ANSI_KeypadDivide = 0x4B,
    kVK_ANSI_KeypadEnter = 0x4C,
    kVK_ANSI_KeypadMinus = 0x4E,
    kVK_ANSI_KeypadEquals = 0x51,
    kVK_ANSI_Keypad0 = 0x52,
    kVK_ANSI_Keypad1 = 0x53,
    kVK_ANSI_Keypad2 = 0x54,
    kVK_ANSI_Keypad3 = 0x55,
    kVK_ANSI_Keypad4 = 0x56,
    kVK_ANSI_Keypad5 = 0x57,
    kVK_ANSI_Keypad6 = 0x58,
    kVK_ANSI_Keypad7 = 0x59,
    kVK_ANSI_Keypad8 = 0x5B,
    kVK_ANSI_Keypad9 = 0x5C,
    /* keycodes for keys that are independent of keyboard layout*/
    kVK_Return = 0x24,
    kVK_Tab = 0x30,
    kVK_Space = 0x31,
    kVK_Delete = 0x33,
    kVK_Escape = 0x35,
    kVK_Command = 0x37,
    kVK_Shift = 0x38,
    kVK_CapsLock = 0x39,
    kVK_Option = 0x3A,
    kVK_Control = 0x3B,
    kVK_RightCommand = 0x36,
    kVK_RightShift = 0x3C,
    kVK_RightOption = 0x3D,
    kVK_RightControl = 0x3E,
    kVK_Function = 0x3F,
    kVK_F17 = 0x40,
    kVK_VolumeUp = 0x48,
    kVK_VolumeDown = 0x49,
    kVK_Mute = 0x4A,
    kVK_F18 = 0x4F,
    kVK_F19 = 0x50,
    kVK_F20 = 0x5A,
    kVK_F5 = 0x60,
    kVK_F6 = 0x61,
    kVK_F7 = 0x62,
    kVK_F3 = 0x63,
    kVK_F8 = 0x64,
    kVK_F9 = 0x65,
    kVK_F11 = 0x67,
    kVK_F13 = 0x69,
    kVK_F16 = 0x6A,
    kVK_F14 = 0x6B,
    kVK_F10 = 0x6D,
    kVK_F12 = 0x6F,
    kVK_F15 = 0x71,
    kVK_Help = 0x72,
    kVK_Home = 0x73,
    kVK_PageUp = 0x74,
    kVK_ForwardDelete = 0x75,
    kVK_F4 = 0x76,
    kVK_End = 0x77,
    kVK_F2 = 0x78,
    kVK_PageDown = 0x79,
    kVK_F1 = 0x7A,
    kVK_LeftArrow = 0x7B,
    kVK_RightArrow = 0x7C,
    kVK_DownArrow = 0x7D,
    kVK_UpArrow = 0x7E,

    Last = kVK_UpArrow
};

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
    uint32_t shadowMapSize;
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

struct LightData
{
    glm::mat4 lightSpace;
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
RectMinMaxf spriteToTextureCoords(id <MTLTexture> texture, Sprite* sprite)
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

struct Mesh
{
    id <MTLBuffer> vertexBuffer;
    id <MTLBuffer> indexBuffer;
    MTLIndexType indexType;
    size_t vertexCount;
    size_t indexCount;
    MTLPrimitiveType primitiveType;
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

struct App
{
    AppConfig* config;

    // window and view
    NSWindow* window;
    NSSplitView* splitView;
    MetalView* view;
    MetalViewDelegate* viewDelegate;
    NSView* sidepanel;
    TextViewDelegate* textViewDelegate;

    // metal objects
    id <MTLDevice> device;
    id <MTLLibrary> library; // shader library
    id <MTLCommandQueue> commandQueue;
    id <MTLDepthStencilState> depthStencilStateDefault;

    // shaders
    id <MTLRenderPipelineState> uiRenderPipelineState;
    id <MTLRenderPipelineState> threeDRenderPipelineState;
    id <MTLRenderPipelineState> terrainRenderPipelineState;
    id <MTLRenderPipelineState> threeDTexturedRenderPipelineState;
    id <MTLRenderPipelineState> shadowRenderPipelineState;

    // for clearing the depth buffer (https://stackoverflow.com/questions/58964035/in-metal-how-to-clear-the-depth-buffer-or-the-stencil-buffer)
    id <MTLDepthStencilState> depthStencilStateClear;
    id <MTLRenderPipelineState> clearDepthRenderPipelineState;

    // font rendering
    TextureAtlas fontAtlas;
    Font font;

    // camera
    Transform cameraTransform;
    float cameraYaw;
    float cameraPitch;
    float cameraRoll;

    // primitives
    Mesh cube;

    // axes
    Mesh axes;

    // terrain
    Mesh terrain;
    id <MTLTexture> terrainTexture;

    // shadow and lighting
    Transform sunTransform;
    id <MTLTexture> shadowMap;

    // silly periodic timer
    float time = 0.0f;

    std::string currentText;

    // icons
    id <MTLTexture> iconSunTexture;

    // input
    std::bitset<static_cast<size_t>(CocoaKeyCode::Last)> keys;
};

@implementation TextViewDelegate
- (void)textDidChange:(NSNotification*)obj {
    // https://developer.apple.com/documentation/appkit/nstextdidchangenotification
    auto* v = (NSTextView*)(obj.object);
    NSString* aa = [[v textStorage] string];
    _app->currentText = [aa cStringUsingEncoding:NSUTF8StringEncoding];
}
@end

@implementation MetalView

// ui responder
- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent*)event
{
    _app->keys[event.keyCode] = true;
}

-(void)keyUp:(NSEvent*)event
{
    _app->keys[event.keyCode] = false;
}
@end

[[nodiscard]] bool isKeyPressed(App* app, CocoaKeyCode keyCode)
{
    return app->keys[static_cast<unsigned short>(keyCode)];
}

Mesh createMesh(App* app, std::vector<VertexData>* vertices, std::vector<uint32_t>* indices, MTLPrimitiveType primitiveType)
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
    mesh.primitiveType = primitiveType;
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
        {.position = {0, -w, l, 1}, .color = blue},
        {.position = {0, +w, l, 1}, .color = blue},
        {.position = {0, -w, 0, 1}, .color = blue},
        {.position = {0, +w, 0, 1}, .color = blue},
    };

    for (int i = 0; i <= 2; i++)
    {
        // indices
        for (auto& index: indicesTemplate)
        {
            indices.emplace_back(index + 4 * i);
        }
    }

    return createMesh(app, &vertices, &indices, MTLPrimitiveTypeTriangle);
}

[[nodiscard]] Mesh createCube(App* app)
{
    float uvmin = 0.0f;
    float uvmax = 1.0f;
    float s = 0.5f;
    std::vector<VertexData> vertices{
        {.position{-s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // A 0
        {.position{+s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // B 1
        {.position{+s, +s, -s, 1}, .uv0{uvmax, uvmax}},  // C 2
        {.position{-s, +s, -s, 1}, .uv0{uvmin, uvmax}},  // D 3
        {.position{-s, -s, +s, 1}, .uv0{uvmin, uvmin}},  // E 4
        {.position{+s, -s, +s, 1}, .uv0{uvmax, uvmin}},  // F 5
        {.position{+s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // G 6
        {.position{-s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // H 7
        {.position{-s, +s, -s, 1}, .uv0{uvmin, uvmin}},  // D 8
        {.position{-s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // A 9
        {.position{-s, -s, +s, 1}, .uv0{uvmax, uvmax}},  // E 10
        {.position{-s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // H 11
        {.position{+s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // B 12
        {.position{+s, +s, -s, 1}, .uv0{uvmax, uvmin}},  // C 13
        {.position{+s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // G 14
        {.position{+s, -s, +s, 1}, .uv0{uvmin, uvmax}},  // F 15
        {.position{-s, -s, -s, 1}, .uv0{uvmin, uvmin}},  // A 16
        {.position{+s, -s, -s, 1}, .uv0{uvmax, uvmin}},  // B 17
        {.position{+s, -s, +s, 1}, .uv0{uvmax, uvmax}},  // F 18
        {.position{-s, -s, +s, 1}, .uv0{uvmin, uvmax}},  // E 19
        {.position{+s, +s, -s, 1}, .uv0{uvmin, uvmin}},  // C 20
        {.position{-s, +s, -s, 1}, .uv0{uvmax, uvmin}},  // D 21
        {.position{-s, +s, +s, 1}, .uv0{uvmax, uvmax}},  // H 22
        {.position{+s, +s, +s, 1}, .uv0{uvmin, uvmax}},  // G 23
    };
    std::vector<uint32_t> indices{
        // front and back
        0, 3, 2,
        2, 1, 0,
        4, 5, 6,
        6, 7 ,4,
        // left and right
        11, 8, 9,
        9, 10, 11,
        12, 13, 14,
        14, 15, 12,
        // bottom and top
        16, 17, 18,
        18, 19, 16,
        20, 21, 22,
        22, 23, 20
    };

    return createMesh(app, &vertices, &indices, MTLPrimitiveTypeTriangle);
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

            float y = 0.1f * perlin(x * 8, z * 8) + 2.0f * perlin(x / 2, z / 2) + 3.0f * perlin(x / 9, z / 12);

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
        indices.emplace_back(invalidIndex);
    }

    return createMesh(app, &vertices, &indices, MTLPrimitiveTypeTriangleStrip);
}

id <MTLTexture> importTexture(App* app, std::filesystem::path const& path)
{
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
        exit(1);
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
    id <MTLTexture> texture = [app->device newTextureWithDescriptor:descriptor];

    size_t strideInBytes = 4; // for each component 1 byte = 8 bits

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [texture
        replaceRegion:region
        mipmapLevel:0
        slice:0
        withBytes:image.data()
        bytesPerRow:width * strideInBytes
        bytesPerImage:0]; // only single image

    return texture;
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
        MetalView* view = [[MetalView alloc] initWithFrame:splitView.frame device:device];
        view.app = app;
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
            shadersPath / "shader_clear_depth.metal",
            shadersPath / "shader_3d_textured.metal",
            shadersPath / "shader_shadow.metal"
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
    app->uiRenderPipelineState = createRenderPipelineState(app, @"ui_vertex", @"ui_fragment");
    app->threeDRenderPipelineState = createRenderPipelineState(app, @"main_vertex", @"main_fragment");
    app->terrainRenderPipelineState = createRenderPipelineState(app, @"terrain_vertex", @"terrain_fragment");
    app->threeDTexturedRenderPipelineState = createRenderPipelineState(app, @"textured_vertex", @"textured_fragment");
    app->shadowRenderPipelineState = createRenderPipelineState(app, @"shadow_vertex", @"shadow_fragment");

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
        app->fontAtlas.texture = importTexture(app, path);

        // create sprites from texture
        uint32_t spriteSize = 32;
        uint32_t width = app->fontAtlas.texture.width;
        uint32_t height = app->fontAtlas.texture.height;
        createSprites(&app->fontAtlas, spriteSize, spriteSize, width / spriteSize, height / spriteSize);
    }

    // import icons
    {
        app->iconSunTexture = importTexture(app, app->config->assetsPath / "sun.png");
        [app->iconSunTexture retain];
    }

    // create shadow map
    {
        MTLTextureDescriptor* descriptor = [[MTLTextureDescriptor alloc] init];
        uint32_t size = app->config->shadowMapSize;
        descriptor.width = size;
        descriptor.height = size;
        descriptor.pixelFormat = MTLPixelFormatDepth16Unorm;
        descriptor.textureType = MTLTextureType2D;
        descriptor.arrayLength = 1;
        descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        app->shadowMap = [device newTextureWithDescriptor:descriptor];
        [app->shadowMap retain];
    }

    // create font
    {
        app->font.atlas = &app->fontAtlas;
        createFontMap(&app->font, app->config->fontCharacterMap);
    }

    // create cube
    app->cube = createCube(app);

    // create axes
    app->axes = createAxes(app);

    // set camera transform
    app->cameraTransform = {
        .position = glm::vec3(-1.0f, 1.0f, 1.0f),
        .rotation = glm::quat(1, 0, 0, 0),
        .scale = glm::vec3(1, 1, 1)
    };

    // create terrain
    app->terrain = createTerrain(app, RectMinMaxf{-20, -20, 20, 20}, 1000, 1000);
    app->terrainTexture = importTexture(app, app->config->assetsPath / "terrain.png");
    [app->terrainTexture retain];

    // make window active
    [window makeKeyAndOrderFront:NSApp];
}

void onTerminate(App* app)
{
    destroyMesh(&app->terrain);
    destroyMesh(&app->axes);
    destroyMesh(&app->cube);

    // shaders
    [app->threeDRenderPipelineState release];
    [app->uiRenderPipelineState release];
    [app->threeDTexturedRenderPipelineState release];
    [app->clearDepthRenderPipelineState release];
    [app->shadowRenderPipelineState release];

    [app->depthStencilStateDefault release];
    [app->depthStencilStateClear release];

    [app->fontAtlas.texture release];
    [app->terrainTexture release];
    [app->shadowMap release];

    // icons
    [app->iconSunTexture release];

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

// from pixel coordinates to NDC (normalized device coordinates)
RectMinMaxf pixelCoordsToNDC(App* app, RectMinMaxi rect)
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

void addText(App* app, std::string const& text, std::vector<VertexData>* vertices, uint32_t x, uint32_t y, uint32_t characterSize)
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
        RectMinMaxf positionCoords = pixelCoordsToNDC(app, position);
        RectMinMaxf textureCoords = spriteToTextureCoords(app->fontAtlas.texture, &app->fontAtlas.sprites[index]);

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

void drawScene(App* app, id <MTLRenderCommandEncoder> encoder, glm::mat4 viewProjection, id <MTLRenderPipelineState> pipelineOverride)
{
    assert(encoder != nullptr);

    // set camera data
    {
        CameraData cameraData{viewProjection};
        [encoder setVertexBytes:&cameraData length:sizeof(CameraData) atIndex:1];
    }

    // draw terrain
    {
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:pipelineOverride == nullptr ? app->terrainRenderPipelineState : pipelineOverride];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->terrainTexture atIndex:0];
        std::vector<InstanceData> instances{
            {.localToWorld = glm::rotate(glm::radians(45.0f), glm::vec3(0, 1, 0))},
//            {.localToWorld = glm::scale(glm::translate(glm::vec3(0, 0, 9)), glm::vec3(0.5f))},
//            {.localToWorld = glm::translate(glm::vec3(9, 0, 9))},
//            {.localToWorld = glm::translate(glm::vec3(9, 0, 0))},
        };
        [encoder setVertexBytes:instances.data() length:instances.size() * sizeof(InstanceData) atIndex:2];
        [encoder setVertexBuffer:app->terrain.vertexBuffer offset:0 atIndex:0];
        [encoder
            drawIndexedPrimitives:app->terrain.primitiveType
            indexCount:app->terrain.indexCount
            indexType:app->terrain.indexType
            indexBuffer:app->terrain.indexBuffer
            indexBufferOffset:0
            instanceCount:instances.size()
            baseVertex:0
            baseInstance:0
        ];
    }
}

void drawAxes(App* app, id <MTLRenderCommandEncoder> encoder, glm::mat4 transform)
{
    [encoder setCullMode:MTLCullModeNone];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setDepthStencilState:app->depthStencilStateDefault];
    [encoder setRenderPipelineState:app->threeDRenderPipelineState];
    InstanceData instance{
        .localToWorld = transform
    };
    [encoder setVertexBytes:&instance length:sizeof(InstanceData) atIndex:2];
    [encoder setVertexBuffer:app->axes.vertexBuffer offset:0 atIndex:0];
    [encoder
        drawIndexedPrimitives:app->axes.primitiveType
        indexCount:app->axes.indexCount
        indexType:app->axes.indexType
        indexBuffer:app->axes.indexBuffer
        indexBufferOffset:0
        instanceCount:1
        baseVertex:0
        baseInstance:0
    ];
}

// main render loop
void onDraw(App* app)
{
    app->time += 0.025f;
    if (app->time > 2.0f * (float)pi)
    {
        app->time -= 2.0f * (float)pi;
    }

    // update sun and camera transform
    {
        float speed = 0.1f;
        float rotationSpeed = 2.0f;

        // update position
        auto const dx = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_ANSI_D) - isKeyPressed(app, CocoaKeyCode::kVK_ANSI_A));
        auto const dy = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_ANSI_E) - isKeyPressed(app, CocoaKeyCode::kVK_ANSI_Q));
        auto const dz = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_ANSI_W) - isKeyPressed(app, CocoaKeyCode::kVK_ANSI_S));
        glm::vec3 delta{dx, dy, dz};

        delta *= speed;

        //  update rotation
        auto const dyaw = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_RightArrow) - isKeyPressed(app, CocoaKeyCode::kVK_LeftArrow));
        auto const dpitch = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_UpArrow) - isKeyPressed(app, CocoaKeyCode::kVK_DownArrow));
        auto const droll = static_cast<float>(isKeyPressed(app, CocoaKeyCode::kVK_ANSI_RightBracket) - isKeyPressed(app, CocoaKeyCode::kVK_ANSI_LeftBracket));
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

        float currentX = 4.0f + 0.5f * sin(app->time);
        float currentY = 5.0f + 0.5f * cos(app->time);
        float currentRot = 30.0f + 20.0f * sin(app->time);
        app->sunTransform = {
            .position = glm::vec3{currentX, currentY, -20.0f},
            .rotation = glm::quat{glm::vec3{glm::radians(currentRot), 0, 0}},
            .scale = glm::vec3{1, 1, 1}
        };
    }

    LightData lightData{};

    // shadow pass
    {
        MTLRenderPassDescriptor* shadowPass = [[MTLRenderPassDescriptor alloc] init];
        MTLRenderPassDepthAttachmentDescriptor* depth = shadowPass.depthAttachment;
        depth.loadAction = MTLLoadActionClear;
        depth.storeAction = MTLStoreActionStore;
        depth.texture = app->shadowMap;

        id <MTLCommandBuffer> cmd = [app->commandQueue commandBuffer];
        assert(cmd);
        id <MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:shadowPass];
        assert(encoder);

        // draw scene to the shadow map, from the view of the sun
        glm::mat4 projection = glm::ortho(-30.0f, 30.0f,-20.0f, 20.0f, 1.0f, 50.0f);
        glm::mat4 view = glm::inverse(transformToMatrix(&app->sunTransform));
        lightData.lightSpace = projection * view;
        drawScene(app, encoder, lightData.lightSpace, app->shadowRenderPipelineState);

        [encoder endEncoding];
        [cmd commit];
    }

    // main pass
    {
        MTLRenderPassDescriptor* renderPass = [app->view currentRenderPassDescriptor];
        assert(renderPass);
        renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;

        id <MTLCommandBuffer> cmd = [app->commandQueue commandBuffer];
        assert(cmd);
        id <MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:renderPass];
        assert(encoder);

        [encoder setFrontFacingWinding:MTLWindingClockwise];
        [encoder setCullMode:MTLCullModeBack];

        // calculate camera matrix and draw scene
        {
            CGSize size = app->view.frame.size;
            glm::mat4 projection = glm::perspective(glm::radians(app->config->cameraFov),
                                                    (float)(size.width / size.height),
                                                    app->config->cameraNear, app->config->cameraFar);
            glm::mat4 view = glm::inverse(transformToMatrix(&app->cameraTransform));

            [encoder setFragmentTexture:app->shadowMap atIndex:1];
            [encoder setVertexBytes:&lightData length:sizeof(LightData) atIndex:3];

            drawScene(app, encoder, projection * view, nullptr);
        }

        // clear depth buffer
        clearDepthBuffer(app, encoder);

        // draw cube at sun position
        {
            [encoder setCullMode:MTLCullModeNone];
            [encoder setTriangleFillMode:MTLTriangleFillModeFill];
            [encoder setDepthStencilState:app->depthStencilStateDefault];
            [encoder setRenderPipelineState:app->threeDTexturedRenderPipelineState];
            [encoder setFragmentTexture:app->iconSunTexture atIndex:0];

            InstanceData instance{
                .localToWorld = glm::scale(transformToMatrix(&app->sunTransform), glm::vec3(0.25f))
            };
            [encoder setVertexBytes:&instance length:sizeof(InstanceData) atIndex:2];
            [encoder setVertexBuffer:app->cube.vertexBuffer offset:0 atIndex:0];
            [encoder
                drawIndexedPrimitives:app->cube.primitiveType
                indexCount:app->cube.indexCount
                indexType:app->cube.indexType
                indexBuffer:app->cube.indexBuffer
                indexBufferOffset:0
                instanceCount:1
                baseVertex:0
                baseInstance:0
            ];
        }

        // draw axes at sun position
        drawAxes(app, encoder, transformToMatrix(&app->sunTransform));

        // draw axes at origin
        drawAxes(app, encoder, glm::mat4(1));

        // draw shadow map (2D, on-screen)
        id <MTLBuffer> shadowMapVertexBuffer;
        {
            [encoder setCullMode:MTLCullModeBack];
            [encoder setTriangleFillMode:MTLTriangleFillModeFill];
            [encoder setRenderPipelineState:app->uiRenderPipelineState];
            [encoder setFragmentTexture:app->shadowMap atIndex:0];

            RectMinMaxf position = pixelCoordsToNDC(app, {0, 28, 400, 400});
            std::vector<VertexData> vertices;
            addQuad(app, &vertices, position, RectMinMaxf{0, 0, 1, 1});

            // create vertex buffer
            MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
            shadowMapVertexBuffer = [app->device newBufferWithBytes:vertices.data() length:vertices.size() * sizeof(VertexData) options:options];
            [shadowMapVertexBuffer retain];

            // draw shadow map
            [encoder setVertexBuffer:shadowMapVertexBuffer offset:0 atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
        }

        // draw text (2D, on-screen)
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:app->uiRenderPipelineState];
        [encoder setFragmentTexture:app->fontAtlas.texture atIndex:0];

        id <MTLBuffer> textBuffer;
        {
            std::vector<VertexData> vertices;

            glm::vec3* pos = &app->cameraTransform.position;
            std::string a = fmt::format("camera ({0:+.3f}, {1:+.3f}, {2:+.3f})", pos->x, pos->y, pos->z);
            addText(app, a, &vertices, 0, 0, 14);

            pos = &app->sunTransform.position;
            std::string b = fmt::format("sun ({0:+.3f}, {1:+.3f}, {2:+.3f})", pos->x, pos->y, pos->z);
            addText(app, b, &vertices, 0, 14, 14);

            addText(app, app->currentText, &vertices, 600, 14, 12);

            // create vertex buffer
            MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
            textBuffer = [app->device newBufferWithBytes:vertices.data() length:vertices.size() * sizeof(VertexData) options:options];
            [textBuffer retain];

            // draw text
            [encoder setVertexBuffer:textBuffer offset:0 atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
        }

        [encoder endEncoding];
        assert(app->view.currentDrawable);
        [cmd presentDrawable:app->view.currentDrawable];
        [cmd commit];

        [textBuffer release];
        [shadowMapVertexBuffer release];
    }
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
        .clearColor = MTLClearColorMake(0, 1, 1, 1.0),
        .assetsPath = argv[1],
        .fontCharacterMap = fontCharacterMap,
        .cameraFov = 60.0f,
        .cameraNear = 0.1f,
        .cameraFar = 1000.0f,
        .shadowMapSize = 4096
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

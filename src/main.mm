// architecture can be done later, first focus on features
// (in a way that it can be easily refactored into a better structure)
//
// some things I could implement:
//
// - [X] blinn phong shading
// - [X] fog
// - [X] skybox (panoramic / 360 spherical)
// - [X] compilation of shader variants
// - [X] gltf import
// - [ ] gltf import with stride of 16 bytes instead of 12 for vector3, this is better for alignment. packed_float3 is not ideal.

// rendering:
// - [ ] PBR shading (Epic Games and Disney PBR)
// - [ ] deferred rendering
// - [ ] animation / rigging of a mesh, skinning
// - [ ] multiple light sources (point light, directional light, colored lights) probably best with deferred rendering
// - [ ] mip-mapping of textures
// - [ ] lens flare / post-processing
// - [ ] specular reflection probes (cubemaps)
// - [ ] skybox using cubemap
// - [ ] terrain system
//      - [ ] terrain normals (calculate derivatives for perlin noise terrain)
//      - [ ] grass / foliage / tree shader (animated with wind etc.)
//      - [ ] terrain chunks
// - [ ] water shader
// - [ ] frustum culling -> meshes should have bounds
// - [ ] LOD system
// - [ ] collisions (terrain collider, box collider)
// - [ ] scene file format -> utilize GLTF instead of inventing own scene model?
// - [ ] level editor
// - [ ] 3d text rendering
// - [ ] stereoscopic rendering

// data:
// CAD or BIM data
// 3D city data (Open Street Maps), Cesium (https://cesium.com/why-cesium/3d-tiles/)

// PBR:
// Blender Principled BSDF https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/principled.html
// OpenPBR https://github.com/AcademySoftwareFoundation/OpenPBR (is the result of collaboration between Autodesk and Adobe, taking inspiration from
// Autodesk Standard Surface and Adobe Standard Material).
// MaterialX https://materialx.org
// Autodesk Standard Surface https://autodesk.github.io/standard-surface/
// Adobe Standard Material https://helpx.adobe.com/content/dam/help/en/substance-3d/documentation/s3d/files/225969597/225969613/1/1647027222890/adobe-standard-material-specification.pdf
// Disney's Principled Shader
// Pixar's PxrSurface

// these shaders are über-shaders, which capture a wide range of materials, rather than requiring
// specialized shaders for each type of material. Unfortunately not all materials can be captured in a single
// model, so for high quality skin or cloth, a custom shader needs to be created.
// but for the large majority of materials, this singular über shader would suffice. e.g. for wood, metal, glass etc.

// https://github.com/AcademySoftwareFoundation/MaterialX/tree/main/libraries/bxdf
// so MaterialX is a common format that is a graph of nodes that represents a material
// this format is in XML, and gets compiled into MSL (Metal Shading Language), GLSL etc.
// this does immediately look quite complex. the git repository is also large.
//
// adopting it would have the advantage of being able to reuse materials from other programs
// https://zoewave.medium.com/explore-materialx-b8979808d512
// pros:
// - don't have to invent our own shader language, can use MaterialX to define all shaders -> might not cover all shader use cases
// - used by Houdini, Apple Reality Composer / RealityKit,
// cons:
// - dependency on a standard that might get abandoned / superseded
// - time to implement is larger than writing a singular PBR shader ourselves -> dubious

// approach:
// for now write custom PBR über-shader for learning purposes, and later adopt MaterialX for "production ready" code

// alternative approach:
// https://www.khronos.org/spir/
// write a custom shader language that compiles to SPIR-V and MSL (apparently SPIR-V can be cross-compiled to MSL using SPIRV-Cross)
// or: simply write in an existing shading language and cross-compile to all others.
// Vulkan and Metal are the only graphics APIs I intend to support, so this latter approach
// might be best.
// rewriting shaders from MSL to GLSL also won't be too hard, as the concepts and supported feature-sets of the languages / hardware are roughly the same.
// simplicity is key, so just writing the shader directly might be the easiest.
// we can always import MaterialX, just not use it internally.

// brdf = bidirectional reflectance distribution function

// compile shader variants:
// shader variants can strip out features that are not used to improve performance
// e.g. no alpha cutout, alpha blending or texture sampling when these are not enabled.

// now: implement OpenPBR specification from: https://academysoftwarefoundation.github.io/OpenPBR

// refer to this article for the difference between BRDF and BSDF: https://en.wikipedia.org/wiki/Bidirectional_scattering_distribution_function

// https://support.fab.com/s/article/How-does-Sketchfab-determine-if-a-3D-model-uses-PBR-materials

// https://viclw17.github.io/2018/08/05/raytracing-dielectric-materials
// https://pbr-book.org/4ed/contents (pathtracing, but good content)
// https://gfxcourses.stanford.edu/cs348b/spring22

// in OpenPBR Surface, the microfacet BRDF is taken from:
// https://www.graphics.cornell.edu/~bjw/microfacetbsdf.pdf
// and https://www.pbr-book.org/3ed-2018/Reflection_Models/Microfacet_Models

// f(wi, wo) ∝ F(wi, h) D(h) G(wi, wo)

// where wi = vector of light ray coming in
// and wo = vector of camera ray going out
// h is half vector, which reflects wi into wo (aka the normal or micro normal)

// proportionality (∝)
// given an independent variable x and dependent variable y, y is directly proportional to x if
// some k exists that can fulfill `y = kx`
// this gives: `y ∝ x`

// F(wi, h) is the Fresnel factor

// D(h) is the Normal Distribution Function (NDF)
// popular form of NDF = GGX distribution:

// DGGX(m) ∝ (1 + (tan(θm)^2))

// where m is the micronormal
// and θm is the angle between m and the macro surface normal

// G(wi, wo) is the Masking-shadowing function

// the following should be defined before including any headers that use glm, otherwise things break
#define GLM_ENABLE_EXPERIMENTAL
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#define GLM_FORCE_LEFT_HANDED

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

#include "common.h"
#include "rect.h"
#include "mesh.h"
#include "procedural_mesh.h"
#include "gltf.h"

#define SHADER_CONSTANTS_MAIN

#include "shader_constants.h"

#include "glm/glm.hpp"
#include "glm/detail/type_quat.hpp"
#include "glm/gtx/transform.hpp"
#include "glm/gtx/quaternion.hpp"

#include "fmt/format.h"

#include <stack>

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

enum ShaderFeatureFlags_
{
    ShaderFeatureFlags_None = 0,
    ShaderFeatureFlags_AlphaBlend = 1 << 0
};

struct AppConfig
{
    NSRect windowRect;
    NSSize windowMinSize;
    float sidepanelWidth;
    MTLClearColor clearColor;
    std::filesystem::path assetsPath;
    std::filesystem::path privateAssetsPath;
    std::string fontCharacterMap;
    float cameraFov;
    float cameraNear;
    float cameraFar;
    uint32_t shadowMapSize;
};

struct CameraData
{
    glm::mat4 viewProjection;
};

// data per instance
struct InstanceData
{
    glm::mat4 localToWorld;
};

struct LightData
{
    glm::mat4 lightSpace;
};

struct BlinnPhongGlobalVertexData
{
    glm::mat4 localToWorldTransposedInverse;
};

struct BlinnPhongGlobalFragmentData
{
    simd::float3 cameraPosition;
    simd::float3 lightDirection;

    // colors
    simd::float3 ambientColor;
    simd::float3 specularColor;
    simd::float3 lightColor;

    // parameters
    float irradiancePerp;
    float shininess;
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
    id <MTLRenderPipelineState> shaderClearDepth;
    id <MTLRenderPipelineState> shaderShadow;
    id <MTLRenderPipelineState> shaderUI;
    id <MTLRenderPipelineState> shaderLit;
    id <MTLRenderPipelineState> shaderLitAlphaBlend;
    id <MTLRenderPipelineState> shaderUnlit; // textured
    id <MTLRenderPipelineState> shaderUnlitAlphaBlend;
    id <MTLRenderPipelineState> shaderUnlitColored; // simplest shader possible, only uses the color
    id <MTLRenderPipelineState> shaderBlinnPhong;
    id <MTLRenderPipelineState> shaderGltf;
    id <MTLRenderPipelineState> shaderOpenPBRSurface; // OpenPBR Surface implementation from https://academysoftwarefoundation.github.io/OpenPBR/

    // for clearing the depth buffer (https://stackoverflow.com/questions/58964035/in-metal-how-to-clear-the-depth-buffer-or-the-stencil-buffer)
    id <MTLDepthStencilState> depthStencilStateClear;

    // font rendering
    TextureAtlas fontAtlas;
    Font font;

    // camera
    Transform cameraTransform;
    float cameraYaw;
    float cameraPitch;
    float cameraRoll;

    // skybox
    id <MTLRenderPipelineState> skyboxShader;
    id <MTLTexture> skyboxTexture;
    id <MTLTexture> skybox2Texture;
    id <MTLTexture> skybox3Texture;
    id <MTLTexture> skybox4Texture;

    // active skybox
    id <MTLTexture> activeSkybox;

    // PBR
    id <MTLTexture> prefilteredEnvironmentMap;

    // primitives
    Mesh cube;
    Mesh cubeWithoutUV;
    Mesh roundedCube;
    Mesh sphere;
    Mesh plane;

    // axes
    Mesh axes;

    // terrain
    Mesh terrain;
    id <MTLRenderPipelineState> terrainShader;
    id <MTLRenderPipelineState> waterShader;
    id <MTLTexture> terrainGreenTexture;
    id <MTLTexture> terrainYellowTexture;
    id <MTLTexture> waterTexture;

    // tree
    Mesh tree;
    id <MTLTexture> treeTexture;
    std::vector<InstanceData> treeInstances;

    id <MTLTexture> shrubTexture;
    std::vector<InstanceData> shrubInstances;

    // gltf model
    GltfModel gltfCathedral{};
    GltfModel gltfVrLoftLivingRoomBaked{};
    GltfModel gltfUgv{}; // https://sketchfab.com/3d-models/the-d-21-multi-missions-ugv-ebe40dc504a145d0909310e124334420

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

void onKeyPressed(App* app, CocoaKeyCode keyCode);

@implementation MetalView

// ui responder
- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent*)event {
    _app->keys[event.keyCode] = true;
    onKeyPressed(_app, static_cast<CocoaKeyCode>(event.keyCode));
}

- (void)keyUp:(NSEvent*)event {
    _app->keys[event.keyCode] = false;
}
@end

[[nodiscard]] bool isKeyPressed(App* app, CocoaKeyCode keyCode)
{
    return app->keys[static_cast<unsigned short>(keyCode)];
}

void onKeyPressed(App* app, CocoaKeyCode keyCode)
{
    if (keyCode == CocoaKeyCode::kVK_ANSI_1)
    {
        app->activeSkybox = app->skyboxTexture;
    }
    else if (keyCode == CocoaKeyCode::kVK_ANSI_2)
    {
        app->activeSkybox = app->skybox2Texture;
    }
    else if (keyCode == CocoaKeyCode::kVK_ANSI_3)
    {
        app->activeSkybox = app->skybox3Texture;
    }
    else if (keyCode == CocoaKeyCode::kVK_ANSI_4)
    {
        app->activeSkybox = app->skybox4Texture;
    }
}

void checkError(NSError* error)
{
    if (error)
    {
        std::cout << [error.debugDescription cStringUsingEncoding:NSUTF8StringEncoding] << std::endl;
        exit(1);
    }
}

id <MTLRenderPipelineState> createShader(
    App* app,
    NSString* vertexFunctionName,
    NSString* fragmentFunctionName,
    MTLFunctionConstantValues* vertexConstants,
    MTLFunctionConstantValues* fragmentConstants,
    ShaderFeatureFlags_ features = ShaderFeatureFlags_None)
{
    NSError* error = nullptr;

    // constants are a way to create function specializations (i.e. shader variants)
    // don't use too many constants, as this can lead to a combinatorial explosion
    id <MTLFunction> vertexFunction;
    id <MTLFunction> fragmentFunction;

    if (vertexConstants)
    {
        vertexFunction = [app->library newFunctionWithName:vertexFunctionName constantValues:vertexConstants error:&error];
    }
    else
    {
        vertexFunction = [app->library newFunctionWithName:vertexFunctionName];
    }
    checkError(error);

    if (fragmentConstants)
    {
        fragmentFunction = [app->library newFunctionWithName:fragmentFunctionName constantValues:fragmentConstants error:&error];
    }
    else
    {
        fragmentFunction = [app->library newFunctionWithName:fragmentFunctionName];
    }
    checkError(error);

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    if (features & ShaderFeatureFlags_AlphaBlend)
    {
        [descriptor.colorAttachments[0] setBlendingEnabled:YES];
        descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }
    id <CAMetalDrawable> drawable = [app->view currentDrawable];
    descriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;

    id <MTLRenderPipelineState> renderPipelineState = [app->device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    checkError(error);
    return renderPipelineState;
}


id <MTLTexture> importTexture(id <MTLDevice> device, std::filesystem::path const& path)
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

    return texture;
}

// works, but not the best, see: https://stackoverflow.com/questions/12657962/how-do-i-generate-a-random-number-between-two-variables-that-i-have-stored
int randomInt(int min, int max)
{
    return rand() % (max - min + 1) + min;
}

// https://stackoverflow.com/questions/686353/random-float-number-generation
float randomFloatMinMax(float min, float max)
{
    return min + (float)rand() / ((float)RAND_MAX / (max - min));
}

struct PBRPrefilterEnvironmentMapData
{
    float roughness;
    unsigned int mipLevel;
};

// source and output is assumed to be equirectangular projection (not a cubemap)
// adapted from https://bruop.github.io/ibl/
id <MTLTexture> createPrefilteredEnvironmentMap(id <MTLDevice> device,
                                                id <MTLLibrary> library,
                                                id <MTLCommandQueue> queue,
                                                id <MTLTexture> source)
{
    assert(source);
    id <MTLTexture> out;
    // create compute pipeline
    MTLFunctionDescriptor* functionDescriptor = [[MTLFunctionDescriptor alloc] init];
    functionDescriptor.name = @"pbr_prefilter_environment_map";
    NSError* error = nullptr;
    id <MTLFunction> function = [library newFunctionWithDescriptor:functionDescriptor error:&error];
    checkError(error);
    id <MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    checkError(error);

    // maxTotalThreadsPerThreadgroup: 1024, threadExecutionWidth: 32
    std::cout << "maxTotalThreadsPerThreadgroup: " << pipeline.maxTotalThreadsPerThreadgroup
              << ", threadExecutionWidth: " << pipeline.threadExecutionWidth
              << std::endl;

    // mip map levels
    unsigned int maxMipLevel = (int)log2(std::min(source.width, source.height));

    // create prefiltered environment map texture with all mip map levels (higher roughness is higher mip map levels / smaller mip map size)
    {
        MTLTextureDescriptor* d = [[MTLTextureDescriptor alloc] init];
        d.width = source.width;
        d.height = source.height;
        d.textureType = source.textureType;
        d.pixelFormat = source.pixelFormat;
        d.arrayLength = 1;
        d.mipmapLevelCount = maxMipLevel + 1; // mip level 0 is also included
        out = [device newTextureWithDescriptor:d];
    }

    // execute pipeline
    {
        id <MTLCommandBuffer> commandBuffer = [queue commandBuffer];

        // copy from source texture to target texture
        id <MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:source toTexture:out];
        [blit endEncoding];

        // execute compute kernel
        id <MTLComputeCommandEncoder> compute = [commandBuffer computeCommandEncoder];
        [compute setComputePipelineState:pipeline];
        [compute setTexture:source atIndex:1];

        for (unsigned int mipLevel = 0; mipLevel <= maxMipLevel; mipLevel++)
        {
            unsigned int width = out.width >> mipLevel;
            unsigned int height = out.height >> mipLevel;
            float roughness = (float)mipLevel / (float)maxMipLevel;
            std::cout << "mipLevel: " << mipLevel << ", width: " << width << ", height: " << height << ", roughness: " << roughness << std::endl;

            PBRPrefilterEnvironmentMapData data{
                .roughness = roughness,
                .mipLevel = mipLevel
            };
            [compute setBytes:&data length:sizeof(PBRPrefilterEnvironmentMapData) atIndex:0];

            // create texture view for a specific mip level, so that we can write to that specific level
            id <MTLTexture> outView = [out
                newTextureViewWithPixelFormat:out.pixelFormat
                textureType:out.textureType
                levels:NSMakeRange(mipLevel, 1)
                slices:NSMakeRange(0, 1)];
            [compute setTexture:outView atIndex:2];

            MTLSize threads = MTLSizeMake(width, height, 1);
            //[compute dispatchThreads:threads threadsPerThreadgroup:<#(MTLSize)threadsPerThreadgroup#>];
        }

        [compute endEncoding];
        [commandBuffer commit];
    }

    return out;
}

void onLaunch(App* app)
{
    // create MTLDevice
    app->device = MTLCreateSystemDefaultDevice();

    // create window
    {
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
    }

    // create split view
    {
        NSSplitView* splitView = [[NSSplitView alloc] initWithFrame:app->window.contentView.frame];
        [app->window setContentView:splitView];
        [splitView setVertical:YES];
        [splitView setDividerStyle:NSSplitViewDividerStylePaneSplitter];
        [splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        app->splitView = splitView;
    }

    // create metal kit view and add to window
    {
        MetalViewDelegate* viewDelegate = [[MetalViewDelegate alloc] init];
        viewDelegate.app = app;
        app->viewDelegate = viewDelegate;

        MetalView* view = [[MetalView alloc] initWithFrame:app->splitView.frame device:app->device];
        view.app = app;
        view.delegate = app->viewDelegate;
        view.clearColor = app->config->clearColor;
        view.depthStencilPixelFormat = MTLPixelFormatDepth16Unorm;
        [app->splitView addSubview:view];
        [app->window makeFirstResponder:view];
        app->view = view;
    }

    // create UI / text view sidepanel
    {
        TextViewDelegate* textViewDelegate = [[TextViewDelegate alloc] init];
        app->textViewDelegate = textViewDelegate;
        textViewDelegate.app = app;

        NSTextView* textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, app->config->sidepanelWidth, app->splitView.frame.size.height)];
        [textView setDelegate:app->textViewDelegate];
        [textView setAutomaticTextCompletionEnabled:NO];
        [textView setString:[[NSString alloc] initWithCString:app->currentText.c_str() encoding:NSUTF8StringEncoding]];
        [app->splitView addSubview:textView];
        app->sidepanel = textView;
    }

    [app->splitView adjustSubviews];

    // create command queue
    {
        id <MTLCommandQueue> commandQueue = [app->device newCommandQueue];
        app->commandQueue = commandQueue;
        [commandQueue retain];
    }

    // create default depth stencil state
    {
        MTLDepthStencilDescriptor* descriptor = [[MTLDepthStencilDescriptor alloc] init];
        descriptor.depthWriteEnabled = YES;
        descriptor.depthCompareFunction = MTLCompareFunctionLessEqual;
        app->depthStencilStateDefault = [app->device newDepthStencilStateWithDescriptor:descriptor];
    }

    // create shader library
    {
        // read shader source from metal source file (Metal Shading Language, MSL)
        std::filesystem::path shadersPath = app->config->assetsPath / "shaders";
        std::vector<std::filesystem::path> paths{
            shadersPath / "shader_constants.h",
            shadersPath / "shader_common.h",

            // utility
            shadersPath / "shader_clear_depth.metal",
            shadersPath / "shader_shadow.metal",

            // UI and 2D
            shadersPath / "shader_ui.metal",

            // special
            shadersPath / "shader_terrain.metal",
            shadersPath / "shader_skybox.metal",

            // 3D
            shadersPath / "shader_lit.metal",
            shadersPath / "shader_unlit.metal",
            shadersPath / "shader_blinn_phong.metal",
            shadersPath / "shader_gltf.metal",
            shadersPath / "shader_openpbr_surface.metal",

            // compute shaders
            shadersPath / "shader_pbr_prefilter_environment_map.metal"
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
        NSString* shaderSource = [NSString stringWithCString:s.c_str() encoding:NSUTF8StringEncoding];

        NSError* error = nullptr;
        MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
        app->library = [app->device newLibraryWithSource:shaderSource options:options error:&error];
        checkError(error);
    }

    // create shaders
    {
        MTLFunctionConstantValues* lit = [[MTLFunctionConstantValues alloc] init];
        bool false_ = false;
        [lit setConstantValue:&false_ type:MTLDataTypeBool atIndex:0];

        MTLFunctionConstantValues* litCutout = [[MTLFunctionConstantValues alloc] init];
        bool true_ = true;
        [litCutout setConstantValue:&true_ type:MTLDataTypeBool atIndex:0];

        // utility
        app->shaderShadow = createShader(app, @"shadow_vertex", @"shadow_fragment", nullptr, nullptr, ShaderFeatureFlags_None);

        // 2D / UI
        app->shaderUI = createShader(app, @"ui_vertex", @"ui_fragment", nullptr, nullptr, ShaderFeatureFlags_None);

        // special
        app->terrainShader = createShader(app, @"terrain_vertex", @"lit_fragment", nullptr, litCutout, ShaderFeatureFlags_None);
        app->waterShader = createShader(app, @"terrain_vertex", @"lit_fragment", nullptr, lit, ShaderFeatureFlags_AlphaBlend);
        app->skyboxShader = createShader(app, @"skybox_vertex", @"skybox_fragment", nullptr, nullptr, ShaderFeatureFlags_None);

        // 3D
        app->shaderLit = createShader(app, @"lit_vertex", @"lit_fragment", nullptr, litCutout, ShaderFeatureFlags_None);
        app->shaderLitAlphaBlend = createShader(app, @"lit_vertex", @"lit_fragment", nullptr, litCutout, ShaderFeatureFlags_AlphaBlend);
        app->shaderUnlit = createShader(app, @"unlit_vertex", @"unlit_fragment", nullptr, nullptr, ShaderFeatureFlags_None);
        app->shaderUnlitAlphaBlend = createShader(app, @"unlit_vertex", @"unlit_fragment", nullptr, nullptr, ShaderFeatureFlags_AlphaBlend);
        app->shaderUnlitColored = createShader(app, @"unlit_vertex", @"unlit_colored_fragment", nullptr, nullptr, ShaderFeatureFlags_None);

        app->shaderBlinnPhong = createShader(app, @"blinn_phong_vertex", @"blinn_phong_fragment", nullptr, nullptr, ShaderFeatureFlags_None);
        app->shaderGltf = createShader(app, @"gltf_vertex", @"gltf_fragment", nullptr, nullptr, ShaderFeatureFlags_None);
        app->shaderOpenPBRSurface = createShader(app, @"openpbr_surface_vertex", @"openpbr_surface_fragment", nullptr, nullptr, ShaderFeatureFlags_None);
    }

    // create depth clear pipeline state and depth stencil state
    {
        MTLDepthStencilDescriptor* depthStencilDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthStencilDescriptor.depthCompareFunction = MTLCompareFunctionAlways; // always write to buffer, no depth test
        depthStencilDescriptor.depthWriteEnabled = YES;
        app->depthStencilStateClear = [app->device newDepthStencilStateWithDescriptor:depthStencilDescriptor];

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
        app->shaderClearDepth = [app->device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&error];
        if (error)
        {
            std::cout << [error.debugDescription cStringUsingEncoding:NSUTF8StringEncoding] << std::endl;
            exit(1);
        }
    }

    // import textures
    {
        // for now the skybox texture is a regular texture (using equirectangular projection) instead of a cubemap texture
        // this is less performant, change later.
        app->skyboxTexture = importTexture(app->device, app->config->assetsPath / "textures" / "skybox.png");
        app->skybox2Texture = importTexture(app->device, app->config->assetsPath / "textures" / "skybox_2.png");
        app->skybox3Texture = importTexture(app->device, app->config->assetsPath / "textures" / "skybox_3.png");
        app->skybox4Texture = importTexture(app->device, app->config->assetsPath / "textures" / "skybox_4.png");
        app->activeSkybox = app->skyboxTexture;

        app->iconSunTexture = importTexture(app->device, app->config->assetsPath / "textures" / "sun.png");
//        app->terrainGreenTexture = importTexture(app->device, app->config->assetsPath / "textures" / "terrain_green.png");
//        app->terrainYellowTexture = importTexture(app->device, app->config->assetsPath / "textures" / "terrain.png");
//        app->waterTexture = importTexture(app->device, app->config->assetsPath / "textures" / "water.png");
    }

    // import font
    {
        std::filesystem::path path = app->config->assetsPath / "textures" / "texturemap.png";
        app->fontAtlas.texture = importTexture(app->device, path);

        // create sprites from texture
        uint32_t spriteSize = 32;
        uint32_t width = app->fontAtlas.texture.width;
        uint32_t height = app->fontAtlas.texture.height;
        createSprites(&app->fontAtlas, spriteSize, spriteSize, width / spriteSize, height / spriteSize);

        // create font map (which letter corresponds to which sprite index)
        app->font.atlas = &app->fontAtlas;
        createFontMap(&app->font, app->config->fontCharacterMap);
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
        app->shadowMap = [app->device newTextureWithDescriptor:descriptor];
    }

    // create primitive shapes
    {
        app->cubeWithoutUV = createCubeWithoutUV(app->device);
        app->cube = createCube(app->device);
        app->roundedCube = createRoundedCube(app->device, simd_float3{2.0f, 4.0f, 10.0f}, 0.5f, 3);
        app->sphere = createUVSphere(app->device, 60, 60);
        app->plane = createPlane(app->device, RectMinMaxf{-30, -30, 30, 30});
        app->axes = createAxes(app->device);
    }

    // set camera transform
    {
        app->cameraTransform = {
            .position = glm::vec3(5.0f, 5.0f, -7.0f),
            .rotation = glm::quat(1, 0, 0, 0),
            .scale = glm::vec3(1, 1, 1)
        };
    }

    // create terrain and trees on terrain
    if (0)
    {
        std::vector<VertexData> vertices{};
        std::vector<uint32_t> indices{};
        MTLPrimitiveType primitiveType;
        createTerrain(RectMinMaxf{-30, -30, 30, 30}, 2000, 2000, &vertices, &indices, &primitiveType);
        app->terrain = createMeshIndexed(app->device, &vertices, &indices, primitiveType);

        app->tree = createTree(app->device, 2.0f, 2.0f);

        int maxIndex = (int)vertices.size();
        // create tree instances at random positions from vertex data of the terrain
        int treeCount = 10;
        app->treeInstances.resize(treeCount);
        for (int i = 0; i < treeCount; i++)
        {
            // get random vertex from vertices
            int index = randomInt(0, maxIndex);
            VertexData& v = vertices[index];
            app->treeInstances[i] = InstanceData{
                .localToWorld = glm::scale(glm::translate(glm::vec3(v.position.x, v.position.y, v.position.z)), glm::vec3(randomFloatMinMax(0.5f, 1.0f)))
            };
        }

        // create shrub instances
        int shrubCount = 10;
        app->shrubInstances.resize(shrubCount);
        for (int i = 0; i < shrubCount; i++)
        {
            // get random vertex from vertices
            int index = randomInt(0, maxIndex);
            VertexData& v = vertices[index];
            app->shrubInstances[i] = InstanceData{
                .localToWorld = glm::scale(glm::translate(glm::vec3(v.position.x, v.position.y, v.position.z)), glm::vec3(randomFloatMinMax(0.2f, 0.8f)))
            };
        }

        app->treeTexture = importTexture(app->device, app->config->assetsPath / "textures" / "tree.png");
        app->shrubTexture = importTexture(app->device, app->config->assetsPath / "textures" / "shrub.png");
    }

    // import gltfs
    if (0)
    {
        bool success;

        success = importGltf(app->device, app->config->privateAssetsPath / "gltf" / "the_d-21_multi-missions_ugv.glb", &app->gltfUgv);
        assert(success);

        success = importGltf(app->device, app->config->assetsPath / "gltf" / "cathedral.glb", &app->gltfCathedral);
        assert(success);

        success = importGltf(app->device, app->config->privateAssetsPath / "gltf" / "vr_loft__living_room__baked.glb", &app->gltfVrLoftLivingRoomBaked);
        assert(success);
    }

    // cubemap is more performant than equirectangular projection

    // write three shaders:
    // - equirectangular to cubemap projection -> store to disk? (this can be sampled more efficiently)
    // - cubemap based skybox shader
    // - cubemap based reflection shader (image based lighting) in OpenPBR Surface
    // - compute shaders that create GGX lookup textures (mipmaps in Metal are not prepopulated, should be filled in manually)

    // cubemap can be done later, first let's create the lookup textures

    // create prefiltered environment map for PBR rendering
    app->prefilteredEnvironmentMap = createPrefilteredEnvironmentMap(app->device, app->library, app->commandQueue, app->skybox2Texture);

    // make window active
    [app->window makeKeyAndOrderFront:NSApp];
}

void onTerminate(App* app)
{

}

void addQuad(std::vector<VertexData>* vertices, RectMinMaxf position, RectMinMaxf uv)
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
        addQuad(vertices, positionCoords, textureCoords);

        i++;
    }
}

// sets: triangle fill mode, cull mode, depth stencil state and render pipeline state
void clearDepthBuffer(App* app, id <MTLRenderCommandEncoder> encoder)
{
    // Set up the pipeline and depth/stencil state to write a clear value to only the depth buffer.
    [encoder setDepthStencilState:app->depthStencilStateClear];
    [encoder setRenderPipelineState:app->shaderClearDepth];

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

void drawMesh(id <MTLRenderCommandEncoder> encoder, Mesh* mesh, InstanceData* instance)
{
    [encoder setVertexBytes:instance length:sizeof(InstanceData) atIndex:bindings::instanceData];
    [encoder setVertexBuffer:mesh->vertexBuffer offset:0 atIndex:bindings::vertexData];
    if (mesh->indexed)
    {
        [encoder
            drawIndexedPrimitives:mesh->primitiveType
            indexCount:mesh->indexCount
            indexType:mesh->indexType
            indexBuffer:mesh->indexBuffer
            indexBufferOffset:0];
    }
    else
    {
        [encoder
            drawPrimitives:mesh->primitiveType
            vertexStart:0
            vertexCount:mesh->vertexCount];
    }
}

void drawMeshInstanced(id <MTLRenderCommandEncoder> encoder, Mesh* mesh, std::vector<InstanceData>* instances)
{
    [encoder setVertexBytes:instances->data() length:instances->size() * sizeof(InstanceData) atIndex:bindings::instanceData];
    [encoder setVertexBuffer:mesh->vertexBuffer offset:0 atIndex:bindings::vertexData];
    if (mesh->indexed)
    {
        [encoder
            drawIndexedPrimitives:mesh->primitiveType
            indexCount:mesh->indexCount
            indexType:mesh->indexType
            indexBuffer:mesh->indexBuffer
            indexBufferOffset:0
            instanceCount:instances->size()
            baseVertex:0
            baseInstance:0];
    }
    else
    {
        [encoder
            drawPrimitives:mesh->primitiveType
            vertexStart:0
            vertexCount:mesh->vertexCount
            instanceCount:instances->size()
            baseInstance:0];
    }
}

void setCameraData(id <MTLRenderCommandEncoder> encoder, glm::mat4 viewProjection)
{
    CameraData cameraData{viewProjection};
    [encoder setVertexBytes:&cameraData length:sizeof(CameraData) atIndex:bindings::cameraData];
}

enum DrawSceneFlags_
{
    DrawSceneFlags_None = 0,
    DrawSceneFlags_IsShadowPass = 1 << 0
};

[[nodiscard]] simd::float3 glmVec3ToSimdFloat3(glm::vec3 in)
{
    return simd::float3{in.x, in.y, in.z}; // could also simply reinterpret cast as the struct layout should be the same
}

[[nodiscard]] glm::vec3 quaternionToDirectionVector(glm::quat in)
{
    glm::mat4 rotationMatrix = glm::toMat4(in);
    auto directionVector = glm::vec3(rotationMatrix[2]); // Z-axis for forward direction
    return glm::normalize(directionVector);
}

void drawGltfPrimitive(id <MTLRenderCommandEncoder> encoder, GltfModel* model, GltfPrimitive* primitive)
{
    // bind vertex attributes
    size_t offset = 0;
    for (auto& attribute: primitive->attributes)
    {
        int index = 0;
        switch (attribute.type)
        {
            case cgltf_attribute_type_invalid:assert(false);
                break;
            case cgltf_attribute_type_position:index = bindings::positions;
                break;
            case cgltf_attribute_type_normal:index = bindings::normals;
                break;
            case cgltf_attribute_type_tangent:index = bindings::tangents;
                break;
            case cgltf_attribute_type_texcoord:index = bindings::uv0s;
                break;
            case cgltf_attribute_type_color:index = bindings::colors;
                break;
            case cgltf_attribute_type_joints:assert(false);
                break;
            case cgltf_attribute_type_weights:assert(false);
                break;
            case cgltf_attribute_type_custom:assert(false);
                break;
            case cgltf_attribute_type_max_enum:assert(false);
                break;
        }
        [encoder setVertexBuffer:primitive->vertexBuffer offset:offset atIndex:index];
        offset += attribute.size;
    }

    // set correct fragment texture
    if (primitive->material != invalidIndex)
    {
        GltfMaterial* mat = &model->materials[primitive->material];
        if (mat->baseColor != invalidIndex)
        {
            id <MTLTexture> texture = model->textures[mat->baseColor];
            [encoder setFragmentTexture:texture atIndex:0];
        }
    }

    [encoder
        drawIndexedPrimitives:primitive->primitiveType
        indexCount:primitive->indexCount
        indexType:primitive->indexType
        indexBuffer:primitive->indexBuffer
        indexBufferOffset:0
        instanceCount:1
        baseVertex:0
        baseInstance:0];
}

void drawGltfMesh(id <MTLRenderCommandEncoder> encoder, GltfModel* model, glm::mat4 localToWorld, GltfMesh* mesh)
{
    InstanceData instance{
        .localToWorld = localToWorld
    };
    [encoder setVertexBytes:&instance length:sizeof(InstanceData) atIndex:bindings::instanceData];

    for (auto& primitive: mesh->primitives)
    {
        drawGltfPrimitive(encoder, model, &primitive);
    }
}

struct GltfDFSData
{
    GltfNode* node;
    glm::mat4 localToWorld; // calculated
};

void drawGltf(App* app, id <MTLRenderCommandEncoder> encoder, GltfModel* model, glm::mat4 transform)
{
    [encoder setCullMode:MTLCullModeNone];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setRenderPipelineState:app->shaderGltf]; // shaderGltf];
    [encoder setDepthStencilState:app->depthStencilStateDefault];

    // traverse scene
    GltfScene* scene = &model->scenes[0];

    // dfs
    std::stack<GltfDFSData> stack;
    GltfNode* rootNode = &model->nodes[scene->rootNode];
    stack.push({.node = rootNode, .localToWorld = transform});
    while (!stack.empty())
    {
        GltfDFSData d = stack.top();
        stack.pop();

        // draw mesh at transform
        if (d.node->meshIndex != invalidIndex)
        {
            drawGltfMesh(encoder, model, d.localToWorld, &model->meshes[d.node->meshIndex]);
        }

        // iterate over children
        for (int i = 0; i < d.node->childNodes.size(); i++)
        {
            size_t childIndex = d.node->childNodes[i];
            GltfNode* child = &model->nodes[childIndex];

            // calculate localToWorld
            glm::mat4 localToWorld = d.localToWorld * child->localTransform;

            stack.push({.node = child, .localToWorld = localToWorld});
        }
    }
}

struct OpenPBRSurfaceGlobalVertexData
{
    glm::mat4 localToWorldTransposedInverse;
};

struct OpenPBRSurfaceGlobalFragmentData
{
    simd_float3 cameraPosition;
    float roughness;
};

void drawScene(App* app, id <MTLRenderCommandEncoder> encoder, DrawSceneFlags_ flags)
{
    assert(encoder != nullptr);

    // draw terrain
    if (0)
    {
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:(flags & DrawSceneFlags_IsShadowPass) ? app->shaderShadow : app->terrainShader];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->terrainGreenTexture atIndex:0];
        std::vector<InstanceData> instances{
            {.localToWorld = glm::mat4(1)}//glm::rotate(app->time, glm::vec3(0, 1, 0))},
//            {.localToWorld = glm::scale(glm::translate(glm::vec3(0, 0, 9)), glm::vec3(0.5f))},
//            {.localToWorld = glm::translate(glm::vec3(9, 0, 9))},
//            {.localToWorld = glm::translate(glm::vec3(9, 0, 0))},
        };
        drawMeshInstanced(encoder, &app->terrain, &instances);
    }

    // draw water
    if (0)
    {
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:(flags & DrawSceneFlags_IsShadowPass) ? app->shaderShadow : app->waterShader];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->waterTexture atIndex:0];
        InstanceData instance{
            .localToWorld = glm::mat4(1)
        };
        drawMesh(encoder, &app->plane, &instance);
    }

    // draw rounded cube (blinn phong test)
    if (0)
    {
        [encoder setCullMode:MTLCullModeBack];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:(flags & DrawSceneFlags_IsShadowPass) ? app->shaderShadow : app->shaderBlinnPhong];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->terrainYellowTexture atIndex:0];
        float angle = app->time;
        InstanceData instance{
            .localToWorld = glm::rotate(glm::translate(glm::vec3{0, 3, 0}), angle, glm::vec3(0, 1, 0))
        };
        BlinnPhongGlobalVertexData vertexData{
            .localToWorldTransposedInverse = glm::transpose(glm::inverse(instance.localToWorld))
        };
        BlinnPhongGlobalFragmentData fragmentData{
            .cameraPosition = glmVec3ToSimdFloat3(app->cameraTransform.position),
            .lightDirection = glmVec3ToSimdFloat3(quaternionToDirectionVector(app->sunTransform.rotation)),

            // colors
            .ambientColor = {0, 0.1, 0.1},
            .specularColor = {0, 1, 0},
            .lightColor = {1, 1, 0.5},

            // parameters
            .irradiancePerp = 1.0f,
            .shininess = 50.0f//.shininess = 50.0f + 50.0f * sin(app->time),
        };
        [encoder setVertexBytes:&vertexData length:sizeof(BlinnPhongGlobalVertexData) atIndex:3];
        [encoder setFragmentBytes:&fragmentData length:sizeof(BlinnPhongGlobalFragmentData) atIndex:1];
        drawMesh(encoder, &app->roundedCube, &instance);
    }

    // draw trees
    if (0)
    {
        [encoder setCullMode:MTLCullModeNone];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:app->shaderLit];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->treeTexture atIndex:0];
        drawMeshInstanced(encoder, &app->tree, &app->treeInstances);
    }

    // draw shrubs
    if (0)
    {
        [encoder setCullMode:MTLCullModeNone];
        [encoder setTriangleFillMode:MTLTriangleFillModeFill];
        [encoder setRenderPipelineState:app->shaderLitAlphaBlend];
        [encoder setDepthStencilState:app->depthStencilStateDefault];
        [encoder setFragmentTexture:app->shrubTexture atIndex:0];
        drawMeshInstanced(encoder, &app->tree, &app->shrubInstances);

        std::vector<InstanceData>* instances = &app->shrubInstances;
        Mesh* mesh = &app->tree;

        [encoder setVertexBytes:instances->data() length:instances->size() * sizeof(InstanceData) atIndex:bindings::instanceData];
        [encoder setVertexBuffer:mesh->vertexBuffer offset:0 atIndex:bindings::vertexData];

        [encoder
            drawIndexedPrimitives:mesh->primitiveType
            indexCount:mesh->indexCount
            indexType:mesh->indexType
            indexBuffer:mesh->indexBuffer
            indexBufferOffset:0
            instanceCount:instances->size()
            baseVertex:0
            baseInstance:0];
    }

    // draw gltfs
    if (0)
    {
        drawGltf(app, encoder, &app->gltfUgv, glm::scale(glm::mat4(1), glm::vec3(2, 2, 2)));
        drawGltf(app, encoder, &app->gltfCathedral, glm::translate(glm::scale(glm::mat4(1), glm::vec3(0.6f, 0.6f, 0.6f)), glm::vec3(60, 0, 0)));
        drawGltf(app, encoder, &app->gltfVrLoftLivingRoomBaked, glm::translate(glm::vec3(0, 10, 0)));
    }

    // draw pbr (not textured yet)
    if (1)
    {
        // for now, we store all material settings inside the fragment bytes, so that we don't have to create a separate buffer for all different material settings
        for (int x = 0; x < 5; x++)
        {
            for (int y = 0; y < 5; y++)
            {
                // draw pbr
                [encoder setCullMode:MTLCullModeBack];
                [encoder setTriangleFillMode:MTLTriangleFillModeFill];
                [encoder setRenderPipelineState:app->shaderOpenPBRSurface];
                [encoder setDepthStencilState:app->depthStencilStateDefault];

                InstanceData instance{
                    .localToWorld = glm::rotate(glm::scale(glm::translate(glm::vec3(x * 6, y * 3, 0)), glm::vec3(0.5, 0.5, 0.5)),
                                                app->time + (float)x / 6.0f + (float)y / 10.0f, glm::vec3(0, 1, 0))
                };
                OpenPBRSurfaceGlobalVertexData globalVertexData{
                    .localToWorldTransposedInverse = glm::transpose(glm::inverse(instance.localToWorld))
                };

                OpenPBRSurfaceGlobalFragmentData globalFragmentData{
                    .cameraPosition = glmVec3ToSimdFloat3(app->cameraTransform.position),
                    .roughness = (float)x / 5.0f
                };
                [encoder setVertexBytes:&globalVertexData length:sizeof(OpenPBRSurfaceGlobalVertexData) atIndex:bindings::globalVertexData];
                [encoder setFragmentBytes:&globalFragmentData length:sizeof(OpenPBRSurfaceGlobalFragmentData) atIndex:bindings::globalFragmentData];
                [encoder setFragmentTexture:app->prefilteredEnvironmentMap atIndex:bindings::reflectionMap];
                drawMesh(encoder, &app->roundedCube, &instance);
            }
        }
    }
}

void drawAxes(App* app, id <MTLRenderCommandEncoder> encoder, glm::mat4 transform)
{
    [encoder setCullMode:MTLCullModeNone];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setDepthStencilState:app->depthStencilStateDefault];
    [encoder setRenderPipelineState:app->shaderUnlitColored];
    InstanceData instance{.localToWorld = transform};
    drawMesh(encoder, &app->axes, &instance);
}

void drawTexture(App* app, id <MTLRenderCommandEncoder> encoder, id <MTLTexture> texture, RectMinMaxi pixelCoords)
{
    [encoder setCullMode:MTLCullModeBack];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setRenderPipelineState:app->shaderUI];
    [encoder setFragmentTexture:texture atIndex:bindings::texture];

    RectMinMaxf extents = pixelCoordsToNDC(app, pixelCoords);
    std::vector<VertexData> vertices;
    addQuad(&vertices, extents, /*uv*/ RectMinMaxf{0, 0, 1, 1});
    [encoder setVertexBytes:vertices.data() length:vertices.size() * sizeof(VertexData) atIndex:bindings::vertexData];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
}

// main render loop
void onDraw(App* app)
{
    app->time += 0.015f;
    if (app->time > 2.0f * pi_)
    {
        app->time -= 2.0f * pi_;
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

        float currentX = 0.0f + 0.5f * sin(app->time);
        float currentY = 5.0f + 0.5f * cos(app->time);
        float currentRot = 30.0f + 20.0f * sin(app->time);
        app->sunTransform = {
            .position = glm::vec3{currentX, currentY, -20.0f},
            .rotation = glm::quat{glm::vec3{glm::radians(currentRot), glm::radians(10.0f), 0}},
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
        glm::mat4 projection = glm::ortho(-40.0f, 40.0f, -40.0f, 40.0f, 1.0f, 50.0f);
        glm::mat4 view = glm::inverse(transformToMatrix(&app->sunTransform));
        lightData.lightSpace = projection * view;

        // set camera data
        setCameraData(encoder, lightData.lightSpace);
        drawScene(app, encoder, DrawSceneFlags_IsShadowPass);
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

        glm::mat4 projection;
        glm::mat4 view;
        glm::mat4 viewProjection;

        // calculate camera matrix and draw scene
        {
            CGSize size = app->view.frame.size;
            projection = glm::perspective(glm::radians(app->config->cameraFov),
                                          (float)(size.width / size.height),
                                          app->config->cameraNear, app->config->cameraFar);
            view = glm::inverse(transformToMatrix(&app->cameraTransform));
            viewProjection = projection * view;

            [encoder setFragmentTexture:app->shadowMap atIndex:bindings::shadowMap];
            [encoder setVertexBytes:&lightData length:sizeof(LightData) atIndex:bindings::lightData];

            setCameraData(encoder, viewProjection);
            drawScene(app, encoder, DrawSceneFlags_None);
        }

        // we need to sample the equirectangular projection skybox texture using spherical coordinates.
        // the position of the camera is not taken into account
        Transform skyboxCameraTransform = app->cameraTransform;
        skyboxCameraTransform.position = glm::vec3(0);
        glm::mat4 skyboxView = glm::inverse(transformToMatrix(&skyboxCameraTransform));
        setCameraData(encoder, projection * skyboxView);

        // draw skybox
        if (1)
        {
            [encoder setCullMode:MTLCullModeNone];
            [encoder setTriangleFillMode:MTLTriangleFillModeFill];
            [encoder setDepthStencilState:app->depthStencilStateDefault];
            [encoder setRenderPipelineState:app->skyboxShader];
            [encoder setFragmentTexture:app->activeSkybox atIndex:bindings::texture];
            InstanceData instance{
                .localToWorld = glm::scale(glm::mat4(1.0f), glm::vec3(10))
            };
            drawMesh(encoder, &app->cube, &instance);
        }

        // clear depth buffer (sets vertex bytes at index 0)
        clearDepthBuffer(app, encoder);

        // set camera data again (sets vertex bytes at index 0, so has to be called after clearDepthBuffer)
        setCameraData(encoder, viewProjection);

        // draw cube at sun position
        {
            [encoder setCullMode:MTLCullModeNone];
            [encoder setTriangleFillMode:MTLTriangleFillModeFill];
            [encoder setDepthStencilState:app->depthStencilStateDefault];
            [encoder setRenderPipelineState:app->shaderUnlitAlphaBlend];
            [encoder setFragmentTexture:app->iconSunTexture atIndex:bindings::texture];
            InstanceData instance{
                .localToWorld = glm::scale(transformToMatrix(&app->sunTransform), glm::vec3(0.25f))
            };
            drawMesh(encoder, &app->cube, &instance);
        }

        // draw axes at sun position
        drawAxes(app, encoder, transformToMatrix(&app->sunTransform));

        // draw axes at origin
        drawAxes(app, encoder, glm::mat4(1));

        // draw shadow map (2D, on-screen)
        drawTexture(app, encoder, app->shadowMap, RectMinMaxi{0, 28, 200, 200});

        // draw skybox (2D, on-screen)
        drawTexture(app, encoder, app->activeSkybox, RectMinMaxi{200, 28, 600, 200});

        // draw gltf textures (2D, on-screen)
        for (size_t i = 0; i < app->gltfCathedral.textures.size(); i++)
        {
            id <MTLTexture> texture = app->gltfCathedral.textures[i];
            uint32_t size = 75;
            uint32_t y = 220;
            drawTexture(app, encoder, texture, RectMinMaxi{size * (uint32_t)i, y, size * (uint32_t)i + size, y + size});
        }

        // draw gltf textures (2D, on-screen)
        for (size_t i = 0; i < app->gltfVrLoftLivingRoomBaked.textures.size(); i++)
        {
            id <MTLTexture> texture = app->gltfVrLoftLivingRoomBaked.textures[i];
            uint32_t size = 50;
            uint32_t y = 220 + 160;
            uint32_t xCount = 10;
            uint32_t yIndex = i / xCount;
            uint32_t xIndex = i % xCount;
            uint32_t padding = 2;
            drawTexture(
                app, encoder, texture,
                RectMinMaxi{
                    size * xIndex + (xIndex * padding),
                    y + yIndex * size + (yIndex * padding),
                    size * xIndex + size + (xIndex * padding),
                    y + size + yIndex * size + (yIndex * padding)
                }
            );
        }

        // draw text (2D, on-screen)
        {
            [encoder setCullMode:MTLCullModeBack];
            [encoder setTriangleFillMode:MTLTriangleFillModeFill];
            [encoder setRenderPipelineState:app->shaderUI];
            [encoder setFragmentTexture:app->fontAtlas.texture atIndex:bindings::texture];
            std::vector<VertexData> vertices;

            glm::vec3* pos = &app->cameraTransform.position;
            std::string a = fmt::format("camera ({0:+.3f}, {1:+.3f}, {2:+.3f})", pos->x, pos->y, pos->z);
            addText(app, a, &vertices, 0, 0, 14);

            pos = &app->sunTransform.position;
            std::string b = fmt::format("sun ({0:+.3f}, {1:+.3f}, {2:+.3f})", pos->x, pos->y, pos->z);
            addText(app, b, &vertices, 0, 14, 14);

            // draw text
            [encoder setVertexBytes:vertices.data() length:vertices.size() * sizeof(VertexData) atIndex:bindings::vertexData];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
        }

        [encoder endEncoding];
        assert(app->view.currentDrawable);
        [cmd presentDrawable:app->view.currentDrawable];
        [cmd commit];
    }
}

void onSizeChanged(App* app, CGSize size)
{

}

int main(int argc, char const* argv[])
{
    assert(argc == 3); // we expect one additional argument: the assets folder
    char const* assetsDirectory = argv[1];
    char const* privateAssetsDirectory = argv[2];

    std::string fontCharacterMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?/_[]{}'\"()&^#@%*=+-;:<>~`abcdefghijklmnopqrstuvwxyz0123456789 ";

    // seed the time
    srand(time(nullptr));

    AppConfig config{
        .windowRect = NSMakeRect(0, 0, 1200, 800),
        .windowMinSize = NSSize{100.0f, 50.0f},
        .sidepanelWidth = 300.0f,
        .clearColor = MTLClearColorMake(0, 1, 1, 1.0),
        .assetsPath = assetsDirectory,
        .privateAssetsPath = privateAssetsDirectory,
        .fontCharacterMap = fontCharacterMap,
        .cameraFov = 90.0f,
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
    NSApplication* nsApp = [NSApplication sharedApplication];
    [nsApp setDelegate:appDelegate];
    [nsApp run];
    return 0;
}

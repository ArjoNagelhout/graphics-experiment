#include <iostream>

// what to build:
// a simple game

// how to render to the screen:
// Metal?

// we use MTKView

// we want to render text
// spritesheet?
// vector text rendering
// SDF
// let's use simplest method: spritesheet

#include <fstream>
#include <sstream>
#include <vector>
#include <filesystem>

#import "Cocoa/Cocoa.h"
#import "MetalKit/MTKView.h"
#import "Metal/MTLDevice.h"
#import "Metal/MTLDrawable.h"
#import "simd/simd.h"

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

struct AppConfig
{
    NSRect windowRect;
    MTLClearColor clearColor;
    std::filesystem::path assetsPath;
};

struct VertexData
{
    simd_float4 position;
    simd_float4 color;
};



struct App
{
    AppConfig* config;

    // window and view
    NSWindow* window;
    MTKView* view;
    MetalViewDelegate* viewDelegate;

    // metal objects
    id <MTLDevice> device;
    id <MTLLibrary> library; // shader library
    id <MTLCommandQueue> commandQueue;
    id <MTLDepthStencilState> depthStencilState;
    id <MTLRenderPipelineState> renderPipelineState;
    id <MTLBuffer> vertexBuffer;
};

void onLaunch(App* app)
{
    // create metal kit view delegate
    MetalViewDelegate* viewDelegate = [[MetalViewDelegate alloc] init];
    viewDelegate.app = app;
    app->viewDelegate = viewDelegate;
    [viewDelegate retain];

    // create MTLDevice
    id <MTLDevice> device = MTLCreateSystemDefaultDevice();
    app->device = device;
    [device retain];

    // create window
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:app->config->windowRect
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setTitle:@"bored_c"];
    [window setBackgroundColor:[NSColor blackColor]];
    [window center];
    app->window = window;
    [window retain];

    // create metal kit view and add to window
    MTKView* view = [[MTKView alloc] initWithFrame:window.frame device:device];
    view.delegate = viewDelegate;
    view.clearColor = app->config->clearColor;
    [window setContentView:view];
    [window makeFirstResponder:view];
    app->view = view;
    [view retain];

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
        descriptor.depthCompareFunction = MTLCompareFunctionAlways;
        id <MTLDepthStencilState> depthStencilState = [device newDepthStencilStateWithDescriptor:descriptor];
        app->depthStencilState = depthStencilState;
        [depthStencilState retain];
    }

    // create shader library
    {
        // read shader source from metal source file (Metal Shading Language, MSL)
        std::filesystem::path path = app->config->assetsPath / "shader.metal";
        assert(std::filesystem::exists(path));
        std::ifstream file(path);
        std::stringstream buffer;
        buffer << file.rdbuf();
        std::string s = buffer.str();
        NSString* shaderSource = [NSString stringWithCString:s.c_str()];

        NSError* error = nullptr;
        MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
        id <MTLLibrary> library = [device newLibraryWithSource:shaderSource options:options error:&error];
        if (error)
        {
            std::cout << error.debugDescription.cString << std::endl;
        }
        app->library = library;
        [library retain];
    }

    // create render pipeline state
    {
        // use function specialization to create shader variants
        id <MTLFunction> vertexFunction = [app->library newFunctionWithName:@"main_vertex"];
        assert(vertexFunction != nullptr);
        id <MTLFunction> fragmentFunction = [app->library newFunctionWithName:@"main_fragment"];
        assert(fragmentFunction != nullptr);

        MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
        descriptor.vertexFunction = vertexFunction;
        descriptor.fragmentFunction = fragmentFunction;
        id <CAMetalDrawable> drawable = [app->view currentDrawable];
        descriptor.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat;

        NSError* error = nullptr;
        id <MTLRenderPipelineState> renderPipelineState = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
        if (error)
        {
            std::cout << error.debugDescription.cString << std::endl;
        }
        app->renderPipelineState = renderPipelineState;
        [renderPipelineState retain];

        [vertexFunction release];
        [fragmentFunction release];
    }

    // create vertex buffer
    {
        std::vector<VertexData> vertices{
            {.position = {0.5f, -0.5f, 0.0f, 1.0f}, .color = {1.0f, 0.0f, 0.0f, 1.0f}},
            {.position = {-0.5f, -0.5f, 0.0f, 1.0f}, .color = {0.0f, 0.0f, 1.0f, 1.0f}},
            {.position = {0.0f, 0.5f, 0.0f, 1.0f}, .color = {1.0f, 1.0f, 0.0f, 1.0f}}
        };

        MTLResourceOptions options = MTLResourceCPUCacheModeDefaultCache | MTLResourceStorageModeShared;
        id <MTLBuffer> buffer = [device newBufferWithBytes:vertices.data() length:vertices.size() * sizeof(VertexData) options:options];
        app->vertexBuffer = buffer;
        [buffer retain];
    }

    // make window active
    [window makeKeyAndOrderFront:NSApp];
}

void onTerminate(App* app)
{
    [app->vertexBuffer release];
    [app->renderPipelineState release];
    [app->depthStencilState release];
    [app->view release];
    [app->window release];
    [app->commandQueue release];
    [app->device release];
    [app->viewDelegate release];
}

void onDraw(App* app)
{
    // main render loop
    MTLRenderPassDescriptor* renderPass = [app->view currentRenderPassDescriptor];
    assert(renderPass);
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id <MTLCommandBuffer> cmd = [app->commandQueue commandBuffer];
    assert(cmd);
    id <MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:renderPass];
    assert(encoder);

    [encoder setFrontFacingWinding:MTLWindingClockwise];
    [encoder setCullMode:MTLCullModeNone];
    [encoder setTriangleFillMode:MTLTriangleFillModeFill];
    [encoder setDepthStencilState:app->depthStencilState];
    [encoder setRenderPipelineState:app->renderPipelineState];
    [encoder setVertexBuffer:app->vertexBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    assert(app->view.currentDrawable);
    [cmd presentDrawable:app->view.currentDrawable];
    [cmd commit];
}

void onSizeChanged(App* app, CGSize size)
{

}

int main(int argc, char const* argv[])
{
    assert(argc == 2); // we expect one additional argument: the assets folder
    char const* assetsFolder = argv[1];

    AppConfig config{
        .windowRect = NSMakeRect(0, 0, 800, 600),
        .clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0),
        .assetsPath = argv[1]
    };
    App app{
        .config = &config
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

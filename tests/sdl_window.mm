//
// Created by Arjo Nagelhout on 17/08/2024.
//

#define SDL_MAIN_USE_CALLBACKS 1 /* use the callbacks instead of main() */
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#import "Cocoa/Cocoa.h"
#import "Metal/MTLDevice.h"
#import "QuartzCore/CAMetalLayer.h"

#include <cassert>

constexpr int stepRateInMilliseconds = 125;

struct App
{
    SDL_Window* window;
    SDL_MetalView metalView;
    NSView* view;
    CAMetalLayer* metalLayer;
    id <MTLDevice> device;


    SDL_TimerID stepTimer;

};

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

SDL_AppResult SDL_AppIterate(void* appstate)
{
    App* app = (App*)appstate;

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppInit(void** appstate, int argc, char* argv[])
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0)
    {
        return SDL_APP_FAILURE;
    }

    App* app = new App();
    *appstate = app;

    // create window
    {
        SDL_WindowFlags windowFlags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_METAL;
        app->window = SDL_CreateWindow("sdl window test", 600, 400, windowFlags);
        assert(app->window);
    }

    // create Metal device
    app->device = MTLCreateSystemDefaultDevice();

    // create Metal view
    {
        app->metalView = SDL_Metal_CreateView(app->window);
        assert(app->metalView);
        app->view = (NSView*)app->metalView;

        // assign metal device to layer
        app->metalLayer = (CAMetalLayer*)SDL_Metal_GetLayer(app->metalView);
        assert(app->metalLayer);
    }

    app->stepTimer = SDL_AddTimer(stepRateInMilliseconds, sdlTimerCallback, nullptr);
    assert(app->stepTimer != 0);

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

void SDL_AppQuit(void* appstate)
{
    if (appstate)
    {
        App* app = (App*)appstate;
        SDL_RemoveTimer(app->stepTimer);
        SDL_Metal_DestroyView(app->metalView);
        SDL_DestroyWindow(app->window);
        delete app;
    }
}

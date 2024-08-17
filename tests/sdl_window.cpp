//
// Created by Arjo Nagelhout on 17/08/2024.
//

#define SDL_MAIN_USE_CALLBACKS 1 /* use the callbacks instead of main() */
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include <cassert>

constexpr int stepRateInMilliseconds = 125;

struct App
{
    SDL_Window* window = nullptr;
    SDL_TimerID stepTimer = 0;
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

    SDL_WindowFlags windowFlags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_METAL;
    app->window = SDL_CreateWindow("sdl window test", 600, 400, windowFlags);
    if (!app->window)
    {
        return SDL_APP_FAILURE;
    }

    app->stepTimer = SDL_AddTimer(stepRateInMilliseconds, sdlTimerCallback, nullptr);
    if (app->stepTimer == 0)
    {
        return SDL_APP_FAILURE;
    }
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
        SDL_DestroyWindow(app->window);
        delete app;
    }
}

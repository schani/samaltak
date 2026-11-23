#ifndef SAMALTAK_C4_SDL_H
#define SAMALTAK_C4_SDL_H

#include <SDL3/SDL.h>

static inline bool c4_sdl_real_driver(const char *driver)
{
    return driver && (SDL_strcmp(driver, "x11") == 0 ||
                      SDL_strcmp(driver, "wayland") == 0);
}

static inline bool c4_sdl_init_video(void)
{
    /* Do not even initialize KMS, dummy, offscreen, or another backend.
     * SDL_GetHint also handles the old SDL_VIDEODRIVER environment name. */
    const char *driver = SDL_GetHint(SDL_HINT_VIDEO_DRIVER);
    if (driver && *driver && !c4_sdl_real_driver(driver))
        return SDL_SetError("a real X11 or Wayland display is required");
    if (!SDL_SetHintWithPriority(SDL_HINT_VIDEO_DRIVER,
                                 driver && *driver ? driver : "wayland,x11",
                                 SDL_HINT_OVERRIDE))
        return SDL_SetError("cannot restrict video drivers to X11 and Wayland");
    if (!SDL_SetHintWithPriority(SDL_HINT_FRAMEBUFFER_ACCELERATION, "0", SDL_HINT_OVERRIDE))
        return SDL_SetError("cannot select a software window surface");
    if (!SDL_Init(SDL_INIT_VIDEO))
        return false;
    if (c4_sdl_real_driver(SDL_GetCurrentVideoDriver()))
        return true;
    SDL_Quit();
    return SDL_SetError("a real X11 or Wayland display is required");
}

/* The source is an owned native copy, not an image body. Its SDL wrapper
 * borrows it just for this call; the destination surface belongs to SDL. */
static inline bool c4_sdl_copy_rgba(SDL_Surface *dst, int w, int h, uint8_t *pixels)
{
    if (dst->w != w || dst->h != h)
        return SDL_SetError("frame extent does not match the window surface");
    SDL_Surface *src = SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_RGBA32, pixels, w * 4);
    if (!src)
        return false;
    bool ok = SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE) &&
              SDL_BlitSurface(src, NULL, dst, NULL);
    SDL_DestroySurface(src);
    return ok;
}

static inline bool c4_sdl_present_rgba(SDL_Window *win, int w, int h, uint8_t *pixels)
{
    SDL_Surface *dst = SDL_GetWindowSurface(win);
    return dst && c4_sdl_copy_rgba(dst, w, h, pixels) && SDL_UpdateWindowSurface(win);
}

#endif

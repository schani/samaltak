/* Link-only fixture: no SDL display or event subsystem is initialized. */
#include "samaltak.h"
#include <assert.h>
#include <stdio.h>

#ifdef SAMALTAK_C4_PLATFORM_SDL
static unsigned char *staged;
static bool copied, busy;
#endif
static bool queued;
void __real_platform_interface_poll(void);

void __wrap_platform_interface_poll(void)
{
    __real_platform_interface_poll();
    if (!queued) {
        SDL_Event event = {.type = SDL_EVENT_QUIT};
        translate(&event);

        char text[] = "copied \xce\xbb";
#ifdef SAMALTAK_C4_PLATFORM_SDL
        /* A stale window token must not turn into a broadcast. */
        pf_event stale = {.type = PF_EV_TEXT_INPUT, .xkind = PF_X_TEXT,
                          .text = text, .window = 1};
        platform_events_push(&stale);
#endif
        pf_event input = {.type = PF_EV_TEXT_INPUT, .time_ms = 53, .xkind = PF_X_TEXT,
                          .text = text};
        platform_events_push(&input);
        memset(text, '?', sizeof text - 1);
        pf_event wheel = {.type = PF_EV_WHEEL, .time_ms = 54, .x = 42.5, .y = 13.25,
                          .xkind = PF_X_POINT, .dx = -2.5, .dy = 3.25};
        platform_events_push(&wheel);
        queued = true;
    }
#ifdef SAMALTAK_C4_PLATFORM_SDL
    if (!copied && !staged) {
        /* Check a real native primitive entry while bypassing the registry.
         * Zero args is valid for clipboardGet; it must not even try video. */
        const int32_t saved = prim_status, error = prim_error_code, nargs = prim_nargs;
        prim_status = PS_OK;
        prim_error_code = 123;
        prim_nargs = 0;
        prim_clipboard_get();
        assert(prim_status == PS_FAIL && prim_error_code == -1);
        prim_status = saved;
        prim_error_code = error;
        prim_nargs = nargs;

        prim_status = PS_OK;
        prim_error_code = 123;
        prim_nargs = 0;
        prim_jit_parameters();
        assert(prim_status == PS_FAIL && prim_error_code == -1);
        prim_status = saved;
        prim_error_code = error;
        prim_nargs = nargs;

        oop owner = string_from_utf8("xYz!", 4);
        push_root(&owner);
        assert(!stage_rgba(owner, 8));
        staged = stage_rgba(owner, 4);
        pop_root();
        assert(staged);
        /* The SDL source must not be inside the image arena even while
         * owner is live. Verify content later, after dropping the root. */
        assert((uintptr_t)staged < old_lo || (uintptr_t)staged >= old_lo + max_heap_bytes);
        /* Don't keep an oop in the fixture. Wait for a busy-to-idle cycle. */
    }
    if (staged && c4_heap_busy())
        busy = true;
    if (staged && busy && !c4_heap_busy()) {
        SDL_Surface *surface = SDL_CreateSurface(1, 1, SDL_PIXELFORMAT_BGRA32);
        Uint8 r, g, b, a;
        assert(surface);
        assert(!c4_sdl_copy_rgba(surface, 2, 1, staged));
        assert(c4_sdl_copy_rgba(surface, 1, 1, staged));
        assert(SDL_ReadSurfacePixel(surface, 0, 0, &r, &g, &b, &a));
        assert(r == 'x' && g == 'Y' && b == 'z' && a == '!');
        SDL_DestroySurface(surface);
        free(staged);
        staged = NULL;
        copied = true;
        fprintf(stderr, "C4 SDL staged pixels survived a C4 cycle\n");
    }
#endif
}

#ifdef SAMALTAK_C4_PLATFORM_SDL
bool __wrap_SDL_Init(SDL_InitFlags flags)
{
    (void)flags;
    abort(); /* Any attempted display init is a failing headless test. */
}
#endif

/* CI only: verify the X server's window pixels, not a VM-side framebuffer. */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned channel(unsigned long pixel, unsigned long mask)
{
    if (!mask) return 0;
    while (!(mask & 1)) { mask >>= 1; pixel >>= 1; }
    return ((pixel & mask) * 255 + mask / 2) / mask;
}

int main(int argc, char **argv)
{
    if (argc != 5) return 2;
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "XOpenDisplay failed\n");
        return 2;
    }
    Window win = strtoul(argv[1], NULL, 0);
    XWindowAttributes attrs;
    if (!XGetWindowAttributes(display, win, &attrs) || attrs.map_state != IsViewable ||
        attrs.width != 128 || attrs.height != 96)
        return 1;
    XImage *im = XGetImage(display, win, 32, 24, 1, 1, AllPlanes, ZPixmap);
    if (!im) return 1;
    unsigned long v = XGetPixel(im, 0, 0);
    unsigned r = channel(v, attrs.visual->red_mask), g = channel(v, attrs.visual->green_mask),
             b = channel(v, attrs.visual->blue_mask);
    XDestroyImage(im);
    XCloseDisplay(display);
    if (r != strtoul(argv[2], NULL, 10) || g != strtoul(argv[3], NULL, 10) || b != strtoul(argv[4], NULL, 10)) return 1;
    printf("X11 framebuffer %u %u %u\n", r, g, b);
    return 0;
}

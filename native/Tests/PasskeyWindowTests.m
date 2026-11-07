// Run against the compiled passkey engine on a macOS desktop.
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#include <stdio.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        void *framework = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!framework) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        NSWindow *(*anchor)(NSView *) = dlsym(framework, "browser_webauthn_window_v1");
        if (!anchor) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        NSWindow *first = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,12,12)
                                                      styleMask:NSWindowStyleMaskBorderless
                                                        backing:NSBackingStoreBuffered defer:NO];
        NSWindow *second = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,12,12)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        NSView *container = [NSView new];
        NSView *page = [NSView new];
        [container addSubview:page];
        first.contentView = container;
        if (anchor(page) != nil) return 1;
        [first orderBack:nil];
        [second orderBack:nil];
        if (anchor(page) != first || anchor(second.contentView) != second) return 1;
        container.hidden = YES;
        if (anchor(page) != nil) return 1;
        container.hidden = NO;
        [second.contentView addSubview:page];
        if (anchor(page) != second) return 1;
        [page removeFromSuperview];
        if (anchor(page) != nil || anchor(nil) != nil) return 1;
        [first orderOut:nil];
        [second orderOut:nil];
        puts("PASS document window, two windows, reparenting, hidden ancestor, detached document");
    }
    return 0;
}

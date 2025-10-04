
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
typedef UIView PlatformView;
#else
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
typedef NSView PlatformView;
#endif

// GLOBAL
static PlatformView *g_render_view = nil;
static bool g_initialized = false;

// Pointers to potential runtime functions (searched by dlsym)
typedef void (*fn_bootstrap)(const char *);
typedef void (*fn_void_str)(const char *);
typedef void (*fn_frame)(void);
typedef void (*fn_set_layer)(void *);
typedef int (*fn_is_stub)(void);          // ADDED

static fn_bootstrap g_fn_bootstrap = nullptr;
static fn_frame     g_fn_frame = nullptr;
static fn_void_str  g_fn_change_scene = nullptr;
static fn_void_str  g_fn_send_event = nullptr;
static fn_set_layer g_fn_set_layer = nullptr;
static fn_is_stub g_fn_is_stub = nullptr; // ADDED

static void resolve_symbols() {
    if (g_fn_bootstrap || g_fn_frame) return;
    void *handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) { NSLog(@"[godot_embed] dlopen(NULL) failed."); return; }

    const char *SYMBOL_CANDIDATES_BOOTSTRAP[] = {
        "godot_rn_bootstrap",
        "godot_embed_bootstrap",
        "godot_bootstrap",
        "godot_init", // fallback example name
    };
    const char *SYMBOL_CANDIDATES_FRAME[] = {
        "godot_rn_frame",
        "godot_embed_frame",
        "godot_frame_step",
        "godot_iterate",
    };
    const char *SYMBOL_CANDIDATES_CHANGE_SCENE[] = {
        "godot_rn_change_scene",
        "godot_embed_change_scene",
        "godot_change_scene"
    };
    const char *SYMBOL_CANDIDATES_SEND_EVENT[] = {
        "godot_rn_send_event",
        "godot_embed_send_event",
        "godot_send_event"
    };
    const char *SYMBOL_CANDIDATES_SET_LAYER[] = {
        "godot_rn_set_metal_layer",
        "godot_embed_set_metal_layer",
        "godot_set_metal_layer",
        "godot_set_render_surface"
    };
    const char *SYMBOL_CANDIDATES_IS_STUB[] = { "godot_rn_is_stub" }; // ADDED

    // ADDED: prefer real Godot bridge (rg_main_setup -> map as bootstrap)
    const char *REAL_BRIDGE_SETUP[] = { "rg_main_setup" };
    const char *REAL_BRIDGE_ITER[]  = { "rg_main_iteration" };
    for (auto sym : REAL_BRIDGE_SETUP) {
        if (!g_fn_bootstrap) {
            auto raw = (fn_bootstrap)dlsym(handle, sym);
            if (raw) {
                // Wrapper: Godot bridge has signature (const char*) -> int, we expect void
                g_fn_bootstrap = ^(const char *p) {
                    typedef int (*fn_real_setup)(const char*);
                    ((fn_real_setup)raw)(p);
                };
                NSLog(@"[godot_embed] detected real bootstrap (%s).", sym);
            }
        }
    }
    for (auto sym : REAL_BRIDGE_ITER) {
        if (!g_fn_frame) {
            auto raw = (fn_frame)dlsym(handle, sym);
            if (raw) {
                g_fn_frame = raw;
                NSLog(@"[godot_embed] iteration -> %s", sym);
            }
        }
    }

    for (auto sym : SYMBOL_CANDIDATES_BOOTSTRAP) {
        if (!g_fn_bootstrap) {
            g_fn_bootstrap = (fn_bootstrap)dlsym(handle, sym);
            if (g_fn_bootstrap) NSLog(@"[godot_embed] bootstrap -> %s", sym);
        }
    }
    for (auto sym : SYMBOL_CANDIDATES_FRAME) {
        if (!g_fn_frame) {
            g_fn_frame = (fn_frame)dlsym(handle, sym);
            if (g_fn_frame) NSLog(@"[godot_embed] frame -> %s", sym);
        }
    }
    for (auto sym : SYMBOL_CANDIDATES_CHANGE_SCENE) {
        if (!g_fn_change_scene) {
            g_fn_change_scene = (fn_void_str)dlsym(handle, sym);
            if (g_fn_change_scene) NSLog(@"[godot_embed] change_scene -> %s", sym);
        }
    }
    for (auto sym : SYMBOL_CANDIDATES_SEND_EVENT) {
        if (!g_fn_send_event) {
            g_fn_send_event = (fn_void_str)dlsym(handle, sym);
            if (g_fn_send_event) NSLog(@"[godot_embed] send_event -> %s", sym);
        }
    }
    for (auto sym : SYMBOL_CANDIDATES_SET_LAYER) {
        if (!g_fn_set_layer) {
            g_fn_set_layer = (fn_set_layer)dlsym(handle, sym);
            if (g_fn_set_layer) NSLog(@"[godot_embed] set_layer -> %s", sym);
        }
    }
    // ADDED: detect stub
    if (!g_fn_is_stub) {
        g_fn_is_stub = (fn_is_stub)dlsym(handle, SYMBOL_CANDIDATES_IS_STUB[0]);
        if (g_fn_is_stub) NSLog(@"[godot_embed] is_stub -> %s", SYMBOL_CANDIDATES_IS_STUB[0]);
    }

    if (!g_fn_bootstrap) {
        NSLog(@"[godot_embed][WARN] Bootstrap function not found (rg_main_setup or godot_rn_bootstrap missing).");
    }
}

static PlatformView *create_render_view() {
#if TARGET_OS_IOS || TARGET_OS_TV
    UIView *host = [[UIView alloc] initWithFrame:CGRectZero];
    host.backgroundColor = [UIColor blackColor];
    // CAMetalLayer
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.colorspace = CGColorSpaceCreateDeviceRGB();
    host.layer.masksToBounds = YES;
    [host.layer addSublayer:layer];
    layer.frame = host.layer.bounds;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
#else
    NSView *host = [[NSView alloc] initWithFrame:NSZeroRect];
    host.wantsLayer = YES;
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    host.layer = layer; // no sublayer – main layer
#endif
    if (g_fn_set_layer) {
        g_fn_set_layer((__bridge void *)host.layer);
    } else {
        NSLog(@"[godot_embed][INFO] No set_layer symbol – assuming bootstrap creates surface.");
    }
    return host;
}

extern "C" {

// Initialization – creates view + calls bootstrap if available.
void rn_godot_initialize(const char *project_path_or_null) {
    if (g_initialized) return;
    resolve_symbols();
    g_render_view = create_render_view();
    if (g_fn_bootstrap) {
        g_fn_bootstrap(project_path_or_null);
        NSLog(@"[godot_embed] bootstrap called (project=%s).", project_path_or_null ? project_path_or_null : "nil");
        if (g_fn_is_stub && g_fn_is_stub() == 1) {
            NSLog(@"[godot_embed][INFO] Detected STUB runtime (godot_rn_is_stub=1) – black screen until real integration is provided.");
        }
    } else {
        NSLog(@"[godot_embed][WARN] No bootstrap – Godot did not actually start.");
    }
    g_initialized = true;
}

// Scene change – delegates to change_scene function if available.
void rn_godot_change_scene(const char *scene_path) {
    if (g_fn_change_scene) {
        g_fn_change_scene(scene_path);
    } else {
        NSLog(@"[godot_embed][WARN] change_scene not available – add symbol (scene=%s).", scene_path ? scene_path : "(null)");
    }
}

// Event sending – delegates to send_event function if available.
void rn_godot_send_event(const char *event_name) {
    if (g_fn_send_event) {
        g_fn_send_event(event_name);
    } else {
        NSLog(@"[godot_embed][WARN] send_event missing – symbol not found (event=%s).", event_name ? event_name : "(null)");
    }
}

// Return renderer view (UIView*/NSView*)
void *rn_godot_get_view(void) {
    return (__bridge void *)g_render_view;
}

// Frame loop (if RN / Swift finds symbol rn_godot_frame – will be called)
// Removed rainbow animation; real runtime function call if it exists.
void rn_godot_frame(void) {
    if (g_fn_frame) {
        g_fn_frame();
    }
    // No else – if there is no frame function, we assume the engine renders by itself (or does nothing).
}

} // extern "C"

// (Optional) out‑of‑band message channel
extern "C" __attribute__((weak)) void message_callback(const char *channel, const char *json_payload) {
    if (channel) NSLog(@"[godot_embed] message_callback %s", channel);
}
//
// Why don't we provide a READY-MADE "real" Godot bootstrap?
// 1. API Stability: The official Godot startup point (Main::setup / Main::start / OS / DisplayServer)
//    does not have a guaranteed stable C ABI between versions. Exposing ready-made
//    calls increases the risk that the next 4.x / 5.x version will stop working
//    without warning (break in binary symbols or initialization sequence).
// 2. Size and dependencies: True embed requires a number of headers + initialization
//    of subsystems (filesystem, input, audio, drivers, threads). We would have to add
//    a large chunk of platform code (duplication of part of main/platform). This would cause
//    harder updates, higher "surface area" for debugging, and greater weight
//    of the npm package.
// 3. Flexibility: Different users want different modes: own frame loop with
//    CADisplayLink, internal Godot thread, integration with existing Metal app
//    or temporary "headless" processing. Stub + dynamic symbol searching
//    dlsym gives freedom of implementation on the integrator's side (You decide what and when
//    you initialize).
// 4. Legal / licensing restrictions: Godot is MIT – OK for distribution – but
//    maintaining forked fragments of platform/main in the RN repo makes it difficult to clearly
//    track upstream changes (easier to update clean prebuild .a and give a thin
//    C interface).
// 5. Version detection: Users can replace libgodot*.a with other variants (own
//    builds, feature toggles). Minimalist C shim + dlsym allows to run
//    anything, as long as the required symbols are provided (godot_rn_bootstrap etc.).
//
// In short: the package provides a "rail" (C API + host view + call loop) and diagnostic tools;
// *You* provide the actual bridge to the engine considering
// your version, plugins, assets, and thread policy.
//
// === How to make a real bootstrap? (Outline – pseudocode) ======================
// 1. Build Godot with build_library=yes (which we already do) or prepare your own
//    static library/xcframework with internal symbols.
// 2. Add a C++ file (e.g. ios/real_bootstrap.mm) compiled together with libgodot*.a.
// 3. In this file implement:
//      extern "C" int  godot_rn_is_stub() { return 0; }
//      extern "C" void godot_rn_set_metal_layer(void *layer);
//      extern "C" void godot_rn_bootstrap(const char *project_dir_or_pck);
//      extern "C" void godot_rn_frame();
//      extern "C" void godot_rn_change_scene(const char *res_path);
//      extern "C" void godot_rn_send_event(const char *evt);
// 4. In godot_rn_bootstrap:
//      - Keep the project path.
//      - Build the argument table (e.g. ["godot", "--path", project_dir]).
//      - Call the internal initialization procedure (analogous to Main::setup).
//        (Here you most often need access to the appropriate headers – if you don't want them
//         to copy, you create minimal C wrappers when compiling the engine.)
//      - Create/inform the renderer about CAMetalLayer (see godot_rn_set_metal_layer).
// 5. In godot_rn_set_metal_layer: you pass a pointer/reference to the backend
//    of the renderer (MetalDevice / DisplayServer / RenderingServer – depending on the version).
// 6. In godot_rn_frame (if you choose manual loop):
//      - Call the main loop step (e.g. Main::iteration() or analog).
//      - Delegate render / commit (depending on how you configured the backend).
//    If you use an internal thread – this step may be empty.
// 7. change_scene / send_event: through GDNative / internal API (SceneTree::change_scene_to_file,
//    or through global singleton / autoload). In a simple variant you can map
//    these calls to a task queue executed in godot_rn_frame on the render/logic thread.
// 8. Replace stub in CI: in the workflow (Package runtime) remove the generation of
//    rn_godot_runtime_bridge.c and include your file (keep the symbol names).
// 9. Make sure the symbol rn_godot_frame exists only if *you really*
//    expect calls from CADisplayLink/Timer (otherwise Swift will not start the loop).
// 10. Log errors (stderr) – RN Metro/Xcode will show them in the console.
//
// The code below (further) remains a skeleton that:
//  - creates view + CAMetalLayer,
//  - searches symbols dynamically,
//  - calls provided functions if they are,
//  - DOES NOT implement true "Main" of Godot.
//
// ============================================================================

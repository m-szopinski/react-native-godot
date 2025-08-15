//
// real_bootstrap_example.mm
// Minimalny SZKIELET prawdziwego bootstrapu – zastępuje stub (godot_rn_is_stub=1).
// Uzupełnij miejsca oznaczone TODO realnymi wywołaniami Twojej wbudowanej wersji Godota.
//
// WYMAGANIA:
// 1. Zbuduj Godot z build_library=yes (jak już robisz).
// 2. W swoim fork’u / patchu Godota dodaj / odsłoń funkcje C (przykład):
//      extern "C" int  rg_main_setup(int argc, char **argv);        // return 0 on success
//      extern "C" void rg_main_iteration();                         // pojedynczy krok
//      extern "C" void rg_main_finalize();                          // sprzątanie
//      extern "C" void rg_set_metal_layer(void *layer);             // przekazanie CAMetalLayer
//    (Nazwy dowolne – dopasuj do listy SYMBOL_* poniżej.
//     Możesz też zamiast dlsym linkować bezpośrednio jeśli symbole są w static .a)
// 3. Usuń (lub pozostaw, ale nie kompiluj) plik stub: rn_godot_runtime_bridge.c / godot_runtime_stub.c.
// 4. Ten plik MUSI być w Compile Sources (Objective-C++).
// 5. Funkcje godot_rn_* poniżej nadpisują stub z paczki.
//
// Po sukcesie logi NIE powinny zawierać „STUB”.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
typedef UIView PlatformView;
#else
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
typedef NSView PlatformView;
#endif

// ===== Global state =====
static PlatformView *g_render_view = nil;
static CAMetalLayer *g_metal_layer = nil;
static bool g_initialized = false;
static bool g_have_iteration = false;
static bool g_have_finalize = false;

// Pointers do funkcji runtime (rozwiązywane przez dlsym lub link-time)
typedef int  (*fn_setup)(int, char **);
typedef void (*fn_iter)(void);
typedef void (*fn_fin)(void);
typedef void (*fn_set_layer)(void *);

static fn_setup     g_fn_setup = nullptr;
static fn_iter      g_fn_iter = nullptr;
static fn_fin       g_fn_fin = nullptr;
static fn_set_layer g_fn_set_layer = nullptr;

// DODANE – wskaźniki dodatkowych funkcji
typedef void (*fn_req_scene)(const char*);
typedef void (*fn_req_event)(const char*);
static fn_req_scene g_fn_req_scene = nullptr;
static fn_req_event g_fn_req_event = nullptr;

// ===== Symbol resolution =====
static void resolve_runtime_symbols() {
    if (g_fn_setup) return;
    void *h = dlopen(NULL, RTLD_LAZY);
    if (!h) { NSLog(@"[real_bootstrap] dlopen(NULL) fail"); return; }

    const char *SYMBOL_SETUP[]     = { "rg_main_setup", "godot_rn_internal_setup" };
    const char *SYMBOL_ITER[]      = { "rg_main_iteration", "godot_rn_internal_iteration" };
    const char *SYMBOL_FIN[]       = { "rg_main_finalize", "godot_rn_internal_finalize" };
    const char *SYMBOL_SET_LAYER[] = { "rg_set_metal_layer", "godot_rn_set_metal_layer" };
    const char *SYMBOL_REQ_SCENE[] = { "rg_request_change_scene" };
    const char *SYMBOL_REQ_EVENT[] = { "rg_request_event" };

    for (auto s : SYMBOL_SETUP) if (!g_fn_setup)     { g_fn_setup     = (fn_setup)dlsym(h, s); if (g_fn_setup) NSLog(@"[real_bootstrap] setup -> %s", s); }
    for (auto s : SYMBOL_ITER)  if (!g_fn_iter)      { g_fn_iter      = (fn_iter)dlsym(h, s); if (g_fn_iter)  NSLog(@"[real_bootstrap] iter  -> %s", s); }
    for (auto s : SYMBOL_FIN)   if (!g_fn_fin)       { g_fn_fin       = (fn_fin)dlsym(h, s); if (g_fn_fin)   NSLog(@"[real_bootstrap] fin   -> %s", s); }
    for (auto s : SYMBOL_SET_LAYER) if (!g_fn_set_layer) { g_fn_set_layer = (fn_set_layer)dlsym(h, s); if (g_fn_set_layer) NSLog(@"[real_bootstrap] set_layer -> %s", s); }
    for (auto s : SYMBOL_REQ_SCENE) if (!g_fn_req_scene) { g_fn_req_scene = (fn_req_scene)dlsym(h, s); if (g_fn_req_scene) NSLog(@"[real_bootstrap] req_scene -> %s", s); }
    for (auto s : SYMBOL_REQ_EVENT) if (!g_fn_req_event) { g_fn_req_event = (fn_req_event)dlsym(h, s); if (g_fn_req_event) NSLog(@"[real_bootstrap] req_event -> %s", s); }

    if (!g_fn_setup) NSLog(@"[real_bootstrap][ERR] Brak funkcji setup – musisz ją wyeksportować w swoim buildzie Godota.");
}

// ===== View / Metal layer =====
static PlatformView *create_host_view() {
#if TARGET_OS_IOS || TARGET_OS_TV
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor blackColor];
    g_metal_layer = [CAMetalLayer layer];
    g_metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    g_metal_layer.framebufferOnly = YES;
    g_metal_layer.frame = v.bounds;
    g_metal_layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [v.layer addSublayer:g_metal_layer];
#else
    NSView *v = [[NSView alloc] initWithFrame:NSZeroRect];
    v.wantsLayer = YES;
    g_metal_layer = [CAMetalLayer layer];
    g_metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    g_metal_layer.frame = v.bounds;
    g_metal_layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    v.layer = g_metal_layer;
#endif
    return v;
}

// ===== API required przez Swift (public) =====
extern "C" int  godot_rn_is_stub(void) { return 0; }

// Inicjalizacja – zastępuje stubową
extern "C" void godot_rn_bootstrap(const char *project_or_pck) {
    if (g_initialized) return;
    resolve_runtime_symbols();
    g_render_view = create_host_view();

    if (g_fn_set_layer && g_metal_layer) {
        g_fn_set_layer((__bridge void *)g_metal_layer);
    } else {
        NSLog(@"[real_bootstrap][WARN] brak funkcji set_layer – zakładam automatyczne tworzenie surface w silniku.");
    }

    if (!g_fn_setup) {
        NSLog(@"[real_bootstrap][FATAL] nie można uruchomić – brak g_fn_setup.");
        return;
    }

    // Przygotuj argumenty (jak uruchomienie godot z --path)
    // TODO: jeśli używasz .pck zamiast katalogu – dodaj odpowiednie flagi (--main-pack)
    const char *path = project_or_pck;
    const char *argv_local[4];
    int argc = 1;
    argv_local[0] = "godot";
    if (path) {
        argv_local[argc++] = "--path";
        argv_local[argc++] = path;
    }
    // (opcjonalnie) argv_local[argc++] = "--rendering-driver"; ...

    int rc = g_fn_setup(argc, (char **)argv_local);
    if (rc != 0) {
        NSLog(@"[real_bootstrap][ERR] setup zwrócił %d – sprawdź swoje hooki.", rc);
    } else {
        NSLog(@"[real_bootstrap] setup OK (project=%s).", path ? path : "nil");
    }

    g_have_iteration = (g_fn_iter != nullptr);
    g_have_finalize  = (g_fn_fin  != nullptr);
    g_initialized = true;
}

// Wywoływane co klatkę (jeśli Swift wykrył rn_godot_frame i uruchomił CADisplayLink/Timer)
extern "C" void godot_rn_frame(void) {
    if (g_have_iteration) {
        g_fn_iter();
    }
}

// Zmiana sceny – wymaga własnego hooka (kolejkujesz i wykonujesz wewnątrz iteration) – pokazujemy prosty placeholder.
extern "C" void godot_rn_change_scene(const char *res_path) {
    if (g_fn_req_scene && res_path) {
        g_fn_req_scene(res_path);
    } else {
        NSLog(@"[real_bootstrap] change_scene request: %s (kolejkuj / brak rg_request_change_scene)", res_path ? res_path : "(null)");
    }
}

// Prosty kanał eventów (kolejkuj do przetworzenia w iteration)
extern "C" void godot_rn_send_event(const char *evt) {
    if (g_fn_req_event && evt) {
        g_fn_req_event(evt);
    } else {
        NSLog(@"[real_bootstrap] event: %s (kolejkuj / brak rg_request_event)", evt ? evt : "(null)");
    }
}

// Pętla metal layer (już przejęta w bootstrap – nic tu nie robimy)
extern "C" void godot_rn_set_metal_layer(void *layer) {
    // Możesz pominąć jeśli używasz rg_set_metal_layer wcześniej.
    NSLog(@"[real_bootstrap] set_metal_layer external call ignorowane (użyto podczas bootstrapu).");
}

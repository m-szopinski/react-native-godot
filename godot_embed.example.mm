//
// Przykładowy embed: inicjalizacja Godot zamiast kolorowej “tęczy”.
// Skopiuj jako godot_embed.mm i ewentualnie dostosuj nazwy symboli bootstrapu.
// Ten plik próbuje dynamicznie odnaleźć funkcje w prekompilowanej libgodot*.a (build_library=yes).
//
// OCZEKIWANE (przynajmniej część – możesz zmienić nazwy, ale zaktualizuj listy SYMBOL_CANDIDATES_*):
//   extern "C" void godot_rn_bootstrap(const char *project_or_pck);
//   extern "C" void godot_rn_set_metal_layer(void *layer_or_view);
//   extern "C" void godot_rn_frame(void);
//   (opcjonalnie) extern "C" void godot_rn_change_scene(const char *res_path);
//   (opcjonalnie) extern "C" void godot_rn_send_event(const char *evt);
//
// Jeśli nie dostarczysz bootstrapu – silnik nie ruszy (log ostrzeże).
//
// UWAGA: Wersja CI dodaje STUB (godot_rn_is_stub == 1) – daje czarne tło. Aby zobaczyć scenę:
// 1. Zaimplementuj własny godot_rn_bootstrap (inicjalizacja Godot + załadowanie projektu / main loop).
// 2. Zaimplementuj godot_rn_frame (jeśli potrzebujesz ręcznej pętli) oraz godot_rn_set_metal_layer (Metal).
// 3. Upewnij się, że projekt jest w bundlu (s.resources = ['godot-project/**/*']).
//

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

// Wskaźniki na potencjalne funkcje runtime (wyszukane przez dlsym)
typedef void (*fn_bootstrap)(const char *);
typedef void (*fn_void_str)(const char *);
typedef void (*fn_frame)(void);
typedef void (*fn_set_layer)(void *);
typedef int (*fn_is_stub)(void);          // DODANE

static fn_bootstrap g_fn_bootstrap = nullptr;
static fn_frame     g_fn_frame = nullptr;
static fn_void_str  g_fn_change_scene = nullptr;
static fn_void_str  g_fn_send_event = nullptr;
static fn_set_layer g_fn_set_layer = nullptr;
static fn_is_stub g_fn_is_stub = nullptr; // DODANE

static void resolve_symbols() {
    if (g_fn_bootstrap || g_fn_frame) return;
    void *handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) { NSLog(@"[godot_embed] dlopen(NULL) niepowodzenie."); return; }

    const char *SYMBOL_CANDIDATES_BOOTSTRAP[] = {
        "godot_rn_bootstrap",
        "godot_embed_bootstrap",
        "godot_bootstrap",
        "godot_init", // fallback nazwa przykładowa
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
    const char *SYMBOL_CANDIDATES_IS_STUB[] = { "godot_rn_is_stub" }; // DODANE

    // DODANE: preferuj realny bridge Godota (rg_main_setup -> mapujemy jako bootstrap)
    const char *REAL_BRIDGE_SETUP[] = { "rg_main_setup" };
    const char *REAL_BRIDGE_ITER[]  = { "rg_main_iteration" };
    for (auto sym : REAL_BRIDGE_SETUP) {
        if (!g_fn_bootstrap) {
            auto raw = (fn_bootstrap)dlsym(handle, sym);
            if (raw) {
                // Owijka: Godot bridge ma sygnaturę (const char*) -> int, my oczekujemy void
                g_fn_bootstrap = ^(const char *p) {
                    typedef int (*fn_real_setup)(const char*);
                    ((fn_real_setup)raw)(p);
                };
                NSLog(@"[godot_embed] wykryto realny bootstrap (%s).", sym);
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
    // DODANE: wykrycie stuba
    if (!g_fn_is_stub) {
        g_fn_is_stub = (fn_is_stub)dlsym(handle, SYMBOL_CANDIDATES_IS_STUB[0]);
        if (g_fn_is_stub) NSLog(@"[godot_embed] is_stub -> %s", SYMBOL_CANDIDATES_IS_STUB[0]);
    }

    if (!g_fn_bootstrap) {
        NSLog(@"[godot_embed][WARN] Nie znaleziono funkcji bootstrap (brak rg_main_setup ani godot_rn_bootstrap).");
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
    host.layer = layer; // bez sublayer – warstwa główna
#endif
    if (g_fn_set_layer) {
        g_fn_set_layer((__bridge void *)host.layer);
    } else {
        NSLog(@"[godot_embed][INFO] Brak set_layer symbol – zakładam, że bootstrap sam tworzy surface.");
    }
    return host;
}

extern "C" {

// Inicjalizacja – tworzy view + wywołuje bootstrap jeśli dostępny.
void rn_godot_initialize(const char *project_path_or_null) {
    if (g_initialized) return;
    resolve_symbols();
    g_render_view = create_render_view();
    if (g_fn_bootstrap) {
        g_fn_bootstrap(project_path_or_null);
        NSLog(@"[godot_embed] bootstrap wywołany (project=%s).", project_path_or_null ? project_path_or_null : "nil");
        if (g_fn_is_stub && g_fn_is_stub() == 1) {
            NSLog(@"[godot_embed][INFO] Wykryto STUB runtime (godot_rn_is_stub=1) – czarne tło do czasu dostarczenia realnej integracji.");
        }
    } else {
        NSLog(@"[godot_embed][WARN] Brak bootstrap – brak faktycznego startu Godot.");
    }
    g_initialized = true;
}

// Zmiana sceny – deleguje do funkcji change_scene jeśli istnieje.
void rn_godot_change_scene(const char *scene_path) {
    if (g_fn_change_scene) {
        g_fn_change_scene(scene_path);
    } else {
        NSLog(@"[godot_embed][WARN] change_scene niedostępne – dodaj symbol (scene=%s).", scene_path ? scene_path : "(null)");
    }
}

// Wysyłanie eventu – deleguje do funkcji send_event jeśli istnieje.
void rn_godot_send_event(const char *event_name) {
    if (g_fn_send_event) {
        g_fn_send_event(event_name);
    } else {
        NSLog(@"[godot_embed][WARN] send_event brak – symbol nie znaleziony (event=%s).", event_name ? event_name : "(null)");
    }
}

// Zwrócenie widoku renderera (UIView*/NSView*)
void *rn_godot_get_view(void) {
    return (__bridge void *)g_render_view;
}

// Pętla klatek (jeśli RN / Swift znajduje symbol rn_godot_frame – będzie wywoływane)
// Usunięto tęczową animację; wywołanie realnej funkcji runtime jeśli istnieje.
void rn_godot_frame(void) {
    if (g_fn_frame) {
        g_fn_frame();
    }
    // Brak else – jeśli nie ma funkcji frame przyjmujemy, że silnik sam renderuje (lub nic nie robi).
}

} // extern "C"

// (Opcjonalny) kanał wiadomości out‑of‑band
extern "C" __attribute__((weak)) void message_callback(const char *channel, const char *json_payload) {
    if (channel) NSLog(@"[godot_embed] message_callback %s", channel);
}
//
// Dlaczego nie dostarczamy GOTOWEGO “prawdziwego” bootstrapu Godota?
// 1. Stabilność API: Oficjalny punkt startu Godot (Main::setup / Main::start / OS / DisplayServer)
//    nie ma gwarantowanego stabilnego C ABI między wersjami. Wystawienie na sztywno
//    gotowych wywołań zwiększa ryzyko, że kolejna wersja 4.x / 5.x przestanie działać
//    bez ostrzeżenia (break w binarnych symbolach lub sekwencji inicjalizacji).
// 2. Rozmiar i zależności: Prawdziwy embed wymaga szeregu nagłówków + inicjalizacji
//    podsyst. (filesystem, input, audio, drivers, threads). Musielibyśmy dorzucić
//    duży kawał kodu platformowego (duplikacja części main/platform). To spowodowałoby
//    trudniejsze aktualizacje, wyższy „surface area” do debugowania i większy ciężar
//    paczki npm.
// 3. Elastyczność: Różni użytkownicy chcą różnych trybów: własna pętla klatek z
//    CADisplayLink, wątek wewnętrzny Godota, integracja z istniejącą aplikacją Metal
//    albo tymczasowe “headless” przetwarzanie. Stub + dynamiczne szukanie symboli
//    dlsym daje swobodę implementacji po stronie integratora (Ty decydujesz co i kiedy
//    inicjalizujesz).
// 4. Ograniczenia prawne / licencyjne: Godot jest MIT – OK do dystrybucji – ale
//    utrzymywanie zforkowanych fragmentów platform/main w repo RN utrudnia jasne
//    śledzenie zmian upstream (łatwiej aktualizować czyste prebuild .a i dać cienki
//    interfejs C).
// 5. Detekcja wersji: Użytkownicy mogą podmieniać libgodot*.a na inne warianty (własne
//    buildy, feature toggles). Minimalistyczny C shim + dlsym pozwala odpalić
//    cokolwiek, byleby dostarczyć wymagane symbole (godot_rn_bootstrap itp.).
//
// W skrócie: paczka daje “szynę” (C API + host view + pętla wywołań) i narzędzia
// diagnostyczne; *Ty* dostarczasz właściwy most do silnika z uwzględnieniem
// swojej wersji, pluginów, assetów i polityki wątku.
//
// === Jak zrobić prawdziwy bootstrap? (Szkic – pseudokod) ======================
// 1. Zbuduj Godot z build_library=yes (co już robimy) lub przygotuj własną
//    bibliotekę statyczną/xcframework z symbolami wewnętrznymi.
// 2. Dodaj plik C++ (np. ios/real_bootstrap.mm) kompilowany razem z libgodot*.a.
// 3. W tym pliku zaimplementuj:
//      extern "C" int  godot_rn_is_stub() { return 0; }
//      extern "C" void godot_rn_set_metal_layer(void *layer);
//      extern "C" void godot_rn_bootstrap(const char *project_dir_or_pck);
//      extern "C" void godot_rn_frame();
//      extern "C" void godot_rn_change_scene(const char *res_path);
//      extern "C" void godot_rn_send_event(const char *evt);
// 4. W godot_rn_bootstrap:
//      - Zachowaj ścieżkę projektu.
//      - Zbuduj tablicę argumentów (np. ["godot", "--path", project_dir]).
//      - Wywołaj wewnętrzną procedurę inicjalizacji (analogiczną do Main::setup).
//        (Tu najczęściej trzeba mieć dostęp do odpowiednich nagłówków – jeśli ich
//         nie chcesz kopiować, tworzysz minimalne C wrappery przy kompilacji silnika.)
//      - Utwórz/poinformuj renderer o CAMetalLayer (patrz godot_rn_set_metal_layer).
// 5. W godot_rn_set_metal_layer: przekazujesz wskaźnik / referencję do backendu
//    renderera (MetalDevice / DisplayServer / RenderingServer – zależnie od wersji).
// 6. W godot_rn_frame (jeśli wybierasz ręczną pętlę):
//      - Wywołaj step pętli głównej (np. Main::iteration() albo analog).
//      - Zleć render / commit (zależnie od tego jak skonfigurowałeś backend).
//    Jeśli używasz wątku wewnętrznego – ten krok może być pusty.
// 7. change_scene / send_event: przez GDNative / internal API (SceneTree::change_scene_to_file,
//    lub przez globalny singleton / autoload). W prostym wariancie możesz zmapować
//    te wywołania na kolejkę zadań wykonywaną w godot_rn_frame na wątku render/logic.
// 8. Podmień stub w CI: w workflow (Package runtime) usuń generowanie
//    rn_godot_runtime_bridge.c i dołącz swój plik (zachowaj nazwy symboli).
// 9. Upewnij się, że symbol rn_godot_frame istnieje tylko jeśli *rzeczywiście*
//    oczekujesz wywołań z CADisplayLink/Timer (inaczej Swift nie uruchomi pętli).
// 10. Loguj błędy (stderr) – RN Metro/Xcode pokażą je w konsoli.
//
// Poniższy kod (dalej) pozostaje szkieletem, który:
//  - tworzy widok + CAMetalLayer,
//  - szuka dynamicznie symboli,
//  - wywołuje dostarczone funkcje jeśli są,
//  - NIE implementuje prawdziwego “Main” Godota.
//
// ============================================================================

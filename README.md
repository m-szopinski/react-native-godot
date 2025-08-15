# react-native-godot (macOS / iOS)

Po instalacji paczki silnik (RealGodotEngine) jest aktywny automatycznie – wrapper `rn_godot_*` dostarczony jako strong implementacje, a `godot_embed.example.mm` zwraca gotowy widok renderera (placeholder + pętla koloru, który możesz zastąpić pełnym renderem Godota gdy rozszerzysz integrację).

## Quick Start

```bash
npm install @m-szopinski/react-native-godot
(cd ios && pod install)
```

JS:
```tsx
<GodotView style={{flex:1}}
  projectPath="godot-project"
  mainScene="res://scenes/TestScene.tscn" />
```

Silnik startuje, symbole `rn_godot_*` dostępne (link-time), `RealGodotEngine` tworzony automatycznie.

## Integracja (React Native + CocoaPods)

1. `npm install @m-szopinski/react-native-godot`
2. `cd ios && pod install`
3. Otwórz `.xcworkspace` w Xcode.
4. W Pods -> Development Pods widoczny `RNGodot` (z katalogiem `GodotRuntimeDist` zawierającym prebuilt `libgodot_*.a` lub template).
5. Uruchom aplikację (iOS / macOS Catalyst / macOS RN) – zobaczysz placeholder animujący kolor.
6. Aby dodać własny runtime / rendering:
   - `cp node_modules/@m-szopinski/react-native-godot/godot_embed.example.mm ios/godot_embed.mm`
   - Dodaj `godot_embed.mm` do targetu (Objective-C++).
   - W `godot_embed.mm` wdroż realne: inicjalizację Godot, zwrot widoku (`UIView*/NSView*`), opcjonalną pętlę (`rn_godot_frame`).
7. (Opcjonalnie) Zbuduj własne biblioteki (sekcja “Własny build runtime”) i podmień `GodotRuntimeDist`.
8. Jeśli linker zgłasza brak `rn_godot_*`: upewnij się, że nie usunięto `rn_godot_wrapper.c` (lub że Twój `godot_embed.mm` wystawia symbole).

Debug skróty:
- Brak widoku: `rn_godot_get_view` zwraca `NULL`.
- Lista oczekiwanych symboli: `ref.current?.diagnoseStub()`.

## FAQ (integracja)

- Czy muszę ustawiać Header Search Paths? Nie.
- Czy potrzebne `-ObjC`? Zwykle nie (tylko gdy dodasz kategorie ObjC).
- Czy potrzebny bridging header? Nie – Swift + jeden `.mm` z C API wystarcza.
- Jak dodać własne funkcje? Dodaj w `godot_embed.mm` jako `extern "C"` i wywołuj przez dlsym lub eksportuj bezpośrednio.
- Co jeśli `rn_godot_get_view` zwraca nil? Upewnij się, że inicjalizacja silnika wykonała się przed pierwszym pobraniem widoku.
- Czy muszę mieć projekt Godot w bundle? Nie – możesz podać ścieżkę do `.pck` lub zostawić null (stub / własna logika).

## Minimalny kontrakt symboli

```c
void rn_godot_initialize(const char *project_or_pck);
void rn_godot_change_scene(const char *res_scene);
void rn_godot_send_event(const char *evt);
void *rn_godot_get_view(void); // UIView*/NSView*
void rn_godot_frame(void);     // opcjonalne
```

## Własny build runtime (skrót)

1. Ustaw `VULKAN_SDK`.
2. `./build-godot.sh`
3. Podmień `GodotRuntimeDist`.
4. Przebuduj aplikację.

## Rozszerzenie do pełnego renderu Godot

Obecny wrapper dołącza minimalny placeholder (`godot_embed.example.mm`). Aby uzyskać prawdziwy rendering (Metal / GL) wykonaj poniższe kroki.

### 1. Kopiowanie i dodanie pliku
```bash
cp node_modules/@m-szopinski/react-native-godot/godot_embed.example.mm ios/godot_embed.mm
```
W Xcode: Add Files… -> wybierz `ios/godot_embed.mm` -> zaznacz swój target. Upewnij się, że typ kompilacji to Objective-C++ (rozszerzenie .mm wystarcza).

### 2. Cele implementacji
Zaimplementujesz funkcje C:
```
rn_godot_initialize
rn_godot_change_scene
rn_godot_send_event
rn_godot_get_view
rn_godot_frame (opcjonalne – pętla)
```
One są wołane z warstwy Swift (RealGodotEngine). Parametr `project` pochodzi z prop `projectPath` lub wykrytej .pck; `mainScene` z propa lub auto z `project.godot`.

### 3. Artefakty runtime
Masz już prebuilt `GodotRuntimeDist` (statyczne libgodot*.a). Jeśli budujesz własne – podmień pliki przed implementacją (lub później – interfejs C pozostaje identyczny).

### 4. Inicjalizacja silnika
We wnętrzu `rn_godot_initialize`:
- Załaduj projekt: jeśli argument kończy się `.pck` -> użyj jako pakiet; jeśli katalog -> wskaż folder projektu.
- Skonfiguruj ścieżki (godot_main/osx / platform init – zależnie od sposobu embedowania).
- Utwórz obiekt / singleton runtime i utrzymaj w statycznych zmiennych.

Pseudo (fragment – zastąp komentarze własnymi wywołaniami Godota):
```objectivec
static bool g_initialized = false;
static PlatformView *g_render_view = nil;

extern "C" void rn_godot_initialize(const char *project_path_or_pck) {
    if (g_initialized) return;
    // 1. Parse ścieżkę
    // 2. Wywołaj bootstrap Godot (np. godot::gdn_interface / internal main init)
    // 3. Utwórz surface (CAMetalLayer / NSView layer-backed)
#if TARGET_OS_IOS || TARGET_OS_TV
    g_render_view = [[UIView alloc] initWithFrame:CGRectZero];
    g_render_view.layer = [CAMetalLayer layer];
    ((CAMetalLayer*)g_render_view.layer).pixelFormat = MTLPixelFormatBGRA8Unorm;
#else
    g_render_view = [[NSView alloc] initWithFrame:NSZeroRect];
    g_render_view.wantsLayer = YES;
    g_render_view.layer = [CAMetalLayer layer];
#endif
    // 4. Przekaż layer / drawable do Godot (custom hook)
    // 5. Start main loop (jeśli Godot oczekuje manualnego loopu – uruchom w tle / rely on rn_godot_frame)
    g_initialized = true;
}
```

### 5. Widok renderera
`rn_godot_get_view` ma zwracać `UIView*` lub `NSView*` (bridge w Swift zrobi cast). Nigdy nie zwracaj tymczasowego obiektu – przechowuj globalnie. Jeśli Godot tworzy własny NSView/UIView – zwróć go bezpośrednio.

```objectivec
extern "C" void *rn_godot_get_view(void) {
    return (__bridge void*)g_render_view;
}
```

### 6. Pętla klatek
Masz dwa warianty:
- Godot obsługuje własny wątek loopa -> możesz zostawić pusty `rn_godot_frame`.
- Manualny tick -> implementujesz logikę (process / draw) i RealGodotEngine będzie wywoływał `rn_godot_frame` przez CADisplayLink / Timer.

```objectivec
extern "C" void rn_godot_frame(void) {
    // 1. Poll input (opcjonalnie)
    // 2. Step main loop (np. godot_iterate(delta))
    // 3. Render (commit do CAMetalLayer)
}
```

### 7. Zmiana sceny / zdarzenia
Funkcje:
```objectivec
extern "C" void rn_godot_change_scene(const char *res_path) {
    // Wywołaj API Godot do przełączenia sceny (np. użycie SceneTree)
}
extern "C" void rn_godot_send_event(const char *evt) {
    // Kanał prostych stringów lub JSON -> dispatch do scriptu / autoload singleton
}
```
Warstwa JS:
```tsx
ref.current?.setScene("res://scenes/Playground.tscn");
ref.current?.sendEvent("ping");
```

### 8. Ładowanie projektu i `mainScene`
- Jeśli `projectPath` wskazuje katalog: Swift spróbuje znaleźć `run/main_scene` w `project.godot`.
- Jeśli ustawisz `mainScene` w propsie – zostanie wymuszone wywołanie `rn_godot_change_scene`.
- Jeśli podajesz `.pck` – skonfiguruj loader Godota do korzystania z pakietu (standardowy bootstrap).

### 9. Częste pułapki
| Problem | Przyczyna | Jak naprawić |
|---------|-----------|--------------|
| `RealGodotEngine aktywny – brak widoku` | `rn_godot_get_view` zwraca nil zanim inicjalizacja skończona | Zainicjalizuj widok natychmiast / opóźnij `initialize` w JS |
| Brak animacji / brak ruchu | Nie wywołujesz `rn_godot_frame` | Zaimplementuj pętlę albo uruchom natywny wątek loopa |
| Crash przy cast | Zwrócony pointer nie jest obiektem ObjC | Zwróć prawdziwy UIView/NSView (retain w globalu) |
| Scena się nie zmienia | `rn_godot_change_scene` nie zaimplementowane / zła ścieżka | Upewnij się, że path zaczyna się od `res://` |

### 10. Checklista szybkiej walidacji
- [ ] Xcode widzi `godot_embed.mm` w Compile Sources.
- [ ] Implementacje `rn_godot_*` bez `static` (musi być export C).
- [ ] `rn_godot_get_view` zwraca nie-nil po `initialize`.
- [ ] `CADisplayLink` log “Frame loop aktywna.” pojawia się (jeśli masz `rn_godot_frame`).
- [ ] Zmiana `mainScene` w JS wywołuje Twoje logi w `rn_godot_change_scene`.

### Minimalny szkielet końcowy (skrót)
```objectivec
extern "C" {
void rn_godot_initialize(const char *p) { /* bootstrap + tworzenie g_render_view */ }
void rn_godot_change_scene(const char *scene) { /* SceneTree load */ }
void rn_godot_send_event(const char *evt) { /* dispatch */ }
void *rn_godot_get_view(void) { return (__bridge void*)g_render_view; }
void rn_godot_frame(void) { /* iterate + render */ }
}
```

Po wykonaniu powyższych kroków placeholder kolorów znika, a dostajesz właściwy rendering Godota w komponencie `<GodotView/>`.

## Props

| Prop | Opis |
|------|------|
| projectPath | Katalog projektu lub `.pck` |
| mainScene | Scena `res://...` |
| autoStart | Domyślnie true |
| suppressStubLogs | Niewykorzystywane (stub rzadko używany teraz) |
| symbolPrefix / symbolPrefixes | Zachowane dla kompatybilności (link-time strong ignoruje) |

## Ref API

```ts
ref.current?.ensureEngine();
ref.current?.setScene("res://scenes/TestScene.tscn");
```

## Diagnostyka

RealGodotEngine ładuje się zawsze – jeśli widok nie pojawia się, popraw implementację `rn_godot_get_view` w `godot_embed.mm`.

MIT

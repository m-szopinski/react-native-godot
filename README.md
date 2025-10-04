# @m-szopinski/react-native-godot (web export wrapper)

Minimal React / React Native wrapper for a Godot (4.x) Web export.  
No native Godot runtime (no `RealGodotEngine`, no `rn_godot_*`, no `.mm` files).  
Rendering always goes through:
- Web (react-native-web): `<iframe src="web-export/index.html" />`
- iOS / Android: `WebView` (from `react-native-webview`) loading the packaged `index.html`.

## Installation

```bash
npm install @m-szopinski/react-native-godot react-native-webview
# or
yarn add @m-szopinski/react-native-godot react-native-webview
```

(Using Expo and missing WebView? Run: `npx expo install react-native-webview`)

## Basic usage

```tsx
import { GodotView } from '@m-szopinski/react-native-godot';

export function GameScreen() {
  return <GodotView style={{ flex: 1 }} onReady={() => console.log('Godot ready')} />;
}
```

That’s it – the component always points to `web-export/index.html` inside the package.

## Package layout

```
node_modules/@m-szopinski/react-native-godot/
 ├─ lib/         # compiled JS/TS output
 ├─ src/         # sources
 ├─ web-export/  # Godot build (index.html + .js/.wasm/.pck)
 └─ README.md
```

## iOS (Xcode) – adding resources

The WebView must see `web-export/index.html` inside the app bundle.

Option A – manual folder reference:
1. In Xcode: Add Files to "<Your Target>" → select `node_modules/@m-szopinski/react-native-godot/web-export` (check "Copy if needed", choose "Create folder references").
2. Confirm it appears under Build Phases → Copy Bundle Resources.
3. Run the app – `GodotView` should load.

Option B – Run Script Phase:
Add a Run Script Phase before “Compile Sources”:

```bash
set -e
SRC="node_modules/@m-szopinski/react-native-godot/web-export"
DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/web-export"
rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC"/. "$DST"/
echo "Copied Godot web-export -> $DST"
```

## Android – adding assets

The WebView loads: `file:///android_asset/web-export/index.html`

Copy the folder into: `android/app/src/main/assets/web-export`

Gradle copy task (in `app/build.gradle`):

```gradle
tasks.register("copyGodotWebExport", Copy) {
    from("$rootDir/../node_modules/@m-szopinski/react-native-godot/web-export")
    into("$projectDir/src/main/assets/web-export")
}
preBuild.dependsOn("copyGodotWebExport")
```

Ensure `android/app/src/main/assets` exists.

## Component API

| Prop    | Type        | Description                                 |
|---------|-------------|---------------------------------------------|
| style   | any         | Style passed to container / WebView         |
| onReady | () => void  | Called after document load                  |
| source  | any         | Legacy (ignored)                            |

No ref methods – intentionally minimal.

## Migrating from the (deprecated) native version

Remove:
- `RealGodotEngine`, `godot_embed.mm`, any `rn_godot_*` references.
- Extra Pod / podspec native bridging code.

Replace old usage:
```jsx
<GodotView projectPath="..." mainScene="..."/>
```
with:
```jsx
<GodotView />
```

Frame loop, symbol dlsym logic and native scene switching are no longer present. All gameplay logic must exist inside the exported Web project.

## Updating the Godot build

CI exports `web-export` from the `godot-project/` directory.  
To deliver an updated build:
1. Update assets / scenes inside `godot-project/`.
2. Bump `version` in `package.json`.
3. Push to `main` (ensure you have permission for GitHub Packages publishing).

## Using your own project

Fork this repo and:
1. Replace contents of `godot-project/`.
2. Commit.
3. CI regenerates `web-export`.

(If you prefer shipping only your prebuilt export: remove `godot-project` and commit a ready `web-export`.)

## Debug / Troubleshooting

| Issue                                 | Cause / Fix |
|--------------------------------------|-------------|
| Black screen (iOS/Android)           | Missing `web-export` in bundle / assets. Re-run copy step (iOS) or Gradle copy (Android). |
| WebView error page / 404             | Folder not correctly copied. Verify path case-sensitivity. |
| `Invariant Violation: WebView`       | `react-native-webview` not installed or native build not rebuilt. |
| High memory usage                    | WASM + PCK size – consider hosting separately or compressing (gzip / brotli) for production web hosting. |
| Need RN <-> Godot messaging          | Inject JS into Godot export (postMessage to parent) and extend this component to listen (current version keeps scope minimal). |

### White screen deep diagnostics

Enable:
```tsx
<GodotView debug style={{ flex: 1 }} />
```

Overlay indicators:
- CANVAS: appears when a <canvas> element was created / detected.
- GL: OK / FAIL / ? (no attempt yet). FAIL → WebGL context not created (possibly threads crash, unsupported context attributes or missing canvas).
- M: Y/N – whether `window.Module` (Emscripten) was observed.
- Fetch errors / XHR errors: non-200 or network failures for .wasm/.pck/.js assets.

Extended indicators (added):
- IDX: HTTP status (or ERR) of an immediate fetch to index.html (helps detect missing / not copied file).
- Scripts: last loaded script names (verifies main JS actually attached).
- Body length: approximate length of raw document (if large but no canvas → script malfunction / thread stall).

Additional IDX states (index status):
| IDX value        | Meaning | Action |
|------------------|---------|--------|
| SKIP(file://)     | Running from local file:// (iOS/Android bundle) – fetch intentionally skipped to avoid false errors. | Normal for bundled assets. |
| FALLBACK(body)    | Fetch failed but document already has HTML content (body length > 50) – probably benign (file:// restriction). | Usually safe; continue checking canvas/GL. |
| ERR               | Fetch truly failed and no fallback DOM heuristic triggered. | Check that `web-export/index.html` exists in bundle/assets. |
| HTTP 200 / 404    | Normal HTTP status when not file://. 404 → missing file. | Copy or ensure correct path. |

Additional scenarios:
| Indicator combo | Meaning | Action |
|-----------------|---------|--------|
| IDX:HTTP 200, Scripts empty | index.html loaded but script tag not created / blocked | Inspect index.html modifications; ensure main .js included. |
| IDX:HTTP 404 | index.html not present in bundle | Re-copy `web-export` into iOS bundle / Android assets. |
| Scripts list present, NO-CANVAS, GL:? | JS ran but engine didn't create canvas | Check if export uses OffscreenCanvas (unsupported) or threads causing stall. |
| Body len large, NO-CANVAS, Scripts present | Boot code executed partial / runtime error before canvas | Look at console errors & wasm/script errors. |
| WASM error + IDX 200 | .wasm file missing/corrupt though index exists | Ensure .wasm copied (size > 0) and path unchanged. |

If using Godot Web export with threads enabled: iOS WKWebView local file context lacks COOP/COEP headers so SharedArrayBuffer is unavailable; engine stalls after bootstrap.

### Extended white screen diagnostics (new)

Additional overlay indicators & logs:
- Script errors: failing <script> tags (missing/misnamed .js file).
- WASM errors: WebAssembly.instantiate failures (corrupt / missing .wasm).
- Auto reload (cache-bust): triggers once if neither Module nor canvas appear in ~3.2s (helps stale cache).
- GL context fail: now correctly detects 'experimental-webgl'.
- Pending scripts stall: warns if script tags still not completed after 2s.

Recommended fixes per issue:
| Indicator / Log | Meaning | Action |
|-----------------|---------|--------|
| Script load error | JS file missing / path mismatch | Verify export folder copied intact; preserve filenames (hashes). |
| WASM error: ... | WebAssembly failed to parse / fetch | Check .wasm present, not zero bytes, correct MIME not required for file:// but file must exist. |
| Auto reload (cache-bust) | First attempt had no Module & no canvas | Possibly stale cached index / partial copy; after reload still white -> inspect script / wasm errors. |
| GL context fail | WebGL context not created | Re-export with WebGL2 disabled or reduce features (MSAA off). |
| SAB unavailable + threads export | Threads blocked in WKWebView | Re-export with threads disabled. |

### Automatic missing assets heuristic & fallback (native)

When `debug` is enabled the component now:
- Detects `about:blank` loads.
- Heuristically flags missing `web-export` copy (no Module, no canvas, no scripts).
- Provides a diagnostic hint block (steps to fix).
- (Diagnostic only) Can render a fallback inline `index.html` (HTML only) if assets were not bundled, so you see an explicit warning instead of a pure white screen.

Conditions triggering the fallback:
- No canvas + no Module after onLoadEnd.
- Index fetch status is `SKIP(file://)` / `ERR` / null.
- No scripts loaded.
- `debug` = true.

What it means: You likely did not copy `web-export/` into:
- iOS: Xcode Target → Copy Bundle Resources.
- Android: `android/app/src/main/assets/web-export`.

Fix then rebuild.

## Why no native embedding?

Goals:
- Simplify maintenance / installation.
- Avoid C++/Objective-C++ toolchain friction.
- Uniform behavior across platforms via WebView.

If you need full native performance or custom native modules, you’ll need a separate solution embedding a compiled Godot library.

## FAQ

- Do I need `pod install`? Only if adding `react-native-webview` wasn’t done before.
- Any Swift/ObjC classes required? No.
- Can I host assets remotely? Yes – fork / modify the component to use `source={{ uri: 'https://...' }}`.
- Inline base64 mode? Not by default (keeps bundle smaller and debuggable) – possible via custom fork.

## Example helper scripts

Consumer `package.json`:

```json
{
  "scripts": {
    "postinstall": "cp -R node_modules/@m-szopinski/react-native-godot/web-export ios/YourApp/web-export || true"
  }
}
```

(Or rely on Xcode / Gradle tasks above.)

## License

MIT

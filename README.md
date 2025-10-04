# @m-szopinski/react-native-godot (web export wrapper)

Minimal React / React Native wrapper for a Godot (4.x) Web export.  
No native Godot runtime, no inline base64 embedding, no diagnostics overlay.

Rendering:
- Web: `<iframe src="web-export/index.html" />`
- iOS / Android: `<WebView>` loading `index.html` from bundled assets.

## Installation

```bash
npm install @m-szopinski/react-native-godot react-native-webview
# or
yarn add @m-szopinski/react-native-godot react-native-webview
```

iOS (CocoaPods):
```bash
npx pod-install
```

## Basic usage

```tsx
import { GodotView } from '@m-szopinski/react-native-godot';

export function GameScreen() {
  return <GodotView style={{ flex: 1 }} onReady={() => console.log('Godot ready')} />;
}
```

## Package layout

```
node_modules/@m-szopinski/react-native-godot/
 ├─ lib/
 ├─ src/
 ├─ web-export/   # Godot build: index.html + *.js + *.wasm + *.pck
 └─ README.md
```

## iOS (Xcode) – include web-export

Choose ONE method:

### 1. Folder Reference (recommended)

1. Xcode → right‑click project root → “Add Files…”
2. Select: `node_modules/@m-szopinski/react-native-godot/web-export`
3. Options: “Create folder references” (blue), target: your app.
4. Verify in Build Phases → Copy Bundle Resources that files appear.

### 2. Run Script phase

Add Run Script (before Compile Sources):

```bash
set -e
SRC="${SRCROOT}/../node_modules/@m-szopinski/react-native-godot/web-export"
DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/web-export"
rm -rf "$DST"
mkdir -p "$DST"
rsync -a "$SRC"/ "$DST"/
test -f "$DST/index.html" || { echo "Missing index.html"; exit 1; }
```

Clean build if files were renamed (hashed JS).

## Android – add to assets

Copy folder to: `android/app/src/main/assets/web-export`

Gradle helper (`app/build.gradle`):

```gradle
tasks.register("copyGodotWebExport", Copy) {
    from("$rootDir/../node_modules/@m-szopinski/react-native-godot/web-export")
    into("$projectDir/src/main/assets/web-export")
}
preBuild.dependsOn("copyGodotWebExport")
```

Ensure directory `android/app/src/main/assets` exists.

## Component API

| Prop    | Type        | Description                      |
|---------|-------------|----------------------------------|
| style   | any         | Container / WebView style        |
| onReady | () => void  | Called when document finishes    |

No other props. Always loads `web-export/index.html`.

## Migrating from older (debug/inline) version

Remove usages of:
- `debug`
- `forceFileMode`
- All inline/diagnostic expectations

Simply render `<GodotView />` after bundling assets.

## Updating the Godot build

1. Edit content in `godot-project/`
2. Commit & push (CI exports to `web-export/`)
3. Bump version in `package.json`
4. Publish (workflow handles export + publish)

## Using the export without HTTPS (local WebView / file://)

If you see requirements related to COOP/COEP / SharedArrayBuffer or blank screen in iOS WKWebView:
1. Disable thread support in the Web export preset:
   - `variant/thread_support=false`
   - Set `threads/emscripten_pool_size=0`
   - Set `threads/godot_pool_size=0`
2. Disable cross‑origin isolation headers:
   - `progressive_web_app/ensure_cross_origin_isolation_headers=false`
3. Keep PWA disabled (`progressive_web_app/enabled=false`).
4. Re‑export.

Minimal diff in `export_presets.cfg`:
```
progressive_web_app/ensure_cross_origin_isolation_headers=false
threads/emscripten_pool_size=0
threads/godot_pool_size=0
variant/thread_support=false
```

After changing the preset re-run the CI export (or export locally) and copy the new `web-export` folder.

## Troubleshooting

| Symptom                  | Cause                          | Fix |
|--------------------------|--------------------------------|-----|
| White/blank screen       | Assets not copied             | Re-add Folder Reference or run copy script |
| 404 in WebView console   | Missing `index.html` or main JS| Re-export & re-copy `web-export` |
| WebView module undefined | `react-native-webview` missing | Install & pod-install |
| No canvas on iOS         | Threads/WebGL2 issues          | Re-export with threads disabled (WKWebView) |
| WASM not found           | Missing `.wasm` in bundle      | Ensure file present & copied |

## Why minimal?

Focus: predictable, maintenance-free integration.  
Use your own messaging layer by forking if needed.

## License

MIT

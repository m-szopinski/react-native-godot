#!/usr/bin/env bash
# build-godot.sh – pobieranie, rozpakowanie export templates i budowa minimalnego Godot.xcframework (tylko macOS)

set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/GodotBuild"
TEMPL_DIR="${BUILD_DIR}/templates"
ENGINE_DIR="${BUILD_DIR}/engine"
OUT_XC="${BUILD_DIR}/Godot.xcframework"
ENGINE_STAMP="${BUILD_DIR}/.godot.engine.version"
TEMPL_STAMP="${BUILD_DIR}/.godot.templates.version"

FORCE_REDOWNLOAD="${FORCE_REDOWNLOAD:-0}"

log(){ echo "[RNGodot] $*"; }
warn(){ echo "[RNGodot][WARN] $*" >&2; }

have_engine() {
  [[ -d "${OUT_XC}" && -f "${ENGINE_STAMP}" && "$(cat "${ENGINE_STAMP}")" == "${GODOT_VERSION}" ]]
}

have_templates() {
  [[ -f "${TEMPL_STAMP}" && "$(cat "${TEMPL_STAMP}")" == "${GODOT_VERSION}" ]]
}

fetch_templates() {
  mkdir -p "${TEMPL_DIR}"
  if ! have_templates || [[ "${FORCE_REDOWNLOAD}" == "1" ]]; then
    log "Pobieranie export templates (wersja ${GODOT_VERSION})"
    rm -rf "${TEMPL_DIR:?}/"* || true
    local TPZ="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
    local URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${TPZ}"
    curl -L --fail "${URL}" -o "${TEMPL_DIR}/${TPZ}"
    unzip -q "${TEMPL_DIR}/${TPZ}" -d "${TEMPL_DIR}/unpacked"
    echo "${GODOT_VERSION}" > "${TEMPL_STAMP}"
    log "Templates OK."
  else
    log "Templates już są (cache)."
  fi
}

build_engine() {
  [[ "$(uname -s)" == "Darwin" ]] || { warn "Nie macOS – pomijam budowę silnika (to oczekiwane na CI Linux)."; return 0; }
  command -v scons >/dev/null || { warn "Brak scons (brew install scons) – pomijam."; return 0; }
  command -v xcodebuild >/dev/null || { warn "Brak xcodebuild – zainstaluj Xcode."; return 0; }

  if have_engine && [[ "${FORCE_REDOWNLOAD}" != "1" ]]; then
    log "Godot.xcframework (${GODOT_VERSION}) już istnieje – pomijam budowę."
    return 0
  fi

  mkdir -p "${ENGINE_DIR}"
  if [[ ! -d "${ENGINE_DIR}/godot" ]]; then
    log "Klonowanie źródeł Godot ${GODOT_VERSION}"
    git clone --depth=1 --branch "${GODOT_VERSION}-stable" https://github.com/godotengine/godot.git "${ENGINE_DIR}/godot"
  fi

  pushd "${ENGINE_DIR}/godot" >/dev/null
  local CPU
  CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

  log "Budowa macOS arm64"
  scons platform=macos arch=arm64 target=template_release --jobs="${CPU}"
  log "Budowa macOS x86_64"
  scons platform=macos arch=x86_64 target=template_release --jobs="${CPU}"
  log "Budowa iOS arm64"
  scons platform=ios arch=arm64 target=template_release --jobs="${CPU}"
  log "Budowa iOS simulator x86_64"
  scons platform=ios arch=x86_64 target=template_release --jobs="${CPU}"
  popd >/dev/null

  rm -rf "${OUT_XC}"
  local TMP_INC="${BUILD_DIR}/tmp/include"
  mkdir -p "${TMP_INC}"

  cat > "${TMP_INC}/Godot.h" <<'EOF'
#pragma once
// Placeholder public API header for the Godot engine xcframework.
// Add bridging declarations here if you expose engine functions to Swift.
#ifdef __cplusplus
extern "C" {
#endif
// (brak oficjalnych symboli – silnik linkowany statycznie)
#ifdef __cplusplus
}
#endif
EOF

  cat > "${TMP_INC}/module.modulemap" <<'EOF'
module Godot {
  header "Godot.h"
  export *
}
EOF

  log "Tworzenie xcframework"
  xcodebuild -create-xcframework \
    -library "${ENGINE_DIR}/godot/bin/libgodot.macos.template_release.arm64.a" -headers "${TMP_INC}" \
    -library "${ENGINE_DIR}/godot/bin/libgodot.macos.template_release.x86_64.a" -headers "${TMP_INC}" \
    -library "${ENGINE_DIR}/godot/bin/libgodot.ios.template_release.arm64.a" -headers "${TMP_INC}" \
    -library "${ENGINE_DIR}/godot/bin/libgodot.ios.template_release.x86_64.a" -headers "${TMP_INC}" \
    -output "${OUT_XC}"

  if [[ -d "${OUT_XC}" ]]; then
    echo "${GODOT_VERSION}" > "${ENGINE_STAMP}"
    log "Godot.xcframework gotowe."
  else
    warn "Nie udało się utworzyć Godot.xcframework."
  fi
}

main() {
  log "Start build-godot (Godot ${GODOT_VERSION})"
  fetch_templates
  build_engine
  if have_engine; then
    log "Silnik dostępny: ${OUT_XC}"
  else
    warn "Silnik NIE zbudowany – canImport(Godot) w Swift będzie false."
  fi
  log "Koniec build-godot."
}

main "$@"

set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${ROOT}/GodotRuntime"

log(){ echo "[build-godot] $*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Requires macOS."
  exit 0
fi

if ! command -v scons >/dev/null; then
  log "Install scons (brew install scons)."
  exit 1
fi

rm -rf "${RUNTIME_DIR}"
mkdir -p "${RUNTIME_DIR}"

if [[ ! -d "${ROOT}/godot-src" ]]; then
  log "Cloning Godot ${GODOT_VERSION}-stable"
  git clone --depth 1 --branch "${GODOT_VERSION}-stable" https://github.com/godotengine/godot.git "${ROOT}/godot-src"
fi

cd "${ROOT}/godot-src"
CPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)

log "Build macOS arm64"
scons platform=macos arch=arm64 target=template_release tools=no use_lto=yes -j "$CPU"
log "Build macOS x86_64"
scons platform=macos arch=x86_64 target=template_release tools=no use_lto=yes -j "$CPU"
log "Build iOS arm64"
scons platform=ios arch=arm64 target=template_release tools=no ios_simulator=no use_lto=yes -j "$CPU"
log "Build iOS simulator arm64"
scons platform=ios_simulator arch=arm64 target=template_release tools=no use_lto=yes -j "$CPU"

cd "${ROOT}"
mkdir -p "${RUNTIME_DIR}/macos" "${RUNTIME_DIR}/ios/device" "${RUNTIME_DIR}/ios/simulator"

cp godot-src/bin/libgodot.macos.template_release.arm64.a "${RUNTIME_DIR}/macos/"
cp godot-src/bin/libgodot.macos.template_release.x86_64.a "${RUNTIME_DIR}/macos/"
lipo -create \
  godot-src/bin/libgodot.macos.template_release.arm64.a \
  godot-src/bin/libgodot.macos.template_release.x86_64.a \
  -output "${RUNTIME_DIR}/macos/libgodot_universal.a"

cp godot-src/bin/libgodot.ios.template_release.arm64.a "${RUNTIME_DIR}/ios/device/"
cp godot-src/bin/libgodot.ios_simulator.template_release.arm64.a "${RUNTIME_DIR}/ios/simulator/"

cat > "${RUNTIME_DIR}/rn_godot_wrapper.c" <<'EOC'
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void rn_godot_initialize(const char *project_path_or_null) { (void)project_path_or_null; }
void rn_godot_change_scene(const char *scene_path) { (void)scene_path; }
void rn_godot_send_event(const char *event_name) { (void)event_name; }
void *rn_godot_get_view(void) { return NULL; }
void rn_godot_frame(void) { }
#ifdef __cplusplus
}
#endif
EOC

# DODANE: mostek symboli bootstrap (stub – do zastąpienia własną implementacją)
cat > "${RUNTIME_DIR}/rn_godot_runtime_bridge.c" <<'EOC'
#include <stdio.h>
#include <stdarg.h>
static const char *g_project = NULL;
static void *g_metal_layer = NULL;
static int g_frame_count = 0;
static void blog(const char *tag, const char *fmt, ...) {
  va_list ap; va_start(ap, fmt);
  fprintf(stderr, "[godot_runtime_bridge]%s ", tag);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
}
#ifdef __cplusplus
extern "C" {
#endif
int godot_rn_is_stub(void) {
  return 1;
}
void godot_rn_bootstrap(const char *project_or_pck) {
  g_project = project_or_pck;
  blog("[bootstrap]", "STUB start (project=%s) – czarne tło jest normalne dopóki nie wdrożysz realnej inicjalizacji.", project_or_pck ? project_or_pck : "nil");
  /* TODO: real Godot init */
}
void godot_rn_set_metal_layer(void *layer) {
  g_metal_layer = layer;
  blog("[layer]", "CAMetalLayer=%p (stub – brak renderu scen).", layer);
}
void godot_rn_frame(void) {
  if (++g_frame_count == 5) {
    blog("[frame]", "STUB nadal aktywny (5 klatek) – dodaj własny bootstrap żeby zobaczyć scenę.");
  }
}
void godot_rn_change_scene(const char *res_path) {
  blog("[scene]", "change -> %s (stub, ignorowane)", res_path ? res_path : "(null)");
}
void godot_rn_send_event(const char *evt) {
  blog("[event]", "recv -> %s (stub, ignorowane)", evt ? evt : "(null)");
}
#ifdef __cplusplus
}
#endif
EOC

# HOOK REAL BOOTSTRAP (lokalnie):
# Jeśli ustawisz REAL_BOOTSTRAP_SRC=/abs/path/do/real_bootstrap.mm
# skrypt skopiuje ten plik jako rn_godot_runtime_bridge.c/mm zamiast generować stub.
if [[ -n "${REAL_BOOTSTRAP_SRC:-}" && -f "${REAL_BOOTSTRAP_SRC}" ]]; then
  log "Używam REAL_BOOTSTRAP_SRC=${REAL_BOOTSTRAP_SRC} (nadpisuje stub)."
  ext="${REAL_BOOTSTRAP_SRC##*.}"
  cp "${REAL_BOOTSTRAP_SRC}" "${RUNTIME_DIR}/rn_godot_runtime_bridge.${ext}"
  # Pomijamy generowanie stubu (return early jeśli to finalny fragment).
fi

log "Done. Artifacts in ${RUNTIME_DIR}"
find "${RUNTIME_DIR}" -type f -maxdepth 3 -print

# Lokalna budowa (macOS) – wymagany zainstalowany Vulkan / MoltenVK (VULKAN_SDK).
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${ROOT}/godot"
OUT_DIR="${ROOT}/GodotRuntimeLocal"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

log(){ echo "[local-build] $*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  log "Only macOS supported."
  exit 1
fi

command -v scons >/dev/null || { log "Install scons (brew install scons)"; exit 1; }
[[ -n "${VULKAN_SDK:-}" ]] || { log "Set VULKAN_SDK (export VULKAN_SDK=/path/to/vulkansdk)"; exit 1; }
test -d "$VULKAN_SDK/include/vulkan" || { log "VULKAN_SDK missing include/vulkan"; exit 1; }

if [[ ! -d "$SRC_DIR" ]]; then
  log "Cloning Godot ${GODOT_VERSION}-stable"
  git clone --depth 1 --branch "${GODOT_VERSION}-stable" https://github.com/godotengine/godot.git "$SRC_DIR"
fi

pushd "$SRC_DIR" >/dev/null
log "Build macOS arm64"
scons platform=macos arch=arm64 target=template_release tools=no use_lto=yes vulkan_sdk_path=$VULKAN_SDK -j "$JOBS"
log "Build macOS x86_64"
scons platform=macos arch=x86_64 target=template_release tools=no use_lto=yes vulkan_sdk_path=$VULKAN_SDK -j "$JOBS"
log "Build iOS device arm64"
scons platform=ios arch=arm64 target=template_release tools=no ios_simulator=no use_lto=yes vulkan_sdk_path=$VULKAN_SDK -j "$JOBS"
log "Build iOS simulator arm64"
scons platform=ios_simulator arch=arm64 target=template_release tools=no use_lto=yes vulkan_sdk_path=$VULKAN_SDK -j "$JOBS"
popd >/dev/null

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/macos" "$OUT_DIR/ios/device" "$OUT_DIR/ios/simulator"
cp "$SRC_DIR/bin/libgodot.macos.template_release.arm64.a" "$OUT_DIR/macos/"
cp "$SRC_DIR/bin/libgodot.macos.template_release.x86_64.a" "$OUT_DIR/macos/"
lipo -create \
  "$SRC_DIR/bin/libgodot.macos.template_release.arm64.a" \
  "$SRC_DIR/bin/libgodot.macos.template_release.x86_64.a" \
  -output "$OUT_DIR/macos/libgodot_universal.a"
cp "$SRC_DIR/bin/libgodot.ios.template_release.arm64.a" "$OUT_DIR/ios/device/"
cp "$SRC_DIR/bin/libgodot.ios_simulator.template_release.arm64.a" "$OUT_DIR/ios/simulator/"

log "Done. Output in $OUT_DIR"

#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTPM_BUILD_PATH="$ROOT/.swiftpm-build-check"
SWIFTPM_CONFIGURATION="release"
SWIFTPM_PRODUCT_PATH="$SWIFTPM_BUILD_PATH/arm64-apple-macosx/$SWIFTPM_CONFIGURATION"
SWIFTPM_BINARY="$SWIFTPM_PRODUCT_PATH/Papyrus"
SWIFTPM_CLI_BINARY="$SWIFTPM_PRODUCT_PATH/PapyrusCLI"
SWIFTPM_ANALYZER="$SWIFTPM_PRODUCT_PATH/Papyrus_Papyrus.bundle/papyrus_analyzer"
MAIN_APP="$ROOT/Papyrus.app"
APP_INFO_SOURCE="$ROOT/AppResources/Info.plist"
APP_INFO_PLIST="$MAIN_APP/Contents/Info.plist"
APP_BINARY="$MAIN_APP/Contents/MacOS/Papyrus"
APP_CLI_BINARY="$MAIN_APP/Contents/Resources/papyrus"
LEGACY_APP_BINARY="$MAIN_APP/Contents/MacOS/PaperNest"
APP_ANALYZER="$MAIN_APP/Contents/Resources/papyrus_analyzer"
LEGACY_APP_ICON="$MAIN_APP/Contents/Resources/PaperNest.icns"
APP_ICON="$MAIN_APP/Contents/Resources/Papyrus.icns"
EMBEDDED_SAFARI_APPEX="$MAIN_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
LEGACY_EMBEDDED_SAFARI_APPEX_BY_NAME="$MAIN_APP/Contents/PlugIns/PaperNest Web Clipper Extension.appex"
LEGACY_EMBEDDED_SAFARI_APP="$MAIN_APP/Contents/Applications/Papyrus Web Clipper.app"
LEGACY_EMBEDDED_SAFARI_APPEX="$LEGACY_EMBEDDED_SAFARI_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
SAFARI_DEV_APP="$ROOT/.safari-build/Build/Products/Debug/Papyrus Web Clipper.app"
SAFARI_DEV_APPEX="$ROOT/.safari-build/Build/Products/Debug/Papyrus Web Clipper Extension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
ANALYZER_SOURCE="$ROOT/tools/pdf_analyzer/papyrus_analyzer.py"

ensure_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Required path not found: $path" >&2
    exit 1
  fi
}

resolve_codesign_identity() {
  local identity
  identity=$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
      | /usr/bin/head -n 1
  )

  if [[ -n "$identity" ]]; then
    echo "$identity"
  else
    echo "-"
  fi
}

sync_app_bundle_metadata() {
  ensure_file "$APP_INFO_SOURCE"
  /bin/cp "$APP_INFO_SOURCE" "$APP_INFO_PLIST"

  # Keep the renamed bundle launchable even before icon assets are regenerated.
  if [[ ! -f "$APP_ICON" && -f "$LEGACY_APP_ICON" ]]; then
    /bin/cp "$LEGACY_APP_ICON" "$APP_ICON"
  fi
}

remove_stale_bundle_artifacts() {
  rm -f "$LEGACY_APP_BINARY"
  rm -rf "$LEGACY_EMBEDDED_SAFARI_APPEX_BY_NAME"
}

needs_analyzer_rebuild() {
  [[ ! -f "$ANALYZER_SOURCE" ]] && return 1
  [[ ! -f "$APP_ANALYZER" ]] && return 0
  [[ "$ANALYZER_SOURCE" -nt "$APP_ANALYZER" ]]
}

needs_safari_embed() {
  [[ ! -d "$EMBEDDED_SAFARI_APPEX" ]] && return 0

  local newer_file
  newer_file=$(
    find \
      "$ROOT/browser-extension" \
      "$ROOT/safari-extension" \
      -type f \
      -newer "$EMBEDDED_SAFARI_APPEX" \
      -print \
      -quit 2>/dev/null || true
  )

  [[ -n "$newer_file" ]]
}

refresh_safari_registration() {
  [[ -d "$EMBEDDED_SAFARI_APPEX" ]] || return 0
  [[ -x "$LSREGISTER" ]] || return 0

  "$LSREGISTER" -f -R -trusted "$MAIN_APP" >/dev/null
  /usr/bin/pluginkit -a "$EMBEDDED_SAFARI_APPEX" >/dev/null || true
  /usr/bin/pluginkit -r "$SAFARI_DEV_APPEX" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$SAFARI_DEV_APP" >/dev/null 2>&1 || true
  /usr/bin/pluginkit -r "$LEGACY_EMBEDDED_SAFARI_APPEX" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$LEGACY_EMBEDDED_SAFARI_APP" >/dev/null 2>&1 || true
  /usr/bin/pluginkit -a "$EMBEDDED_SAFARI_APPEX" >/dev/null || true
}

refresh_app_registration() {
  [[ -x "$LSREGISTER" ]] || return 0
  "$LSREGISTER" -f -R -trusted "$MAIN_APP" >/dev/null
}

echo "Building Papyrus..."

ensure_file "$MAIN_APP"
SIGNING_IDENTITY="$(resolve_codesign_identity)"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Using ad-hoc signing for Papyrus.app"
else
  echo "Using signing identity: $SIGNING_IDENTITY"
fi

if needs_analyzer_rebuild; then
  echo "Rebuilding PDF analyzer..."
  (
    cd "$ROOT/tools/pdf_analyzer"
    pyinstaller --onefile papyrus_analyzer.py --distpath ../../Papyrus/Resources
  )
fi

CLANG_MODULE_CACHE_PATH=/tmp/papyrus-clang-module-cache \
  swift build -c "$SWIFTPM_CONFIGURATION" --package-path "$ROOT" --build-path "$SWIFTPM_BUILD_PATH"

ensure_file "$SWIFTPM_BINARY"

echo "Syncing Chrome extension..."
"$ROOT/tools/build_chrome_extension.sh" >/dev/null

if needs_safari_embed; then
  echo "Embedding Safari extension..."
  "$ROOT/tools/embed_safari_extension.sh"
fi

sync_app_bundle_metadata
/usr/bin/install -m 755 "$SWIFTPM_BINARY" "$APP_BINARY"
remove_stale_bundle_artifacts

if [[ -f "$SWIFTPM_CLI_BINARY" ]]; then
  /usr/bin/install -m 755 "$SWIFTPM_CLI_BINARY" "$APP_CLI_BINARY"
fi

if [[ -f "$SWIFTPM_ANALYZER" ]]; then
  /usr/bin/install -m 755 "$SWIFTPM_ANALYZER" "$APP_ANALYZER"
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" "$MAIN_APP"
refresh_app_registration

if [[ -d "$EMBEDDED_SAFARI_APPEX" ]]; then
  "$ROOT/tools/repair_embedded_safari_extension_signature.sh" "$MAIN_APP" >/dev/null
  refresh_safari_registration
fi

pkill -x Papyrus >/dev/null 2>&1 || true
pkill -x PaperNest >/dev/null 2>&1 || true
for attempt in {1..5}; do
  if open "$MAIN_APP" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
sleep 2
osascript -e 'tell application "Papyrus" to activate' >/dev/null 2>&1 || true

echo "Papyrus rebuilt and launched:"
echo "  $MAIN_APP"

#!/bin/zsh
# Builds the Safari extension bundle and embeds it into Papyrus.app/Contents/PlugIns/.
# Run this after the main app has been built and synced.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJECT="$ROOT/safari-extension/Papyrus Web Clipper/Papyrus Web Clipper.xcodeproj"
DERIVED_DATA="$ROOT/.derived-data-safari-staging"
PRODUCTS="$DERIVED_DATA/Build/Products/Debug"
BUILT_APPEX="$PRODUCTS/Papyrus Web Clipper Extension.appex"
MAIN_APP="$ROOT/Papyrus.app"
EMBEDDED_DIR="$MAIN_APP/Contents/PlugIns"
EMBEDDED_APPEX="$EMBEDDED_DIR/Papyrus Web Clipper Extension.appex"
LEGACY_EMBEDDED_APP="$MAIN_APP/Contents/Applications/Papyrus Web Clipper.app"
LEGACY_EMBEDDED_APPEX="$LEGACY_EMBEDDED_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
DEVELOPMENT_TEAM="${PAPYRUS_DEVELOPMENT_TEAM:-$("$ROOT/tools/resolve_apple_development_team.sh")}"

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "Unable to resolve an Apple Development team ID for Safari extension signing." >&2
  echo "Set PAPYRUS_DEVELOPMENT_TEAM or install an Apple Development certificate first." >&2
  exit 1
fi

echo "Building Papyrus Web Clipper..."
PAPYRUS_ICON_SOURCE_PATH="$ROOT/assets/icons/Papyrus-macos26-source.png" \
  xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "Papyrus Web Clipper" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    PAPYRUS_DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build 2>&1 | tee /tmp/papyrus-webclipper-build.log | grep -E "error:|Build succeeded|Build FAILED" || true

if grep -q "BUILD FAILED" /tmp/papyrus-webclipper-build.log 2>/dev/null; then
  echo "Build failed. See /tmp/papyrus-webclipper-build.log for details." >&2
  exit 1
fi

if [[ ! -d "$BUILT_APPEX" ]]; then
  echo "Build failed: $BUILT_APPEX not found" >&2
  exit 1
fi

echo "Embedding into Papyrus.app..."
mkdir -p "$EMBEDDED_DIR"
if [[ -d "$LEGACY_EMBEDDED_APPEX" ]]; then
  /usr/bin/pluginkit -r "$LEGACY_EMBEDDED_APPEX" >/dev/null 2>&1 || true
fi

rm -rf "$EMBEDDED_APPEX"
ditto "$BUILT_APPEX" "$EMBEDDED_APPEX"

if [[ -d "$LEGACY_EMBEDDED_APP" ]]; then
  rm -rf "$LEGACY_EMBEDDED_APP"
fi

rm -rf "$DERIVED_DATA" 2>/dev/null || true

echo "Done. Papyrus Web Clipper embedded at:"
echo "  $EMBEDDED_APPEX"

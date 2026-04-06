#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/safari-extension/Papyrus Web Clipper/Papyrus Web Clipper.xcodeproj"
DERIVED_DATA="$ROOT/.safari-build"
HOST_APP="$DERIVED_DATA/Build/Products/Debug/Papyrus Web Clipper.app"
HOST_APPEX="$DERIVED_DATA/Build/Products/Debug/Papyrus Web Clipper Extension.appex"
MAIN_APP="$ROOT/Papyrus.app"
MAIN_APPEX="$ROOT/Papyrus.app/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
LEGACY_EMBEDDED_APP="$MAIN_APP/Contents/Applications/Papyrus Web Clipper.app"
LEGACY_EMBEDDED_APPEX="$LEGACY_EMBEDDED_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
DEVELOPMENT_TEAM="${PAPYRUS_DEVELOPMENT_TEAM:-$("$ROOT/tools/resolve_apple_development_team.sh")}"

if [[ ! -d "$PROJECT" ]]; then
  echo "Safari host project not found: $PROJECT" >&2
  exit 1
fi

if [[ ! -d "$MAIN_APPEX" ]]; then
  echo "Embedded Safari extension not found: $MAIN_APPEX" >&2
  echo "Run tools/build_and_launch_app.sh first." >&2
  exit 1
fi

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "Unable to resolve an Apple Development team ID for Safari extension signing." >&2
  echo "Set PAPYRUS_DEVELOPMENT_TEAM or install an Apple Development certificate first." >&2
  exit 1
fi

echo "Building Papyrus Web Clipper host app..."
PAPYRUS_ICON_SOURCE_PATH="$ROOT/assets/icons/Papyrus-macos26-source.png" \
  xcodebuild \
    -project "$PROJECT" \
    -scheme "Papyrus Web Clipper" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    PAPYRUS_DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    build >/tmp/papyrus-safari-visibility.log 2>&1

if [[ ! -d "$HOST_APP" || ! -d "$HOST_APPEX" ]]; then
  echo "Build failed. See /tmp/papyrus-safari-visibility.log for details." >&2
  exit 1
fi

/usr/bin/pluginkit -r "$HOST_APPEX" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$MAIN_APPEX" >/dev/null 2>&1 || true
/usr/bin/pluginkit -r "$LEGACY_EMBEDDED_APPEX" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$HOST_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$LEGACY_EMBEDDED_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R -trusted "$MAIN_APP" >/dev/null
/usr/bin/pluginkit -a "$MAIN_APPEX"

open -W "$HOST_APP"

/usr/bin/pluginkit -r "$HOST_APPEX" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$HOST_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R -trusted "$MAIN_APP" >/dev/null
/usr/bin/pluginkit -a "$MAIN_APPEX"

echo "Safari extension visibility refresh triggered:"
echo "  $HOST_APP"

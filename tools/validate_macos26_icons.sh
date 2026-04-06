#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BUILD_SCRIPT="$ROOT_DIR/tools/build_icons.sh"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/.icon-verification}"

BASE_SOURCE="${BASE_SOURCE:-$ROOT_DIR/assets/icons/Papyrus-macos26-source.png}"
VARIANT_SOURCE="$ARTIFACT_DIR/Papyrus-macos26-variant-source.png"

MAIN_APP="$ROOT_DIR/Papyrus.app"
MAIN_APP_INFO="$MAIN_APP/Contents/Info.plist"
MAIN_APP_ICNS="$MAIN_APP/Contents/Resources/Papyrus.icns"
MAIN_APP_ASSETS="$MAIN_APP/Contents/Resources/Assets.car"

SWIFTPM_BUILD_PATH="$ROOT_DIR/.swiftpm-build-check"
SWIFTPM_CONFIGURATION="release"
SWIFTPM_PRODUCT_PATH="$SWIFTPM_BUILD_PATH/arm64-apple-macosx/$SWIFTPM_CONFIGURATION"
SWIFTPM_BINARY="$SWIFTPM_PRODUCT_PATH/Papyrus"
SWIFTPM_ANALYZER="$SWIFTPM_PRODUCT_PATH/Papyrus_Papyrus.bundle/papyrus_analyzer"
APP_BINARY="$MAIN_APP/Contents/MacOS/Papyrus"
APP_ANALYZER="$MAIN_APP/Contents/Resources/papyrus_analyzer"
REPAIR_SAFARI_SIGNATURE_SCRIPT="$ROOT_DIR/tools/repair_embedded_safari_extension_signature.sh"

SAFARI_PROJECT="$ROOT_DIR/safari-extension/Papyrus Web Clipper/Papyrus Web Clipper.xcodeproj"
SAFARI_SCHEME="Papyrus Web Clipper"
SAFARI_DERIVED_DATA="${SAFARI_DERIVED_DATA:-$ROOT_DIR/.derived-data-icon-validation}"
SAFARI_BUILD_APP="$SAFARI_DERIVED_DATA/Build/Products/Debug/Papyrus Web Clipper.app"
SAFARI_BUILD_APPEX="$SAFARI_DERIVED_DATA/Build/Products/Debug/Papyrus Web Clipper Extension.appex"
SAFARI_HOST_INFO="$SAFARI_BUILD_APP/Contents/Info.plist"
SAFARI_HOST_ICNS="$SAFARI_BUILD_APP/Contents/Resources/Papyrus.icns"
SAFARI_HOST_ASSETS="$SAFARI_BUILD_APP/Contents/Resources/Assets.car"
SAFARI_APPEX="$MAIN_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
SAFARI_APPEX_RESOURCES="$SAFARI_APPEX/Contents/Resources"
SAFARI_APPEX_MANIFEST="$SAFARI_APPEX_RESOURCES/manifest.json"
SAFARI_APPEX_ICON_DIR="$SAFARI_APPEX_RESOURCES/icons"
LEGACY_SAFARI_APP="$MAIN_APP/Contents/Applications/Papyrus Web Clipper.app"
LEGACY_SAFARI_APPEX="$LEGACY_SAFARI_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

EXTENSION_ICON_DIR="$ROOT_DIR/browser-extension/icons"
EXTENSION_SOURCE="$ROOT_DIR/assets/icons/Papyrus-extension-source.png"

MAIN_PREVIEW="$ARTIFACT_DIR/main-app-icon-preview.png"
PLUGIN_PREVIEW="$ARTIFACT_DIR/plugin-app-icon-preview.png"
SAFARI_PREVIEW="$ARTIFACT_DIR/safari-transparent-icon-preview.png"
MAIN_FILE_ICON_PREVIEW="$ARTIFACT_DIR/main-app-file-icon-preview.png"

MAIN_ASSET_REPORT="$ARTIFACT_DIR/main-app-assets.json"
PLUGIN_ASSET_REPORT="$ARTIFACT_DIR/plugin-app-assets.json"
SAFARI_MANIFEST_REPORT="$ARTIFACT_DIR/safari-manifest.json"
REPORT_FILE="$ARTIFACT_DIR/report.txt"

ensure_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

ensure_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

pixel_dimensions() {
  local image_path="$1"
  local width height
  width=$(magick identify -format '%w' "$image_path")
  height=$(magick identify -format '%h' "$image_path")
  echo "$width $height"
}

generate_variant_source() {
  local width height
  read -r width height <<<"$(pixel_dimensions "$BASE_SOURCE")"

  if [[ "$width" != "$height" ]]; then
    echo "Variant source must be generated from a square PNG: $BASE_SOURCE" >&2
    exit 1
  fi

  local size="$width"
  local rect_left=$(( size * 62 / 100 ))
  local rect_top=$(( size * 13 / 100 ))
  local rect_right=$(( size * 88 / 100 ))
  local rect_bottom=$(( size * 39 / 100 ))
  local rect_radius=$(( size * 6 / 100 ))

  local circle_x=$(( size * 27 / 100 ))
  local circle_y=$(( size * 74 / 100 ))
  local circle_edge_x=$(( size * 39 / 100 ))

  local line1_x1=$(( size * 22 / 100 ))
  local line1_y1=$(( size * 28 / 100 ))
  local line1_x2=$(( size * 76 / 100 ))
  local line1_y2=$(( size * 72 / 100 ))

  local line2_x1=$(( size * 31 / 100 ))
  local line2_y1=$(( size * 24 / 100 ))
  local line2_x2=$(( size * 86 / 100 ))
  local line2_y2=$(( size * 69 / 100 ))

  local stroke_width=$(( size * 3 / 100 ))
  (( stroke_width < 24 )) && stroke_width=24

  mkdir -p "$ARTIFACT_DIR"

  magick "$BASE_SOURCE" \
    \( -size "${width}x${height}" xc:none \
      -fill '#F0B94DD8' \
      -draw "roundrectangle ${rect_left},${rect_top} ${rect_right},${rect_bottom} ${rect_radius},${rect_radius}" \) \
    -compose over -composite \
    \( -size "${width}x${height}" xc:none \
      -fill '#0D6C73F0' \
      -draw "circle ${circle_x},${circle_y} ${circle_edge_x},${circle_y}" \) \
    -compose over -composite \
    \( -size "${width}x${height}" xc:none \
      -stroke '#FFF4D2' \
      -strokewidth "$stroke_width" \
      -draw "line ${line1_x1},${line1_y1} ${line1_x2},${line1_y2}" \
      -draw "line ${line2_x1},${line2_y1} ${line2_x2},${line2_y2}" \) \
    -compose over -composite \
    "$VARIANT_SOURCE"
}

extract_preview_from_icns() {
  local icns_path="$1"
  local output_png="$2"
  local temp_dir input_icns iconset_dir candidate
  temp_dir=$(mktemp -d /tmp/papyrus-icon-preview.XXXXXX)
  input_icns="$temp_dir/icon.icns"
  iconset_dir="$temp_dir/icon.iconset"

  cp "$icns_path" "$input_icns"
  iconutil -c iconset "$input_icns" -o "$iconset_dir"

  for candidate in \
    "$iconset_dir/icon_512x512@2x.png" \
    "$iconset_dir/icon_512x512.png" \
    "$iconset_dir/icon_256x256@2x.png" \
    "$iconset_dir/icon_256x256.png" \
    "$iconset_dir/icon_128x128@2x.png"; do
    if [[ -f "$candidate" ]]; then
      cp "$candidate" "$output_png"
      rm -rf "$temp_dir"
      return 0
    fi
  done

  rm -rf "$temp_dir"
  echo "Unable to extract preview PNG from $icns_path" >&2
  exit 1
}

render_file_icon() {
  local bundle_path="$1"
  local output_png="$2"
  local temp_dir swift_file
  temp_dir=$(mktemp -d /tmp/papyrus-file-icon.XXXXXX)
  swift_file="$temp_dir/render.swift"

  cat > "$swift_file" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: render.swift <bundle-path> <output-png>\n", stderr)
  exit(1)
}

let bundlePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let size = NSSize(width: 512, height: 512)
let image = NSWorkspace.shared.icon(forFile: bundlePath)
image.size = size

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(size.width),
  pixelsHigh: Int(size.height),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fputs("Unable to allocate bitmap.\n", stderr)
  exit(1)
}

rep.size = size

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
  fputs("Unable to create graphics context.\n", stderr)
  exit(1)
}

NSGraphicsContext.current = context
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
image.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
  fputs("Unable to encode PNG output.\n", stderr)
  exit(1)
}

try data.write(to: URL(fileURLWithPath: outputPath))
SWIFT

  xcrun swift "$swift_file" "$bundle_path" "$output_png" >/dev/null
  rm -rf "$temp_dir"
}

assert_bundle_icon_name() {
  local plist_path="$1"
  local expected_name="$2"
  local actual_name actual_file

  actual_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$plist_path")
  actual_file=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist_path")

  if [[ "$actual_name" != "$expected_name" || "$actual_file" != "$expected_name" ]]; then
    echo "Unexpected icon keys in $plist_path: CFBundleIconName=$actual_name CFBundleIconFile=$actual_file" >&2
    exit 1
  fi
}

assert_asset_catalog_contains_icon() {
  local assets_path="$1"
  local expected_name="$2"
  local output_path="$3"

  xcrun assetutil --info "$assets_path" > "$output_path"
  if ! rg -q "\"Name\" : \"$expected_name\"" "$output_path"; then
    echo "Assets catalog does not contain icon name $expected_name: $assets_path" >&2
    exit 1
  fi
}

assert_manifest_points_to_icons() {
  local manifest_path="$1"
  local output_path="$2"

  plutil -convert json -o "$output_path" "$manifest_path"

  if ! rg -q 'icon-1024\.png' "$output_path" || ! rg -q 'icon-16\.png' "$output_path"; then
    echo "Manifest does not point at extension icon assets: $manifest_path" >&2
    exit 1
  fi
}

assert_transparent_corner() {
  local image_path="$1"
  local corner_sample
  corner_sample=$(magick "$image_path" -format '%[pixel:p{0,0}]' info:)

  if [[ "$corner_sample" != "srgba(0,0,0,0)" ]]; then
    echo "Expected transparent top-left corner in $image_path, got $corner_sample" >&2
    exit 1
  fi
}

assert_pluginkit_points_to_target() {
  local output
  output=$(/usr/bin/pluginkit -m -A -D -vv -i com.papyrus.app.web-clipper.Extension)

  if ! printf '%s\n' "$output" | grep -Fq "Path = $SAFARI_APPEX"; then
    echo "pluginkit did not switch to expected path: $SAFARI_APPEX" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

main_app_build_and_launch() {
  "$BUILD_SCRIPT" app "$VARIANT_SOURCE"

  CLANG_MODULE_CACHE_PATH=/tmp/papyrus-clang-module-cache \
    swift build -c "$SWIFTPM_CONFIGURATION" --package-path "$ROOT_DIR" --build-path "$SWIFTPM_BUILD_PATH"

  ensure_file "$SWIFTPM_BINARY"
  cp "$SWIFTPM_BINARY" "$APP_BINARY"

  if [[ -f "$SWIFTPM_ANALYZER" ]]; then
    cp "$SWIFTPM_ANALYZER" "$APP_ANALYZER"
  fi

  codesign --force --deep --sign - "$MAIN_APP"

  pkill -x Papyrus >/dev/null 2>&1 || true
  killall Finder Dock iconservicesagent iconservicesd >/dev/null 2>&1 || true

  local attempt
  for attempt in {1..15}; do
    if open "$MAIN_APP" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  for attempt in {1..15}; do
    if pgrep -x Papyrus >/dev/null 2>&1; then
      osascript -e 'tell application "Papyrus" to activate' >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done

  echo "Papyrus did not relaunch after icon update." >&2
  exit 1
}

safari_build_and_patch() {
  rm -rf "$SAFARI_DERIVED_DATA"
  rm -rf "$SAFARI_APPEX"
  mkdir -p "$(dirname "$SAFARI_APPEX")"

  PAPYRUS_ICON_SOURCE_PATH="$VARIANT_SOURCE" xcodebuild \
    -project "$SAFARI_PROJECT" \
    -scheme "$SAFARI_SCHEME" \
    -configuration Debug \
    -derivedDataPath "$SAFARI_DERIVED_DATA" \
    build

  ensure_file "$SAFARI_HOST_INFO"
  ensure_file "$SAFARI_BUILD_APPEX/Contents/Info.plist"
  ditto "$SAFARI_BUILD_APPEX" "$SAFARI_APPEX"
  rm -rf "$LEGACY_SAFARI_APP"
  /usr/bin/codesign --force --deep --sign - "$MAIN_APP"
  "$REPAIR_SAFARI_SIGNATURE_SCRIPT" "$MAIN_APP" >/dev/null
  "$LSREGISTER" -f -R -trusted "$MAIN_APP" >/dev/null
  /usr/bin/pluginkit -a "$SAFARI_APPEX" >/dev/null || true
  /usr/bin/pluginkit -r "$SAFARI_BUILD_APPEX" >/dev/null || true
  "$LSREGISTER" -u "$SAFARI_BUILD_APP" >/dev/null 2>&1 || true
  /usr/bin/pluginkit -r "$LEGACY_SAFARI_APPEX" >/dev/null 2>&1 || true
  "$LSREGISTER" -u "$LEGACY_SAFARI_APP" >/dev/null 2>&1 || true
  /usr/bin/pluginkit -a "$SAFARI_APPEX" >/dev/null || true
  assert_pluginkit_points_to_target
  rm -rf "$SAFARI_DERIVED_DATA"
}

write_report() {
  local main_icns_md5 safari_icns_md5 preview_md5 plugin_preview_md5 safari_preview_md5 file_icon_md5
  main_icns_md5=$(md5 -q "$MAIN_APP_ICNS")
  safari_icns_md5=$(md5 -q "$SAFARI_HOST_ICNS")
  preview_md5=$(md5 -q "$MAIN_PREVIEW")
  plugin_preview_md5=$(md5 -q "$PLUGIN_PREVIEW")
  safari_preview_md5=$(md5 -q "$SAFARI_PREVIEW")
  file_icon_md5=$(md5 -q "$MAIN_FILE_ICON_PREVIEW")

  cat > "$REPORT_FILE" <<EOF
macOS 26 icon validation report

Generated variant source:
- $VARIANT_SOURCE

Main app pipeline:
- Bundle: $MAIN_APP
- Info.plist: $MAIN_APP_INFO
- Assets.car: $MAIN_APP_ASSETS
- icns: $MAIN_APP_ICNS
- Preview PNG: $MAIN_PREVIEW
- File icon preview: $MAIN_FILE_ICON_PREVIEW
- icns md5: $main_icns_md5
- preview md5: $preview_md5
- file icon md5: $file_icon_md5

Safari host build pipeline:
- Bundle: $SAFARI_BUILD_APP
- Info.plist: $SAFARI_HOST_INFO
- Assets.car: $SAFARI_HOST_ASSETS
- icns: $SAFARI_HOST_ICNS
- Preview PNG: $PLUGIN_PREVIEW
- icns md5: $safari_icns_md5
- preview md5: $plugin_preview_md5

Safari transparent icon pipeline:
- Derived transparent source: $EXTENSION_SOURCE
- Repo icons: $EXTENSION_ICON_DIR
- Bundled appex manifest: $SAFARI_APPEX_MANIFEST
- Bundled appex icons: $SAFARI_APPEX_ICON_DIR
- Preview PNG: $SAFARI_PREVIEW
- preview md5: $safari_preview_md5

Detailed reports:
- $MAIN_ASSET_REPORT
- $PLUGIN_ASSET_REPORT
- $SAFARI_MANIFEST_REPORT
EOF
}

main() {
  ensure_command magick
  ensure_command swift
  ensure_command xcodebuild
  ensure_command iconutil
  ensure_command xcrun
  ensure_command rg
  ensure_command sips
  ensure_command codesign

  ensure_file "$BASE_SOURCE"
  ensure_file "$BUILD_SCRIPT"
  mkdir -p "$ARTIFACT_DIR"

  generate_variant_source

  main_app_build_and_launch
  safari_build_and_patch

  ensure_file "$MAIN_APP_INFO"
  ensure_file "$MAIN_APP_ICNS"
  ensure_file "$MAIN_APP_ASSETS"
  ensure_file "$SAFARI_APP_INFO"
  ensure_file "$SAFARI_APP_ICNS"
  ensure_file "$SAFARI_APP_ASSETS"
  ensure_file "$SAFARI_APPEX_MANIFEST"
  ensure_file "$EXTENSION_SOURCE"
  ensure_file "$EXTENSION_ICON_DIR/icon-1024.png"
  ensure_file "$SAFARI_APPEX_ICON_DIR/icon-1024.png"

  assert_bundle_icon_name "$MAIN_APP_INFO" Papyrus
  assert_bundle_icon_name "$SAFARI_APP_INFO" Papyrus
  assert_asset_catalog_contains_icon "$MAIN_APP_ASSETS" Papyrus "$MAIN_ASSET_REPORT"
  assert_asset_catalog_contains_icon "$SAFARI_APP_ASSETS" Papyrus "$PLUGIN_ASSET_REPORT"
  assert_manifest_points_to_icons "$SAFARI_APPEX_MANIFEST" "$SAFARI_MANIFEST_REPORT"

  extract_preview_from_icns "$MAIN_APP_ICNS" "$MAIN_PREVIEW"
  extract_preview_from_icns "$SAFARI_APP_ICNS" "$PLUGIN_PREVIEW"
  cp "$EXTENSION_ICON_DIR/icon-1024.png" "$SAFARI_PREVIEW"
  render_file_icon "$MAIN_APP" "$MAIN_FILE_ICON_PREVIEW"

  if [[ "$(md5 -q "$MAIN_PREVIEW")" == "$(md5 -q "$PLUGIN_PREVIEW")" ]]; then
    echo "Main app preview and plugin app preview should differ, but they are identical." >&2
    exit 1
  fi

  assert_transparent_corner "$EXTENSION_SOURCE"
  assert_transparent_corner "$SAFARI_PREVIEW"

  if [[ "$(md5 -q "$EXTENSION_ICON_DIR/icon-1024.png")" != "$(md5 -q "$SAFARI_APPEX_ICON_DIR/icon-1024.png")" ]]; then
    echo "Bundled appex icon does not match repo-generated icon-1024.png" >&2
    exit 1
  fi

  write_report

  echo "Validation complete."
  echo "Report: $REPORT_FILE"
  echo "Artifacts: $ARTIFACT_DIR"
}

main "$@"

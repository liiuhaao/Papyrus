#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DEFAULT_SOURCE_PNG="${PAPYRUS_ICON_SOURCE_PATH:-${PAPYRUS_ICON_SOURCE:-$ROOT_DIR/assets/icons/Papyrus-macos26-source.png}}"
DEFAULT_ICON_NAME="Papyrus"

ensure_source_png() {
  local source_png="$1"
  if [[ ! -f "$source_png" ]]; then
    echo "Missing source icon: $source_png" >&2
    exit 1
  fi
}

write_asset_catalog() {
  local asset_catalog="$1"
  local appiconset="$2"
  local icon_name="$3"

  mkdir -p "$appiconset"

  cat > "$asset_catalog/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

  cat > "$appiconset/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

generate_icon_png() {
  local size="$1"
  local input_png="$2"
  local output_png="$3"
  sips -z "$size" "$size" "$input_png" --out "$output_png" >/dev/null
}

compile_bundle_icon() {
  local source_png="$1"
  local app_bundle="$2"
  local app_info_plist="$3"
  local icon_name="$4"
  local update_info_plist="${5:-yes}"

  if [[ ! -d "$app_bundle" ]]; then
    echo "Missing app bundle: $app_bundle" >&2
    exit 1
  fi

  local work_dir
  work_dir=$(mktemp -d /tmp/papyrus-appicon.XXXXXX)
  local asset_catalog="$work_dir/AppIcons.xcassets"
  local appiconset="$asset_catalog/$icon_name.appiconset"
  local actool_output="$work_dir/actool-output"
  local partial_info_plist="$work_dir/icon-info.plist"
  local app_resources="$app_bundle/Contents/Resources"

  mkdir -p "$actool_output" "$app_resources"
  write_asset_catalog "$asset_catalog" "$appiconset" "$icon_name"

  generate_icon_png 16 "$source_png" "$appiconset/icon_16x16.png"
  generate_icon_png 32 "$source_png" "$appiconset/icon_16x16@2x.png"
  generate_icon_png 32 "$source_png" "$appiconset/icon_32x32.png"
  generate_icon_png 64 "$source_png" "$appiconset/icon_32x32@2x.png"
  generate_icon_png 128 "$source_png" "$appiconset/icon_128x128.png"
  generate_icon_png 256 "$source_png" "$appiconset/icon_128x128@2x.png"
  generate_icon_png 256 "$source_png" "$appiconset/icon_256x256.png"
  generate_icon_png 512 "$source_png" "$appiconset/icon_256x256@2x.png"
  generate_icon_png 512 "$source_png" "$appiconset/icon_512x512.png"
  generate_icon_png 1024 "$source_png" "$appiconset/icon_512x512@2x.png"

  xcrun actool "$asset_catalog" \
    --compile "$actool_output" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon "$icon_name" \
    --output-partial-info-plist "$partial_info_plist" \
    --output-format human-readable-text >/dev/null

  if [[ ! -f "$actool_output/Assets.car" ]]; then
    echo "actool did not produce Assets.car" >&2
    exit 1
  fi

  if [[ ! -f "$actool_output/$icon_name.icns" ]]; then
    echo "actool did not produce $icon_name.icns" >&2
    exit 1
  fi

  cp "$actool_output/Assets.car" "$app_resources/Assets.car"
  cp "$actool_output/$icon_name.icns" "$app_resources/$icon_name.icns"

  if [[ "$update_info_plist" == "yes" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $icon_name" "$app_info_plist" >/dev/null 2>&1 || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $icon_name" "$app_info_plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconName $icon_name" "$app_info_plist" >/dev/null 2>&1 || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $icon_name" "$app_info_plist" >/dev/null
    touch "$app_info_plist" "$app_resources/Assets.car" "$app_resources/$icon_name.icns" "$app_bundle"
  fi
  rm -rf "$work_dir"
}

build_main_app_icon() {
  local source_png="${1:-$DEFAULT_SOURCE_PNG}"
  local app_bundle="$ROOT_DIR/Papyrus.app"
  local app_info_plist="$app_bundle/Contents/Info.plist"

  ensure_source_png "$source_png"
  compile_bundle_icon "$source_png" "$app_bundle" "$app_info_plist" "$DEFAULT_ICON_NAME" yes
  echo "Updated app icon assets in $app_bundle"
}

build_safari_host_icon() {
  local app_bundle="${1:-}"
  local source_png="${2:-$DEFAULT_SOURCE_PNG}"
  local icon_name="${3:-$DEFAULT_ICON_NAME}"
  local app_info_plist="$app_bundle/Contents/Info.plist"

  if [[ -z "$app_bundle" ]]; then
    echo "Usage: $0 safari-host <app-bundle> [source-png] [icon-name]" >&2
    exit 1
  fi

  ensure_source_png "$source_png"
  compile_bundle_icon "$source_png" "$app_bundle" "$app_info_plist" "$icon_name" no
  echo "Updated Safari host icon assets in $app_bundle"
}

build_extension_icons() {
  local source_png="${1:-$DEFAULT_SOURCE_PNG}"
  local derived_source="$ROOT_DIR/assets/icons/Papyrus-extension-source.png"
  local output_dir="$ROOT_DIR/browser-extension/icons"
  local background_fuzz="${BACKGROUND_FUZZ:-12%}"

  ensure_source_png "$source_png"
  if ! command -v magick >/dev/null 2>&1; then
    echo "Skipping extension icon rebuild: magick not available" >&2
    return 0
  fi
  mkdir -p "$output_dir"

  magick "$source_png" \
    -alpha set \
    -fuzz "$background_fuzz" \
    -fill none \
    -draw "color 0,0 floodfill" \
    -draw "color 2047,0 floodfill" \
    -draw "color 0,2047 floodfill" \
    -draw "color 2047,2047 floodfill" \
    "$derived_source"

  generate_icon_png 16 "$derived_source" "$output_dir/icon-16.png"
  generate_icon_png 32 "$derived_source" "$output_dir/icon-32.png"
  generate_icon_png 48 "$derived_source" "$output_dir/icon-48.png"
  generate_icon_png 128 "$derived_source" "$output_dir/icon-128.png"
  generate_icon_png 512 "$derived_source" "$output_dir/icon-512.png"
  generate_icon_png 1024 "$derived_source" "$output_dir/icon-1024.png"

  echo "Updated browser extension source: $derived_source"
  echo "Updated browser extension icons in $output_dir"
}

build_all_icons() {
  local app_bundle="${1:-}"
  local source_png="${2:-$DEFAULT_SOURCE_PNG}"
  local icon_name="${3:-$DEFAULT_ICON_NAME}"

  if [[ -z "$app_bundle" ]]; then
    echo "Usage: $0 all <safari-host-app-bundle> [source-png] [icon-name]" >&2
    exit 1
  fi

  build_main_app_icon "$source_png"
  build_safari_host_icon "$app_bundle" "$source_png" "$icon_name"
  build_extension_icons "$source_png"
}

usage() {
  cat <<EOF
Usage:
  $0 app [source-png]
  $0 safari-host <app-bundle> [source-png] [icon-name]
  $0 extension [source-png]
  $0 all <safari-host-app-bundle> [source-png] [icon-name]
EOF
}

command="${1:-}"
case "$command" in
  app)
    shift
    build_main_app_icon "${1:-$DEFAULT_SOURCE_PNG}"
    ;;
  safari-host)
    shift
    build_safari_host_icon "${1:-}" "${2:-$DEFAULT_SOURCE_PNG}" "${3:-$DEFAULT_ICON_NAME}"
    ;;
  extension)
    shift
    build_extension_icons "${1:-$DEFAULT_SOURCE_PNG}"
    ;;
  all)
    shift
    build_all_icons "${1:-}" "${2:-$DEFAULT_SOURCE_PNG}" "${3:-$DEFAULT_ICON_NAME}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

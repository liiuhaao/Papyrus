#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/assets/icons/Papyrus-macos26-rendered-512.png"
DEFAULT_OUTPUT="$ROOT/assets/papyrus-showcase.png"
OUTPUT_PATH=""
POSITIONAL=()

usage() {
  cat >&2 <<'EOF'
Usage:
  tools/build_showcase.sh [--output path] <light-list-screenshot> <dark-gallery-screenshot>

Example:
  tools/build_showcase.sh assets/SCR-light.png assets/SCR-dark.png
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || usage
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
  usage
fi

LIGHT_LIST_INPUT="${POSITIONAL[1]}"
DARK_GALLERY_INPUT="${POSITIONAL[2]}"
OUTPUT_PATH="${OUTPUT_PATH:-$DEFAULT_OUTPUT}"

if [[ ! -f "$LIGHT_LIST_INPUT" ]]; then
  echo "Missing light/list screenshot: $LIGHT_LIST_INPUT" >&2
  exit 1
fi

if [[ ! -f "$DARK_GALLERY_INPUT" ]]; then
  echo "Missing dark/gallery screenshot: $DARK_GALLERY_INPUT" >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  echo "Missing rendered app icon: $ICON" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick ('magick') is required." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d /tmp/papyrus-showcase.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

WIDTH=3200
HEIGHT=2000

magick "$LIGHT_LIST_INPUT" -trim +repage "$TMP_DIR/list.png"
magick "$DARK_GALLERY_INPUT" -trim +repage "$TMP_DIR/gallery.png"

magick "$TMP_DIR/list.png" -resize 2320x "$TMP_DIR/list_resized.png"
magick "$TMP_DIR/gallery.png" -resize 1920x "$TMP_DIR/gallery_resized.png"

magick "$TMP_DIR/gallery_resized.png" \
  -background none -virtual-pixel none +distort SRT '-1.8' \
  "$TMP_DIR/gallery_tilt.png"

magick "$TMP_DIR/list_resized.png" \
  -background none -virtual-pixel none +distort SRT '0.45' \
  "$TMP_DIR/list_tilt.png"

magick "$TMP_DIR/gallery_tilt.png" -background none -shadow 82x34+0+30 "$TMP_DIR/gallery_shadow.png"
magick "$TMP_DIR/list_tilt.png" -background none -shadow 92x40+0+34 "$TMP_DIR/list_shadow.png"

magick -size ${WIDTH}x${HEIGHT} gradient:'#d7cbbb-#6f7074' -define gradient:angle=103 "$TMP_DIR/base.png"
magick -size ${WIDTH}x${HEIGHT} gradient:'rgba(250,242,229,0.34)-rgba(250,242,229,0)' -define gradient:angle=180 "$TMP_DIR/top_wash.png"
magick -size 1900x1900 radial-gradient:'rgba(226,176,104,0.34)-rgba(226,176,104,0)' "$TMP_DIR/warm_window_glow.png"
magick -size 2200x2200 radial-gradient:'rgba(42,56,77,0.42)-rgba(42,56,77,0)' "$TMP_DIR/cool_glow.png"
magick -size 2400x1500 radial-gradient:'rgba(0,0,0,0.24)-rgba(0,0,0,0)' "$TMP_DIR/lower_shadow.png"
magick -size ${WIDTH}x${HEIGHT} radial-gradient:'rgba(0,0,0,0)-rgba(0,0,0,0.18)' "$TMP_DIR/vignette.png"
magick -size ${WIDTH}x${HEIGHT} gradient:'rgba(24,30,40,0)-rgba(24,30,40,0.26)' -define gradient:angle=28 "$TMP_DIR/right_falloff.png"
magick -size 290x80 xc:none -fill 'rgba(47,46,49,0.64)' -stroke 'rgba(255,245,232,0.10)' -strokewidth 2 \
  -draw 'roundrectangle 1,1 289,79 26,26' "$TMP_DIR/dark_pill.png"
magick -size 260x80 xc:none -fill 'rgba(244,238,229,0.88)' -stroke 'rgba(88,80,72,0.10)' -strokewidth 2 \
  -draw 'roundrectangle 1,1 259,79 26,26' "$TMP_DIR/light_pill.png"

mkdir -p "$(dirname "$OUTPUT_PATH")"

magick "$TMP_DIR/base.png" \
  \( "$TMP_DIR/top_wash.png" \) -compose screen -composite \
  \( "$TMP_DIR/warm_window_glow.png" \) -geometry -260+340 -compose screen -composite \
  \( "$TMP_DIR/cool_glow.png" \) -geometry +1840+120 -compose screen -composite \
  \( "$TMP_DIR/lower_shadow.png" \) -geometry +1040+1040 -compose multiply -composite \
  \( "$TMP_DIR/right_falloff.png" \) -compose multiply -composite \
  \( "$TMP_DIR/gallery_shadow.png" \) -geometry +1160+210 -compose over -composite \
  \( "$TMP_DIR/gallery_tilt.png" \) -geometry +1190+220 -compose over -composite \
  \( "$TMP_DIR/list_shadow.png" \) -geometry +88+608 -compose over -composite \
  \( "$TMP_DIR/list_tilt.png" \) -geometry +118+632 -compose over -composite \
  \( "$TMP_DIR/vignette.png" \) -compose multiply -composite \
  \( "$ICON" -resize 126x126 \) -geometry +136+92 -compose over -composite \
  \( "$TMP_DIR/dark_pill.png" \) -geometry +2452+140 -compose over -composite \
  \( "$TMP_DIR/light_pill.png" \) -geometry +226+536 -compose over -composite \
  -font Helvetica -fill '#203247' -pointsize 90 -annotate +292+172 'Papyrus' \
  -font Helvetica -fill 'rgba(48,60,74,0.72)' -pointsize 34 -annotate +296+226 'Native macOS paper manager' \
  -font Helvetica -fill '#f8fafc' -pointsize 30 -annotate +2518+190 'Dark / Gallery' \
  -font Helvetica -fill '#5b4836' -pointsize 30 -annotate +288+586 'Light / List' \
  "$OUTPUT_PATH"

echo "Created showcase image:"
echo "  $OUTPUT_PATH"

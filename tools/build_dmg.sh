#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Papyrus.app"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: tools/build_dmg.sh <version>" >&2
  echo "Example: tools/build_dmg.sh v0.1.0" >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "Papyrus.app not found: $APP" >&2
  echo "Run tools/build_and_launch_app.sh first." >&2
  exit 1
fi

RELEASE_DIR="$ROOT/release/$VERSION"
STAGING_DIR="$RELEASE_DIR/dmg-staging"
VOLUME_NAME="Papyrus"
DMG_PATH="$RELEASE_DIR/Papyrus.dmg"

mkdir -p "$RELEASE_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
rm -f "$DMG_PATH"

/usr/bin/ditto "$APP" "$STAGING_DIR/Papyrus.app"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Created DMG at:"
echo "  $DMG_PATH"

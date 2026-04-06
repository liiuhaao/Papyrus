#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_APP="${1:-$ROOT/Papyrus.app}"
APPEX="$MAIN_APP/Contents/PlugIns/Papyrus Web Clipper Extension.appex"
ENTITLEMENTS="$ROOT/tools/papyrus_safari_extension.entitlements"

if [[ ! -d "$MAIN_APP" ]]; then
  echo "Main app not found: $MAIN_APP" >&2
  exit 1
fi

if [[ ! -d "$APPEX" ]]; then
  echo "Embedded Safari extension not found: $APPEX" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

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

SIGNING_IDENTITY="$(resolve_codesign_identity)"

/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$APPEX"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$MAIN_APP"
/usr/bin/codesign --verify --deep --strict "$MAIN_APP"

echo "Re-signed embedded Safari extension at:"
echo "  $APPEX"

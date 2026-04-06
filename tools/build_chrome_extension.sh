#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/browser-extension"
DST="$REPO_ROOT/chrome-extension"

echo "Building Chrome extension..."

rm -rf "$DST/src" "$DST/icons"
cp -r "$SRC/src" "$DST/src"
cp -r "$SRC/icons" "$DST/icons"
/usr/bin/python3 - "$SRC/manifest.json" "$DST/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

manifest = json.loads(src.read_text())
permissions = manifest.get("permissions", [])
manifest["permissions"] = [
    permission for permission in permissions
    if permission != "nativeMessaging"
]

dst.write_text(json.dumps(manifest, indent=2) + "\n")
PY

rm -f "$DST/README.md"

echo "Done. Load '$DST' in Chrome via chrome://extensions (Developer mode → Load unpacked)."

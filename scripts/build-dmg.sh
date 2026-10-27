#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
test -d dist/Zero-K.app || { echo "Run ./scripts/build-app.sh first." >&2; exit 1; }
UV_CACHE_DIR="$ROOT/build/uv-cache" uv run --no-project --python python3 python scripts/audit-app.py
STAGING="$(mktemp -d "$ROOT/build/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Zero-K.app "$STAGING/Zero-K.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Zero-K" -srcfolder "$STAGING" -format UDZO -ov dist/Zero-K-macOS-arm64.dmg
(cd dist && shasum -a 256 Zero-K-macOS-arm64.dmg > Zero-K-macOS-arm64.dmg.sha256)
echo "$ROOT/dist/Zero-K-macOS-arm64.dmg"

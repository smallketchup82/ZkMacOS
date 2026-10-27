#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
test -d dist/Zero-K.app || { echo "Run ./scripts/build-app.sh first." >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "Install create-dmg with brew install create-dmg." >&2; exit 1; }
UV_CACHE_DIR="$ROOT/build/uv-cache" uv run --no-project --python python3 python scripts/audit-app.py
mkdir -p build/swift-cache
swiftc -O -module-cache-path build/swift-cache app/dmg-background.swift -o build/dmg-background
build/dmg-background "$ROOT/build/dmg-background.tiff"
# Let Finder finish applying the view and avoid reopening into tab defaults on
# macOS 27. Patch a build-local copy, never the installed tool.
CREATE_DMG_PREFIX="$(brew --prefix create-dmg)"
mkdir -p build/create-dmg/support
install -m 755 "$CREATE_DMG_PREFIX/bin/create-dmg" build/create-dmg/create-dmg
install -m 644 "$CREATE_DMG_PREFIX/share/create-dmg/support/"* build/create-dmg/support/
touch build/create-dmg/.this-is-the-create-dmg-repo
patch -s -d build/create-dmg -p1 < patches/create-dmg-finder-timing.patch
STAGING="$(mktemp -d "$ROOT/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Zero-K.app "$STAGING/Zero-K.app"
build/create-dmg/create-dmg \
	--volname "Zero-K" \
	--volicon "$ROOT/dist/Zero-K.app/Contents/Resources/Zero-K.icns" \
	--background "$ROOT/build/dmg-background.tiff" \
	--window-pos 200 160 \
	--window-size 640 382 \
	--icon-size 112 \
	--text-size 14 \
	--icon "Zero-K.app" 160 180 \
	--hide-extension "Zero-K.app" \
	--app-drop-link 480 180 \
	--no-internet-enable \
	--overwrite \
	"$ROOT/dist/Zero-K-macOS-arm64.dmg" "$STAGING"
(cd dist && shasum -a 256 Zero-K-macOS-arm64.dmg > Zero-K-macOS-arm64.dmg.sha256)
echo "$ROOT/dist/Zero-K-macOS-arm64.dmg"

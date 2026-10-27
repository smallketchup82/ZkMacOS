#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/logs
export UV_CACHE_DIR="$ROOT/build/uv-cache"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1

uv run --no-project --python python3 python scripts/fetch-sources.py
uv run --no-project --python python3 python scripts/fetch-assets.py
ENGINE_VERSION="$(uv run --no-project --python python3 python -c 'import json; print(json.load(open("sources.lock.json"))["recoil"]["engine_version"])')"
if [ ! -f build/mesa/lib/libEGL.1.dylib ]; then
	mkdir -p build/mesa-work
	cp .cache/mesa-26.3.0-rc1.tar.xz build/mesa-work/mesa-26.3.0-rc1.tar
	cp .cache/mesa-libclc-22.1.8.3.tar.bz2 build/mesa-work/
	bash scripts/build-mesa.sh "$ROOT/build/mesa-work" "$ROOT/build/mesa" > build/logs/mesa.log 2>&1
fi
ENGINE_CMAKE_ARGS=(-S "$ROOT/external/recoil" -B "$ROOT/build/engine" -G Ninja
	-DCMAKE_C_COMPILER="$(brew --prefix gcc)/bin/gcc-16"
	-DCMAKE_CXX_COMPILER="$(brew --prefix gcc)/bin/g++-16"
	-DCMAKE_BUILD_TYPE=RelWithDebInfo -DMAC_MESA_PREFIX="$ROOT/build/mesa"
	-DVERSION_OVERRIDE="$ENGINE_VERSION")
if command -v ccache >/dev/null; then
	ENGINE_CMAKE_ARGS+=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi
ENGINE_CONFIGURATION="$(printf '%s\n' "${ENGINE_CMAKE_ARGS[@]}" | shasum -a 256)"
if [ ! -f build/engine/CMakeCache.txt ] || [ "${RECONFIGURE_ENGINE:-0}" = 1 ] || \
	[ "$(cat build/engine/zk-configuration.sha256 2>/dev/null || true)" != "$ENGINE_CONFIGURATION" ]; then
	cmake "${ENGINE_CMAKE_ARGS[@]}" > build/logs/engine-configure.log 2>&1
	printf '%s\n' "$ENGINE_CONFIGURATION" > build/engine/zk-configuration.sha256
fi
# Ninja tracks source/header/CMake dependencies; never clean the engine here.
cmake --build build/engine --parallel "${BUILD_JOBS:-5}" \
	--target engine-legacy basecontent CircuitAI C-AIInterface > build/logs/engine-build.log 2>&1

export ZEROK_BUILD_DIR="$ROOT/build"
export ZEROK_STEAM_LIBRARY="$ROOT/.cache/steamworks-2025.164.1/OSX-Linux-x64/steam_api.bundle/Contents/MacOS/libsteam_api.dylib"
bash scripts/build-client.sh > build/logs/client-build.log 2>&1
dotnet publish external/infrastructure/ChobbyLauncher/ChobbyLauncher.Mac.csproj \
	-c Release -o build/client-arm64 -p:BaseIntermediateOutputPath=obj/mac/ \
	-p:LegacyClient="$ROOT/build/client" -p:SteamworksSource="$ROOT/.cache/steamworks-source" \
	-p:DebugType=None -p:DebugSymbols=false > build/logs/helper-build.log 2>&1
cp "$ZEROK_STEAM_LIBRARY" build/client-arm64/libsteam_api.dylib
MESA_PREFIX="$ROOT/build/mesa" uv run --no-project --python python3 python scripts/build-app.py > build/logs/package.log 2>&1
uv run --no-project --python python3 python scripts/audit-app.py | tee build/logs/app-audit.json
echo "Built $ROOT/dist/Zero-K.app"

#!/bin/bash
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
CHOBBY="$WORKSPACE/external/chobby"
INFRA="${ZEROK_INFRA_SOURCE:-$WORKSPACE/external/infrastructure}"
OUTPUT="${ZEROK_BUILD_DIR:-$WORKSPACE/build}"
STEAM="${ZEROK_STEAM_LIBRARY:-$WORKSPACE/.cache/steamworks-2025.164.1/OSX-Linux-x64/steam_api.bundle/Contents/MacOS/libsteam_api.dylib}"

mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
test -f "$STEAM" || { echo "Set ZEROK_STEAM_LIBRARY to the Steamworks.NET 11 macOS library." >&2; exit 1; }

msbuild "$INFRA/ChobbyLauncher/ChobbyLauncher.csproj" /restore /t:Rebuild \
	/p:Configuration=Release /p:Platform=x64 /p:PlatformTarget=AnyCPU \
	/p:RestorePackagesPath="$OUTPUT/nuget" /verbosity:minimal \
	> "$OUTPUT/launcher-build.log" 2>&1 \
	|| { tail -n 30 "$OUTPUT/launcher-build.log"; exit 1; }

UV_CACHE_DIR="$OUTPUT/uv-cache" uv run --no-project --python python3 python - "$CHOBBY" "$INFRA" "$OUTPUT" "$STEAM" <<'PY'
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
from zipfile import ZIP_DEFLATED, ZipFile

chobby, infra, output, steam = map(Path, sys.argv[1:])
client = output / 'client'
resources = output / 'resources'
client.mkdir(parents=True, exist_ok=True)
(resources / 'games').mkdir(parents=True, exist_ok=True)

for file in (infra / 'ChobbyLauncher/bin/Release').iterdir():
    if file.is_file() and (file.suffix in ('.dll', '.config') or file.name in ('Zero-K.exe', 'Zero-K.version.txt')):
        shutil.copy2(file, client / file.name)
shutil.copy2(steam, client / 'libsteam_api.dylib')
(client / 'steam_appid.txt').write_text('334920\n')
shutil.copytree(chobby / 'macos/game-data', resources, dirs_exist_ok=True)

archive = resources / 'games/Chobby-macos.sdz'
files = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=chobby).decode().split('\0')
with ZipFile(archive, 'w', ZIP_DEFLATED, compresslevel=6) as package:
    for name in sorted(set(files)):
        if not name or name.startswith('macos/') or '.DS_Store' in Path(name).parts:
            continue
        file = chobby / name
        if not file.is_file():
            continue
        if file.suffix.lower() in ('.dll', '.so', '.exe', '.pdb'):
            continue  # AI/runtime binaries are built and bundled separately for ARM64.
        content = file.read_bytes()
        if name == 'modinfo.lua':
            content = content.replace(b'"$VERSION"', b'"macos-source"')
        package.writestr(name, content)

manifest = {'menu': 'Chobby macos-source', 'launcher': 'client/Zero-K.exe', 'resources': 'resources', 'sources': {}}
for name, repo in [('chobby', chobby), ('infrastructure', infra)]:
    manifest['sources'][name] = {
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip(),
        'modified': bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=repo)),
    }
manifest['lobby_sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / 'client-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Built {client / "Zero-K.exe"}')
print(f'Packaged {archive} ({archive.stat().st_size // 1048576} MiB)')
print('Development build: Mono and native engine dependencies still come from this machine.')
PY

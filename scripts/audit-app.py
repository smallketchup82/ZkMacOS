"""Check bundle containment, native dependencies, architecture and signatures."""
from pathlib import Path
import argparse
import base64
import importlib.util
import json
import plistlib
import subprocess
import struct

parser = argparse.ArgumentParser()
parser.add_argument('application', nargs='?', type=Path, default=Path(__file__).resolve().parents[1] / 'dist/Zero-K.app')
args = parser.parse_args()
app = args.application.resolve()
spec = importlib.util.spec_from_file_location('libraries', Path(__file__).with_name('bundle-libraries.py'))
libraries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(libraries)
errors, binaries = [], []
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info.get('LSApplicationCategoryType') != 'public.app-category.strategy-games':
    errors.append('Missing strategy game application category')
if info.get('LSSupportsGameMode') is not True:
    errors.append('Game Mode support must be enabled')
for file in app.rglob('*'):
    relative = str(file.relative_to(app))
    if file.is_symlink() and not file.resolve().is_relative_to(app):
        errors.append('External symlink: ' + relative)
    if file.name in ('.DS_Store', 'IGL_data.lua', 'IGL_order.lua', 'infolog.txt', 'infolog_full.txt', 'chobby_wrapper_port.txt'):
        errors.append('User data or build metadata: ' + relative)
    if file.is_file() and file.suffix.lower() in ('.dll', '.exe'):
        with file.open('rb') as stream:
            header = stream.read(64)
            if header[:2] == b'MZ' and len(header) == 64:
                stream.seek(struct.unpack_from('<I', header, 60)[0] + 4)
                if stream.read(2) == b'\x64\x86':
                    errors.append('Intel-specific managed assembly: ' + relative)
    if not libraries.macho(file):
        continue
    binaries.append(relative)
    sparkle_binary = relative.startswith('Contents/Frameworks/Sparkle.framework/')
    arches = libraries.command('lipo', '-archs', file).split()
    if 'arm64' not in arches or (not sparkle_binary and arches != ['arm64']):
        errors.append('Non-ARM64 native binary: ' + relative)
    own_id = libraries.command('otool', '-D', file).splitlines()[1:]
    for dependency in libraries.dependencies(file):
        if dependency in own_id or dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if relative == 'Contents/MacOS/Zero-K' and dependency == '@rpath/Sparkle.framework/Versions/B/Sparkle':
            if not (app / 'Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle').is_file():
                errors.append('Missing Sparkle framework')
            continue
        if not dependency.startswith('@loader_path/'):
            errors.append(f'External dependency in {relative}: {dependency}')
            continue
        target = (file.parent / dependency[len('@loader_path/'):]).resolve()
        if not target.is_relative_to(app) or not target.is_file():
            errors.append(f'Unresolved bundle dependency in {relative}: {dependency}')
    for path in libraries.rpaths(file):
        if not path.startswith('@loader_path'):
            errors.append(f'External rpath in {relative}: {path}')
    result = subprocess.run(['codesign', '--verify', '--strict', str(file)], capture_output=True, text=True)
    if result.returncode:
        errors.append('Invalid code signature: ' + relative)
framework = app / 'Contents/Frameworks/Sparkle.framework'
if not framework.is_dir():
    errors.append('Missing Sparkle framework')
else:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(framework)], check=True)
if 'SUPublicEDKey' in info:
    try:
        if len(base64.b64decode(info['SUPublicEDKey'], validate=True)) != 32:
            raise ValueError('Wrong public key length')
    except (ValueError, TypeError):
        errors.append('Invalid Sparkle public key')
    if info.get('SUFeedURL') != 'https://github.com/smallketchup82/ZkMacOS/releases/latest/download/appcast.xml':
        errors.append('Unexpected Sparkle release feed')
    for key in ('SUVerifyUpdateBeforeExtraction', 'SURequireSignedFeed'):
        if info.get(key) is not True:
            errors.append('Missing Sparkle security setting: ' + key)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
expected_version = json.loads((Path(__file__).resolve().parents[1] / 'sources.lock.json').read_text())['recoil']['engine_version']
engine_version = subprocess.check_output([str(app / 'Contents/MacOS/spring'), '--sync-version'], text=True).strip()
if engine_version != expected_version:
    errors.append(f'Engine version mismatch: expected {expected_version}, got {engine_version}')
report = {'application': app.name, 'native_binaries': len(binaries), 'all_arm64': not errors, 'errors': errors}
print(json.dumps(report, indent=2))
if errors:
    raise SystemExit(1)

"""Stage only build outputs and public defaults, then produce the portable app."""
from pathlib import Path
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import hashlib
import base64
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundle_libraries', Path(__file__).with_name('bundle-libraries.py'))
libraries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(libraries)
build = root / 'build'
dist = root / 'dist'
# Local builds without a key can run, but never start an unauthenticated updater.
public_key = os.environ.get('SPARKLE_PUBLIC_ED_KEY', '').strip()
if public_key and len(base64.b64decode(public_key, validate=True)) != 32:
    raise ValueError('SPARKLE_PUBLIC_ED_KEY must be a base64-encoded 32-byte public key.')
dist.mkdir(exist_ok=True)
running = subprocess.check_output(['ps', '-axo', 'comm='], text=True)
if any(line.startswith(str(dist / 'Zero-K.app/Contents') + '/') for line in running.splitlines()):
    raise SystemExit('Close the running Zero-K.app before replacing this build.')
stage = Path(tempfile.mkdtemp(prefix='.app-stage-', dir=dist)) / 'Zero-K.app'
contents = stage / 'Contents'
resources = contents / 'Resources'
frameworks = contents / 'Frameworks'
mesa = Path(os.environ.get('MESA_PREFIX', root / 'build/mesa'))
engine_source = root / 'external/recoil'
chobby = root / 'external/chobby'
engine_build = build / 'engine'


def copy(source, target):
    source, target = Path(source), Path(target)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('.DS_Store', '*.pdb', '*.so', '*.dll', '*.exe'))
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


for directory in ('MacOS', 'Resources/client', 'Resources/licenses', 'Frameworks'):
    (contents / directory).mkdir(parents=True, exist_ok=True)
shutil.copytree(build / 'client-arm64', resources / 'client', dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.pdb'))
copy(build / 'resources', resources / 'data')
copy(engine_build / 'base', resources / 'data/base')
copy(engine_source / 'cont/fonts', resources / 'data/fonts')
copy(root / 'app/defaults', resources / 'defaults')
copy(root / 'app/fontconfig.conf', resources / 'fontconfig.conf')

# Public AI profiles come from Chobby, not from a developer's writable directory.
native_roots = [(engine_build / 'spring', contents / 'MacOS/spring')]
interface = resources / 'data/AI/Interfaces/C/0.1'
copy(engine_source / 'AI/Interfaces/C/data/InterfaceInfo.lua', interface / 'InterfaceInfo.lua')
native_roots.append((engine_build / 'AI/Interfaces/C/data/libAIInterface.dylib', interface / 'libAIInterface.dylib'))
for difficulty in ('Beginner', 'Novice', 'Easy', 'Hard', 'Brutal', 'Normal'):
    profile = '1052188CircuitAI' + difficulty + '64'
    source = chobby / 'LuaMenu/configs/gameConfig/zk/defaultSettings/AI/Skirmish' / profile / 'stable'
    if not source.is_dir():
        if difficulty == 'Normal':
            continue
        raise RuntimeError(f'Missing AI profile {source}')
    target = resources / 'data/AI/Skirmish' / profile / 'stable'
    common = chobby / 'LuaMenu/configs/gameConfig/zk/defaultSettings/AI/Skirmish/1052188CircuitAICommon64/stable'
    copy(common, target)
    copy(source, target)
    native_roots.append((engine_build / 'AI/Skirmish/CircuitAI/data/libSkirmishAI.dylib', target / 'libSkirmishAI.dylib'))

mesa_lib = frameworks
for name in ('libEGL.1.dylib', 'libvulkan_kosmickrisp.dylib'):
    native_roots.append((mesa / 'lib' / name, mesa_lib / name))
for file in (mesa / 'lib').glob('libgallium-*.dylib'):
    native_roots.append((file, mesa_lib / file.name))
native_roots += [(Path('/opt/homebrew/opt/sdl3/lib/libSDL3.dylib'), frameworks / 'libSDL3.dylib'),
                 (Path('/opt/homebrew/opt/vulkan-loader/lib/libvulkan.1.dylib'), frameworks / 'libvulkan.1.dylib')]
native_files = libraries.bundle(native_roots, frameworks, 'arm64')
icd = resources / 'kosmickrisp_mesa_icd.aarch64.json'
icd.write_text(json.dumps({'file_format_version': '1.0.0', 'ICD': {'library_path': '../Frameworks/libvulkan_kosmickrisp.dylib', 'api_version': '1.3.0'}}, indent=2) + '\n')

helper_roots = []
for file in (build / 'client-arm64').iterdir():
    if libraries.macho(file):
        helper_roots.append((file, resources / 'client' / file.name))
native_files.update(libraries.bundle(helper_roots, resources / 'client', 'arm64'))

# Preserve Sparkle's signed universal binaries, framework layout and symlinks.
# Do not pass these binaries through the engine's dylib relocation/thinning code.
sparkle = root / '.cache/sparkle-2.10.1'
shutil.copytree(sparkle / 'Sparkle.framework', frameworks / 'Sparkle.framework', symlinks=True)
copy(sparkle / 'LICENSE', resources / 'licenses/Sparkle-MIT.txt')
subprocess.run(['swiftc', '-O', '-module-cache-path', str(build / 'swift-cache'), '-target', 'arm64-apple-macos26.0', '-framework', 'AppKit', '-F', str(frameworks), '-framework', 'Sparkle',
                '-Xlinker', '-rpath', '-Xlinker', '@loader_path/../Frameworks',
                str(root / 'app/main.swift'), '-o', str(contents / 'MacOS/Zero-K')], check=True)
iconset = build / 'Zero-K.iconset'
iconset.mkdir(exist_ok=True)
icon = root / 'external/infrastructure/presskit/images/icon.png'
for size in (16, 32, 128, 256, 512):
    for density in (1, 2):
        name = f'icon_{size}x{size}' + ('@2x' if density == 2 else '') + '.png'
        pixels = str(size * density)
        subprocess.run(['sips', '-z', pixels, pixels, str(icon), '--out', str(iconset / name)], check=True, capture_output=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'Zero-K.icns')], check=True)
version = os.environ.get('ZKMACOS_VERSION', '0.1.0')
info = {'CFBundleExecutable': 'Zero-K', 'CFBundleIdentifier': 'org.zerok.macos', 'CFBundleName': 'Zero-K',
        'CFBundleDisplayName': 'Zero-K', 'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version,
        'CFBundleVersion': os.environ.get('ZKMACOS_BUILD_NUMBER', '1'),
        'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True,
        'LSApplicationCategoryType': 'public.app-category.strategy-games', 'LSSupportsGameMode': True,
        'NSPrefersDisplaySafeAreaCompatibilityMode': False,
        'LSArchitecturePriority': ['arm64'], 'LSUIElement': True, 'CFBundleIconFile': 'Zero-K.icns',
        'NSHumanReadableCopyright': 'Zero-K contributors; see Resources/licenses'}
if public_key:
    info.update({'SUFeedURL': 'https://github.com/smallketchup82/ZkMacOS/releases/latest/download/appcast.xml',
                 'SUPublicEDKey': public_key, 'SUEnableAutomaticChecks': True,
                 'SUAutomaticallyUpdate': False, 'SUVerifyUpdateBeforeExtraction': True,
                 'SURequireSignedFeed': True})
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
for source, name in ((root / 'LICENSE', 'ZkMacOS-GPL.txt'),
                    (engine_source / 'LICENSE.html', 'Recoil-GPL.html'),
                    (root / 'external/infrastructure/LICENSE', 'Launcher-GPL.txt'),
                    (root / '.cache/steamworks-2025.164.1/LICENSE.txt', 'Steamworks.NET-MIT.txt'),
                    (engine_source / 'cont/fonts/COPYING', 'FreeSans-license.txt')):
    copy(source, resources / 'licenses' / name)
copy(root / 'docs/THIRD-PARTY.md', resources / 'licenses/THIRD-PARTY.md')
with tarfile.open(root / '.cache/mesa-26.3.0-rc1.tar.xz') as archive:
    for member in archive.getmembers():
        parts = Path(member.name).parts[1:]
        if member.isfile() and (parts[:1] == ('licenses',) or parts == ('docs', 'license.rst')):
            target = resources / 'licenses/Mesa' / Path(*parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.extractfile(member).read())
dotnet = Path(shutil.which('dotnet')).resolve().parent
for name in ('LICENSE.txt', 'ThirdPartyNotices.txt'):
    copy(dotnet / name, resources / 'licenses' / ('dotnet-' + name))
copy(root / 'sources.lock.json', resources / 'sources.lock.json')
copy(root / 'assets.lock.json', resources / 'assets.lock.json')
inventory = []
for target, source in sorted(native_files.items()):
    inventory.append({'path': str(target.relative_to(stage)), 'file': source.name,
                      'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    try:
        parts = source.relative_to('/opt/homebrew/Cellar').parts
    except ValueError:
        continue
    keg = Path('/opt/homebrew/Cellar') / parts[0] / parts[1]
    inventory[-1].update({'package': parts[0], 'version': parts[1]})
    notices = list(keg.glob('COPYING*')) + list(keg.glob('LICENSE*')) + list(keg.glob('NOTICE*'))
    notices += list((keg / 'share/doc').glob('**/COPYING*')) + list((keg / 'share/doc').glob('**/LICENSE*'))
    for notice in notices:
        if notice.is_file():
            copy(notice, resources / 'licenses/native' / parts[0] / notice.name)
packages = list((build / 'nuget').rglob('*.nupkg'))
packages += list((Path.home() / '.nuget/packages/newtonsoft.json/13.0.3').glob('*.nupkg'))
for package in packages:
    with ZipFile(package) as archive:
        for name in archive.namelist():
            if Path(name).name.lower().startswith(('license', 'licence', 'notice', 'copying')):
                if name.endswith('/'):
                    continue
                target = resources / 'licenses/nuget' / package.stem / Path(name).name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
(resources / 'native-dependencies.json').write_text(json.dumps(inventory, indent=2) + '\n')
copy(build / 'client-build.json', resources / 'client-build.json')
subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(stage)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
target = dist / 'Zero-K.app'
if target.exists():
    shutil.rmtree(target)
stage.rename(target)
shutil.rmtree(stage.parent)
print(f'Built {target}; bundled {len(native_files)} native binaries.')

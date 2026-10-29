#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography==46.0.3", "rich==14.2.0"]
# ///
"""Build locally, sign and audit the DMG, then open an unpublished GitHub draft."""
from pathlib import Path
from datetime import datetime
import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from build_progress import BuildProgress, ROOT, open_iterm

REPOSITORY = 'smallketchup82/ZkMacOS'
ASSET = 'Zero-K-macOS-arm64.dmg'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


def github(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))


def check_key(private_key, public_key):
    try:
        seed = base64.b64decode(private_key.strip(), validate=True)
        expected = base64.b64decode(public_key.strip(), validate=True)
        actual = Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    except (ValueError, TypeError):
        raise ValueError('Invalid Sparkle key encoding; use the seed exported by generate_keys.') from None
    if actual != expected:
        raise ValueError('Private-key backup does not match SPARKLE_PUBLIC_ED_KEY. Reuse the production signing key.')


def check_source(path, revision, *, allow_uninitialized=False):
    """A release uses clean fork commits and exactly their recorded submodules."""
    actual = subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != revision:
        raise ValueError(f'{path}: checkout is not at its release pin.')
    changes = subprocess.check_output(['git', '-C', str(path), 'status', '--porcelain',
                                       '--untracked-files=all', '--ignore-submodules=none'], text=True).strip()
    if changes:
        raise ValueError(f'{path}: uncommitted source or submodule changes:\n' + changes)
    modules = subprocess.check_output(['git', '-C', str(path), 'submodule', 'status', '--recursive'], text=True)
    for line in modules.splitlines():
        if line.startswith(('+', 'U')) or (line.startswith('-') and not allow_uninitialized):
            raise ValueError(f'{path}: submodule does not match its committed revision: ' + line)


def check_sources(*, allow_missing=False):
    pins = json.loads((ROOT / 'sources.lock.json').read_text())
    for name, item in pins.items():
        path = ROOT / 'external' / name
        if allow_missing and not (path / '.git').exists():
            continue
        check_source(path, item['revision'], allow_uninitialized=allow_missing)


def preflight(args):
    for tool in ('gh', 'uv', 'brew', 'cmake', 'ninja', 'dotnet', 'luajit', 'swiftc', 'hdiutil'):
        if not shutil.which(tool):
            raise ValueError(f'Missing {tool}; install the build dependencies from Brewfile.')
    authentication = subprocess.run(['gh', 'auth', 'status', '--active', '--hostname', 'github.com'], capture_output=True)
    if authentication.returncode:
        raise ValueError('GitHub CLI is not authenticated. Run gh auth login, then retry.')
    if subprocess.check_output(['uname', '-m'], text=True).strip() != 'arm64' or sys.platform != 'darwin':
        raise ValueError('Local releases require an Apple Silicon Mac.')
    if subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip() != 'main':
        raise ValueError('Switch to main before creating a release.')
    if subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip():
        raise ValueError('Commit and push the working-tree changes before creating a release.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    remote = github(f'repos/{REPOSITORY}/commits/main')['sha']
    if commit != remote:
        raise ValueError('Local main must match GitHub main. Push or pull before releasing.')
    if args.notes_file and not args.notes_file.is_file():
        raise ValueError('Release notes file does not exist: ' + str(args.notes_file))
    public_key = os.environ.get('SPARKLE_PUBLIC_ED_KEY') or subprocess.check_output(
        ['gh', 'variable', 'get', 'SPARKLE_PUBLIC_ED_KEY', '--repo', REPOSITORY], text=True).strip()
    private_key = os.environ.get('SPARKLE_PRIVATE_ED_KEY') or args.private_key_file.expanduser().read_text().strip()
    check_key(private_key, public_key)
    tag = subprocess.check_output([sys.executable, ROOT / 'scripts/next-release-version.py', '--repository', REPOSITORY], text=True).strip()
    releases = json.loads(subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
                         f'repos/{REPOSITORY}/releases?per_page=100'], text=True))
    # Count drafts too: two prepared releases must never share an updater build number.
    build_number = 0
    for release in (release for page in releases for release in page):
        feed = next((asset for asset in release['assets'] if asset['name'] == 'appcast.xml'), None)
        if feed:
            xml = subprocess.check_output(['gh', 'api', '-H', 'Accept: application/octet-stream',
                                          f'repos/{REPOSITORY}/releases/assets/{feed["id"]}'])
            version = ET.fromstring(xml).findtext('channel/item/{' + SPARKLE + '}version')
            if not version or not version.isdecimal():
                raise ValueError('Published appcast has an unsupported build number; inspect it before releasing.')
            build_number = max(build_number, int(version))
    check_sources(allow_missing=True)
    return commit, tag, str(build_number + 1), public_key, private_key


def run_checks(display):
    for path in sorted((ROOT / 'tests').glob('check-*.lua')):
        display.run(['luajit', path])
    for name in ('check-cask.py', 'check-release-version.py', 'check-fullscreen.py', 'check-local-release.py'):
        display.run([sys.executable, ROOT / 'tests' / name])
    display.run(['uv', 'run', '--no-project', '--python', 'python3', '--with', 'cryptography==46.0.3',
                 '--with', 'rich==14.2.0', 'python', 'tests/check-appcast.py'])
    display.run(['swiftc', '-D', 'UPDATE_CHECK_TESTS', '-framework', 'AppKit', '-F', '.cache/sparkle-2.10.1',
                 '-framework', 'Sparkle', '-Xlinker', '-rpath', '-Xlinker', str(ROOT / '.cache/sparkle-2.10.1'),
                 'app/main.swift', 'tests/check-updates.swift', '-o', 'build/check-updates'])
    display.run(['build/check-updates'])


def verify_dmg(display, tag, build_number):
    dist = ROOT / 'dist'
    digest, filename = (dist / (ASSET + '.sha256')).read_text().split()
    with (dist / ASSET).open('rb') as stream:
        if filename != ASSET or hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
            raise ValueError('DMG checksum verification failed.')
    with tempfile.TemporaryDirectory(prefix='zk-release-dmg-') as folder:
        mount = Path(folder) / 'mounted'
        mount.mkdir()
        display.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, dist / ASSET])
        try:
            info = plistlib.loads((mount / 'Zero-K.app/Contents/Info.plist').read_bytes())
            if info['CFBundleShortVersionString'] != tag or info['CFBundleVersion'] != build_number or not info.get('SUPublicEDKey'):
                raise ValueError('Mounted DMG version or updater configuration does not match this release.')
            if not (mount / 'Applications').is_symlink():
                raise ValueError('DMG is missing the Applications shortcut.')
            display.run([sys.executable, ROOT / 'scripts/audit-app.py', mount / 'Zero-K.app'])
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)


def create_draft(display, tag, commit, notes_file):
    assets = [ROOT / 'dist' / name for name in (ASSET, ASSET + '.sha256', 'appcast.xml',
              'sources.lock.json', 'assets.lock.json', 'native-dependencies.json', 'client-build.json', 'app-audit.json', 'release-build.json')]
    display.run(['gh', 'release', 'create', tag, '--repo', REPOSITORY, '--target', commit,
                 '--title', tag, '--draft', '--generate-notes', '--notes-file', notes_file, *assets])
    release = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', REPOSITORY,
                                                '--json', 'isDraft,assets,url'], text=True))
    if not release['isDraft']:
        raise ValueError('Expected an unpublished draft release.')
    expected = {asset.name for asset in assets}
    if not expected.issubset({asset['name'] for asset in release['assets']}):
        raise ValueError('Draft exists but some uploads are missing. Inspect it before publishing.')
    return release['url'].replace('/releases/tag/', '/releases/edit/', 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes-file', type=Path, help='Prepend custom Markdown to generated release notes.')
    parser.add_argument('--private-key-file', type=Path,
                        default=Path(os.environ.get('SPARKLE_PRIVATE_KEY_FILE', '~/.config/zkmacos/sparkle-private-key')),
                        help='Sparkle private seed backup; defaults to ~/.config/zkmacos/sparkle-private-key.')
    parser.add_argument('--check', action='store_true', help='Check signing keys, source pins and release metadata; do not build or upload.')
    parser.add_argument('--prepare-only', action='store_true', help='Build and sign artifacts without creating a GitHub draft.')
    parser.add_argument('--no-open', action='store_true', help='Print the draft editing URL without opening the browser.')
    parser.add_argument('--iterm', action='store_true', help='Run in a new, visible iTerm window.')
    parser.add_argument('--plain', action='store_true', help='Print ordinary output without animations.')
    parser.add_argument('--verbose', action='store_true', help='Show all build output alongside progress.')
    args = parser.parse_args()
    if args.notes_file:
        args.notes_file = args.notes_file.resolve()
    args.private_key_file = args.private_key_file.expanduser().resolve()
    os.chdir(ROOT)
    os.environ['UV_CACHE_DIR'] = str(ROOT / 'build/uv-cache')
    if args.iterm:
        arguments = [arg for arg in sys.argv[1:] if arg != '--iterm']
        for option, value in (('--notes-file', args.notes_file), ('--private-key-file', args.private_key_file)):
            if value is not None and option in arguments:
                arguments[arguments.index(option) + 1] = str(value)
            arguments = [option + '=' + str(value) if arg.startswith(option + '=') else arg for arg in arguments]
        open_iterm(['uv', 'run', '--python', 'python3', ROOT / 'scripts/create-release.py', *arguments])
        return
    with BuildProgress('Prepare a local Zero-K release', 'release', 1 if args.check else 7,
                       plain=args.plain, verbose=args.verbose) as display:
        display.step(1, 'Check GitHub, source pins and the production signing key')
        commit, tag, build_number, public_key, private_key = preflight(args)
        display.console.print(f'Release: {tag}  •  Sparkle build: {build_number}  •  Source: {commit[:12]}', markup=False)
        if args.check:
            display.console.print('Preflight passed. Nothing built, uploaded or published.', markup=False)
            return
        environment = {'ZKMACOS_VERSION': tag, 'ZKMACOS_BUILD_NUMBER': build_number,
                       'SPARKLE_PUBLIC_ED_KEY': public_key, 'ZKMACOS_BUILD_RAW': '1'}
        display.step(2, 'Build and audit the app using local caches')
        display.run(['bash', 'scripts/build-app.sh'], env=environment)
        display.step(3, 'Run settings, updater and release checks')
        run_checks(display)
        display.step(4, 'Create the styled disk image')
        display.run(['bash', 'scripts/build-dmg.sh'], env={'CI': 'true'})
        display.step(5, 'Sign the update and verify the mounted disk image')
        # The private key is used only here and never passed as a command argument.
        signer = runpy.run_path(str(ROOT / 'scripts/generate-appcast.py'))['generate_appcast']
        signer(ROOT / 'dist', ROOT / '.cache/sparkle-2.10.1/bin/sign_update', private_key, REPOSITORY)
        verify_dmg(display, tag, build_number)
        display.step(6, 'Record source and dependency metadata')
        for name in ('sources.lock.json', 'assets.lock.json'):
            shutil.copy2(ROOT / name, ROOT / 'dist' / name)
        for name in ('native-dependencies.json', 'client-build.json'):
            shutil.copy2(ROOT / 'dist/Zero-K.app/Contents/Resources' / name, ROOT / 'dist' / name)
        shutil.copy2(ROOT / 'build/logs/app-audit.json', ROOT / 'dist/app-audit.json')
        (ROOT / 'dist/release-build.json').write_text(json.dumps({
            'version': tag, 'build_number': build_number, 'commit': commit,
            'built_at': datetime.now().astimezone().isoformat(), 'builder': 'local',
        }, indent=2) + '\n')
        # Recheck before uploading: the draft must describe the code that was built.
        if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != commit or subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip():
            raise ValueError('Source changed during the build. Artifacts retained; no release uploaded.')
        check_sources()
        display.step(7, 'Finish local artifacts' if args.prepare_only else 'Create the GitHub draft and open its editor')
        if args.prepare_only:
            display.console.print('Signed artifacts are ready in dist/. No release created.', markup=False)
            return
        notes_file = args.notes_file or ROOT / 'build/release-notes.md'
        if not args.notes_file:
            notes_file.write_text('Unofficial, experimental Zero-K client for Apple Silicon Macs running macOS 26 or newer.\n\n'
                                  'Download the DMG and drag `Zero-K.app` into `Applications`; see the README for installation instructions.\n\n'
                                  f'Source commit: {commit}\n')
        url = create_draft(display, tag, commit, notes_file)
        display.console.print('Draft editor: ' + url, markup=False)
        display.console.print('Edit the description, then publish a stable release marked Latest to enable Sparkle and Homebrew updates.', markup=False)
        if not args.no_open:
            subprocess.run(['open', url], check=False)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError, KeyboardInterrupt) as error:
        print('Release stopped: ' + ('cancelled' if isinstance(error, KeyboardInterrupt) else str(error)), file=sys.stderr)
        sys.exit(1)

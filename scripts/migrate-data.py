"""Import existing user data without putting it into a distribution build."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--workspace', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--destination', type=Path, default=Path.home() / 'Library/Application Support/Zero-K')
args = parser.parse_args()
root, destination = args.workspace.resolve(), args.destination.resolve()
os.umask(0o077)
destination.mkdir(parents=True, exist_ok=True)
manifest = {}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def copy_file(source, target, preserve_conflict=False):
    checksum = digest(source)
    if target.exists():
        existing = digest(target)
        if existing == checksum:
            manifest[str(target.relative_to(destination))] = checksum
            return
        if preserve_conflict:
            backup = destination / 'migration-backup/portable' / target.relative_to(destination)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
            manifest[str(backup.relative_to(destination))] = existing
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    target.chmod(0o600)
    manifest[str(target.relative_to(destination))] = checksum


folders = ('games', 'maps', 'packages', 'pool', 'rapid', 'missions', 'CustomModes',
           'Saves', 'demos', 'chatLogs', 'log', 'news', 'MenuLoadscreens', 'LuaUI',
           'LuaMenu', 'benchmarks', 'cache', 'fontcache')
for name in ('zero-k-portable', 'native-data'):
    source = root / name
    if not source.is_dir():
        continue
    for folder in folders:
        directory = source / folder
        if not directory.is_dir():
            continue
        for file in directory.rglob('*'):
            if file.is_file() and file.name != '.DS_Store':
                copy_file(file, destination / folder / file.relative_to(directory), name == 'native-data')
    for file in ('springsettings.cfg', 'lups.cfg', 'cmdcolors.txt', 'chobby_config.json'):
        if (source / file).is_file():
            copy_file(source / file, destination / file, name == 'native-data')
    # Retain old AI tuning as private data, excluding obsolete foreign binaries.
    for file in (source / 'AI').rglob('*') if (source / 'AI').exists() else ():
        if file.is_file() and not file.is_symlink() and file.suffix.lower() in ('.json', '.lua', '.as', '.txt'):
            copy_file(file, destination / 'migration-backup' / name / file.relative_to(source))

for relative, checksum in manifest.items():
    if digest(destination / relative) != checksum:
        raise RuntimeError(f'Migration verification failed: {relative}')
report = {'destination': str(destination), 'verified_files': len(manifest), 'sha256': manifest}
(root / '.local').mkdir(exist_ok=True)
(root / '.local/migration-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'Copied and SHA-256 verified {len(manifest)} user-data files into {destination}.')
print('Distribution inputs are separate; no personal data is copied into the application.')

"""Download public build inputs only, verifying every pinned checksum."""
from pathlib import Path
import hashlib
import json
import tarfile
import urllib.request
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
cache = root / '.cache'
cache.mkdir(exist_ok=True)
for item in json.loads((root / 'assets.lock.json').read_text()).values():
    archive = cache / item['file']
    if not archive.exists():
        with urllib.request.urlopen(item['url'], timeout=120) as response, archive.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        raise RuntimeError(f'Checksum mismatch: {archive}')
    if not item['extract']:
        continue
    destination = cache / item['extract']
    if destination.exists():
        continue
    destination.mkdir()
    if item['kind'] == 'zip':
        with ZipFile(archive) as source:
            for name in source.namelist():
                if not (destination / name).resolve().is_relative_to(destination):
                    raise RuntimeError('Archive contains an escaping path')
            source.extractall(destination)
    else:
        with tarfile.open(archive) as source:
            for entry in source.getmembers():
                if item['kind'] == 'tar-root':
                    source.extract(entry, destination, filter='data')
                    continue
                parts = Path(entry.name).parts
                if len(parts) < 2:
                    continue
                entry.name = str(Path(*parts[1:]))
                source.extract(entry, destination, filter='data')
    print('Prepared', item['extract'])

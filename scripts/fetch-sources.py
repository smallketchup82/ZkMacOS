"""Check out commit-pinned forks and their committed submodule revisions."""
from pathlib import Path
import json
import subprocess


def prepare_source(destination, item):
    if not (destination / '.git').exists():
        subprocess.run(['git', 'clone', '--filter=blob:none', item['url'], str(destination)], check=True)
        subprocess.run(['git', '-C', str(destination), 'checkout', item['revision']], check=True)
    actual = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != item['revision']:
        print(f'{destination.name}: using local revision {actual}; release pin is {item["revision"]}')
    if (destination / '.gitmodules').exists():
        # Fork commits may change a submodule's remote as well as its gitlink.
        subprocess.run(['git', '-C', str(destination), 'submodule', 'sync', '--recursive'], check=True)
        subprocess.run(['git', '-C', str(destination), 'submodule', 'update', '--init', '--recursive'], check=True)


def main():
    root = Path(__file__).resolve().parents[1]
    sources = json.loads((root / 'sources.lock.json').read_text())
    (root / 'external').mkdir(exist_ok=True)
    for name, item in sources.items():
        prepare_source(root / 'external' / name, item)
    print('Source checkouts ready; existing local work was preserved.')


if __name__ == '__main__':
    main()

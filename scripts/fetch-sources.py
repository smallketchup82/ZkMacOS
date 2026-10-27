"""Check out pinned forks and apply the version-specific CircuitAI fix."""
from pathlib import Path
import json
import hashlib
import subprocess

root = Path(__file__).resolve().parents[1]
sources = json.loads((root / 'sources.lock.json').read_text())
(root / 'external').mkdir(exist_ok=True)
for name, item in sources.items():
    destination = root / 'external' / name
    if not (destination / '.git').exists():
        subprocess.run(['git', 'clone', '--filter=blob:none', item['url'], str(destination)], check=True)
        subprocess.run(['git', '-C', str(destination), 'checkout', item['revision']], check=True)
    actual = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != item['revision']:
        print(f'{name}: using local revision {actual}; release pin is {item["revision"]}')
    if (destination / '.gitmodules').exists():
        subprocess.run(['git', '-C', str(destination), 'submodule', 'update', '--init', '--recursive'], check=True)

circuit = root / 'external/recoil/AI/Skirmish/CircuitAI'
patch = root / 'patches/circuitai-apple-arm64.patch'
if hashlib.sha256(patch.read_bytes()).hexdigest() != sources['recoil']['circuitai_patch_sha256']:
    raise RuntimeError('CircuitAI patch differs from the lock file')
reverse = subprocess.run(['git', '-C', str(circuit), 'apply', '--reverse', '--check', str(patch)], capture_output=True)
if reverse.returncode:
    subprocess.run(['git', '-C', str(circuit), 'apply', '--check', str(patch)], check=True)
    subprocess.run(['git', '-C', str(circuit), 'apply', '--whitespace=nowarn', str(patch)], check=True)
print('Source checkouts ready; existing local work was preserved.')

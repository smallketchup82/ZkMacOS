"""Check out pinned forks and apply checksum-verified source patches."""
from pathlib import Path
import json
import hashlib
import subprocess
import shutil
import tempfile

def patch_stack_is_applied(destination, patches):
    # Later patches can change the context of earlier ones. Reverse the stack
    # on disposable file copies, never on a developer's working checkout.
    with tempfile.TemporaryDirectory(prefix='zk-source-patches-') as folder:
        folder = Path(folder)
        for patch in patches:
            stats = subprocess.check_output(['git', 'apply', '--numstat', str(patch)], text=True)
            for line in stats.splitlines():
                name = line.split('\t', 2)[2]
                source = destination / name
                if source.is_file():
                    target = folder / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
        for patch in reversed(patches):
            result = subprocess.run(['git', 'apply', '--reverse', str(patch)], cwd=folder, capture_output=True)
            if result.returncode:
                return False
    return True


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
    patches = [root / 'patches' / filename for filename in item.get('patches', {})]
    for patch, expected_hash in zip(patches, item.get('patches', {}).values()):
        if hashlib.sha256(patch.read_bytes()).hexdigest() != expected_hash:
            raise RuntimeError(f'{patch.name} differs from the lock file')
    if patch_stack_is_applied(destination, patches):
        continue
    for patch in patches:
        reverse = subprocess.run(['git', '-C', str(destination), 'apply', '--reverse', '--check', str(patch)], capture_output=True)
        if reverse.returncode:
            subprocess.run(['git', '-C', str(destination), 'apply', '--check', str(patch)], check=True)
            subprocess.run(['git', '-C', str(destination), 'apply', '--whitespace=nowarn', str(patch)], check=True)

circuit = root / 'external/recoil/AI/Skirmish/CircuitAI'
patch = root / 'patches/circuitai-apple-arm64.patch'
if hashlib.sha256(patch.read_bytes()).hexdigest() != sources['recoil']['circuitai_patch_sha256']:
    raise RuntimeError('CircuitAI patch differs from the lock file')
reverse = subprocess.run(['git', '-C', str(circuit), 'apply', '--reverse', '--check', str(patch)], capture_output=True)
if reverse.returncode:
    subprocess.run(['git', '-C', str(circuit), 'apply', '--check', str(patch)], check=True)
    subprocess.run(['git', '-C', str(circuit), 'apply', '--whitespace=nowarn', str(patch)], check=True)
print('Source checkouts ready; existing local work was preserved.')

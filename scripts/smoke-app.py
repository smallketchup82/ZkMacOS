"""Build, relocate and run the app, bounding engine unified memory and runtime."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, default=90)
parser.add_argument('--script', type=Path, default=root / 'tests/novice-skirmish.tdf')
args = parser.parse_args()
subprocess.run([str(root / 'scripts/build-app.sh')], cwd=root, check=True)
source = root / 'dist/Zero-K.app'
test_root = root / '.local/relocation-test'
app = test_root / 'Moved App/Zero-K.app'
data = test_root / 'data'
if app.exists():
    shutil.rmtree(app)
app.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(source, app)
data.mkdir(parents=True, exist_ok=True)
user_data = Path.home() / 'Library/Application Support/Zero-K'
for folder in ('games', 'maps', 'packages', 'pool', 'rapid'):
    target = data / folder
    if not target.exists() and (user_data / folder).exists():
        target.symlink_to(user_data / folder, target_is_directory=True)


def snapshot(directory):
    return {str(file.relative_to(directory)): hashlib.sha256(file.read_bytes()).hexdigest()
            for file in directory.rglob('*') if file.is_file()}


before = snapshot(app)
environment = os.environ.copy()
for key in list(environment):
    if key.startswith(('MONO_', 'DOTNET_', 'DYLD_', 'SPRING_', 'VK_', 'MESA_')):
        del environment[key]
environment['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
environment['ZKMACOS_DATA_DIR'] = str(data)
environment['DYLD_PRINT_LIBRARIES'] = '1'
process = subprocess.Popen([str(app / 'Contents/MacOS/Zero-K'), '--engine', str(args.script.resolve())],
                           env=environment, start_new_session=True)
started = time.monotonic()
peak = 0
reason = 'engine exited'
try:
    while process.poll() is None:
        if time.monotonic() - started >= args.seconds:
            reason = 'time limit'
            break
        rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='], text=True).splitlines()
        for row in rows:
            fields = row.strip().split(None, 2)
            if len(fields) != 3 or fields[1] != str(process.pid) or not fields[2].endswith('/spring'):
                continue
            sample = subprocess.run(['footprint', '-p', fields[0]], capture_output=True, text=True, timeout=5)
            match = re.search(r'phys_footprint:\s*([\d.]+)\s*(GB|MB|KB|B)', sample.stdout)
            if match:
                footprint = float(match[1]) * {'GB': 1024**3, 'MB': 1024**2, 'KB': 1024, 'B': 1}[match[2]]
                peak = max(peak, footprint)
                if footprint > 8 * 1024**3:
                    reason = 'memory limit'
                    raise RuntimeError('Engine exceeded the 8 GiB unified-memory limit')
        time.sleep(1)
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()

after = snapshot(app)
if before != after:
    raise RuntimeError('The application wrote into its own bundle')
log = (data / 'infolog.txt').read_text(errors='replace')
loader_log = (data / 'log/engine-launch.log').read_text(errors='replace')
outside = []
for line in loader_log.splitlines():
    if not line.startswith('dyld['):
        continue
    match = re.search(r'(/.+)$', line)
    if match and match[1].startswith(('/opt/homebrew/', '/Library/Frameworks/Mono.framework/', '/usr/local/share/dotnet/')):
        outside.append(match[1])
if outside:
    raise RuntimeError('Loaded developer-machine dependencies: ' + ', '.join(outside))
report = {'reason': reason, 'exit_code': process.returncode, 'peak_footprint_mib': round(peak / 1024**2),
          'bundle_unchanged': True, 'host_dependencies': outside, 'ai_initialized': 'Initialized!' in log,
          'vsync_enabled': 'interval=1 (Mesa EGL bridge)' in log}
(test_root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
if not report['vsync_enabled'] or ('novice' in args.script.name and not report['ai_initialized']):
    raise SystemExit('The expected renderer or AI did not initialize')

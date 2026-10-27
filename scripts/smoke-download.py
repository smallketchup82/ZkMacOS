"""After build-app.sh, test a real map download through the packaged helper."""
from pathlib import Path
import argparse
import json
import os
import signal
import socket
import subprocess
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--map', default='The Halite Maze v1.3')
parser.add_argument('--seconds', type=int, default=120)
args = parser.parse_args()
app = root / 'dist/Zero-K.app/Contents'
data = root / '.local/download-test'
os.umask(0o077)
data.mkdir(parents=True, exist_ok=True)

# Exercise the real helper without opening a game window or using player data.
engine = data / 'hold-engine.sh'
engine.write_text('#!/bin/sh\nexec /bin/sleep 180\n')
engine.chmod(0o700)
environment = os.environ.copy()
environment.update(ZEROK_DATA_DIR=str(data), ZEROK_ENGINE_PATH=str(engine),
                   ZEROK_RESOURCE_DIR=str(app / 'Resources/data'), ZEROK_CHOBBY_NAME='Chobby macos-source',
                   SteamAppId='334920', SteamGameId='334920')
port_file = data / 'chobby_wrapper_port.txt'
port_file.unlink(missing_ok=True)

with (data / 'helper.log').open('w') as output:
    process = subprocess.Popen([str(app / 'Resources/client/Zero-K-Helper')], env=environment,
                               stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        deadline = time.monotonic() + 25
        while not port_file.exists():
            if process.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('The helper did not open its local protocol')
            time.sleep(0.1)

        result = None
        with socket.create_connection(('127.0.0.1', int(port_file.read_text()))) as connection:
            connection.settimeout(1)
            request = 'DownloadFile ' + json.dumps({'FileType': 'MAP', 'Name': args.map}) + '\n'
            connection.sendall(request.encode())
            buffer = b''
            deadline = time.monotonic() + args.seconds
            while time.monotonic() < deadline and result is None:
                try:
                    incoming = connection.recv(65536)
                except socket.timeout:
                    continue
                if not incoming:
                    raise RuntimeError('The helper disconnected during the download')
                buffer += incoming
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if line.startswith(b'DownloadFileDone '):
                        result = json.loads(line.split(b' ', 1)[1])
                        break

        report = {'result': result, 'maps': [{'name': file.name, 'bytes': file.stat().st_size}
                  for file in (data / 'maps').glob('*') if file.is_file()]}
        (data / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        if not result or not result.get('IsSuccess'):
            raise RuntimeError('The map download did not complete')
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=10)

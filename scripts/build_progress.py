# /// script
# requires-python = ">=3.11"
# dependencies = ["rich==14.2.0"]
# ///
"""Shared terminal display and command logging for local builds and releases."""
from collections import deque
from pathlib import Path
import argparse
import fcntl
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time

from rich.console import Console
from rich.panel import Panel
from rich.progress import BarColumn, Progress, SpinnerColumn, TextColumn, TimeElapsedColumn
from rich.text import Text
from rich.table import Column

ROOT = Path(__file__).resolve().parents[1]


def open_iterm(command):
    """Open a separate shell; never type into an existing interactive session."""
    if not Path('/Applications/iTerm.app').exists():
        raise RuntimeError('iTerm is not installed. Run again without --iterm in your terminal.')
    script = '''on run argv
        tell application "iTerm"
            activate
            set buildWindow to (create window with default profile)
            tell current session of buildWindow to write text (item 1 of argv)
        end tell
    end run'''
    shell_command = 'cd ' + shlex.quote(str(ROOT)) + ' && ' + shlex.join(map(str, command))
    subprocess.run(['osascript', '-', shell_command], input=script, text=True, check=True)
    print('Opened a new iTerm window. Logs: ' + str(ROOT / 'build/logs'))


class BuildProgress:
    """One display owns the step summary, live command progress, and full log."""
    def __init__(self, title, name, steps, *, plain=False, verbose=False):
        self.title, self.name, self.steps = title, name, steps
        self.console = Console(highlight=False)
        self.interactive = self.console.is_terminal and not plain
        self.verbose = verbose
        self.directory = ROOT / 'build/logs'
        self.directory.mkdir(parents=True, exist_ok=True)
        self.log_path = self.directory / (name + '.log')
        self.result_path = self.directory / (name + '-result.json')
        self.progress = Progress(SpinnerColumn(), TextColumn('{task.description}', table_column=Column(max_width=32, no_wrap=True)), BarColumn(bar_width=None),
                                 TextColumn('{task.fields[percentage]}'), TextColumn('{task.fields[count]}'), TimeElapsedColumn(), console=self.console,
                                 disable=not self.interactive, transient=True)
        self.overall = self.progress.add_task('Stages', total=steps, count='', percentage='0%')
        self.current = self.progress.add_task('Starting', total=None, count='', percentage='')
        self.engine = self.progress.add_task('Engine compilation', total=None, count='', percentage='', visible=False)
        self.compiling_engine = False
        self.index = 0
        self.step_title = ''
        self.tail = deque(maxlen=25)

    def __enter__(self):
        self.started = self.step_started = time.monotonic()
        self.lock = (ROOT / 'build/.pipeline.lock').open('a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise RuntimeError('Another build or release is using this checkout. Wait for it to finish.') from None
        self.log = self.log_path.open('w', buffering=1)
        self.result_path.write_text(json.dumps({'status': 'running', 'pid': os.getpid()}) + '\n')
        self.console.print(Panel(Text(self.title + '\n' + str(ROOT) + '\nLogs: ' + str(self.log_path)),
                                 border_style='cyan'))
        self.progress.start()
        return self

    def step(self, index, title):
        now = time.monotonic()
        if self.step_title:
            self.console.print(f'  ✓ {self.step_title}  ({now - self.step_started:.1f}s)', style='green', markup=False)
        self.index, self.step_title, self.step_started = index, title, now
        self.progress.update(self.overall, completed=index - 1, description=f'Stages {index}/{self.steps}', percentage=f'{(index - 1) * 100 / self.steps:.0f}%')
        self.progress.reset(self.current, total=None, description=title[:85], count='', percentage='')
        line = f'[{index}/{self.steps}] {title}'
        self.log.write(line + '\n')
        self.console.print(line, style='bold cyan', markup=False)

    def run(self, command, *, env=None, input=None, build_steps=False, capture=False):
        """Stream tool output to disk; Ninja supplies real counts, other tools pulse."""
        environment = os.environ.copy()
        environment.update(env or {})
        environment.pop('SPARKLE_PRIVATE_ED_KEY', None)
        environment['NINJA_STATUS'] = '[%f/%t] '
        output = []
        self.tail.clear()
        with subprocess.Popen(list(map(str, command)), cwd=ROOT, env=environment,
                              stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors='replace', bufsize=1, start_new_session=True) as process:
            try:
                if input is not None:
                    process.stdin.write(input)
                    process.stdin.close()
                for line in process.stdout:
                    if line.startswith('::zk-step::'):
                        index, total, title = line.rstrip().split('::zk-step::', 1)[1].split('|', 2)
                        self.compiling_engine = int(index) == 5
                        if self.compiling_engine:
                            self.progress.reset(self.engine, total=None, completed=0, description='Engine compilation', count='', percentage='', visible=True)
                        if build_steps:
                            self.step(int(index), title)
                        else:
                            self.progress.reset(self.current, total=None, description=f'Build {index}/{total}: {title}'[:85], count='', percentage='')
                            self.log.write(line)
                            self.console.print(f'    Build {index}/{total}: {title}', markup=False)
                        continue
                    self.log.write(line)
                    self.tail.append(line.rstrip())
                    if capture:
                        output.append(line)
                    match = re.match(r'\[(\d+)/(\d+)\] ', line)
                    if match:
                        task = self.engine if self.compiling_engine else self.current
                        self.progress.update(task, completed=int(match[1]), total=int(match[2]),
                                             count=f'{match[1]} / {match[2]} tasks',
                                             percentage=f'{int(match[1]) * 100 / int(match[2]):.0f}%' if int(match[2]) else 'done')
                        self.progress.update(self.current, description=line[match.end():].strip()[-85:])
                    elif self.compiling_engine and 'ninja: no work to do.' in line:
                        self.progress.update(self.engine, completed=0, total=0, count='0 / 0 tasks', percentage='cached')
                    elif line.strip():
                        self.progress.update(self.current, description=line.strip()[-85:])
                    if self.verbose or not self.interactive:
                        self.console.print(line, end='', markup=False, highlight=False)
                code = process.wait()
            except BaseException:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                raise
        if code:
            if self.interactive and not self.verbose:
                self.console.print(Text('\n'.join(self.tail)), style='red')
            raise RuntimeError(f'{Path(command[0]).name} failed (exit {code}). Full log: {self.log_path}')
        return ''.join(output)

    def __exit__(self, kind, error, traceback):
        duration = time.monotonic() - self.started
        if error is None:
            self.progress.update(self.overall, completed=self.steps, percentage='100%')
        self.progress.stop()
        self.log.close()
        self.lock.close()
        self.result_path.write_text(json.dumps({'status': 'failed' if error else 'success',
                                               'seconds': round(duration, 1), 'step': self.step_title}) + '\n')
        if error:
            self.console.print(Text(f'Stopped at {self.step_title or "startup"}: {error}'), style='bold red')
        else:
            self.console.print(f'✓ {self.title} complete in {duration:.1f}s', style='bold green', markup=False)
        self.console.print('Full log: ' + str(self.log_path), markup=False)


def main():
    parser = argparse.ArgumentParser(description='Build the app with live progress and full logs.')
    parser.add_argument('--iterm', action='store_true', help='Run in a new, visible iTerm window.')
    parser.add_argument('--plain', action='store_true', help='Print ordinary output without animations.')
    parser.add_argument('--verbose', action='store_true', help='Show all compiler output alongside progress.')
    args = parser.parse_args()
    if args.iterm:
        open_iterm([ROOT / 'scripts/build-app.sh', *[arg for arg in sys.argv[1:] if arg != '--iterm']])
        return
    with BuildProgress('Build Zero-K for macOS', 'build', 9, plain=args.plain, verbose=args.verbose) as display:
        display.run(['bash', ROOT / 'scripts/build-app.sh'], env={'ZKMACOS_BUILD_RAW': '1'}, build_steps=True)
        display.console.print('App: ' + str(ROOT / 'dist/Zero-K.app'), markup=False)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, KeyboardInterrupt) as error:
        if isinstance(error, KeyboardInterrupt):
            print('Cancelled.', file=sys.stderr)
        else:
            print(str(error), file=sys.stderr)
        sys.exit(1)

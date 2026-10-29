"""Run isolated, fixed-camera rendering and presentation comparisons on this Mac.

Usage: uv run tests/benchmark-metalfx.py --app /path/to/Zero-K.app
       --content /path/to/profile-with-maps-and-games --output build/benchmark
The app must contain the GPU-sharing engine and Mesa patches. Do not run other
games or GPU workloads during measurement. Each case warms up for 15 seconds,
records 30 seconds of frame intervals, takes a screenshot, and exits.
"""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--content', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--repeats', type=int, default=2)
parser.add_argument('--display-link', type=int, choices=(0, 1), default=1)
parser.add_argument('--replay', type=Path)
parser.add_argument('--replay-start', type=int, default=600, help='Replay game seconds to seek before warm-up')
parser.add_argument('--label', default='static rendering scene')
parser.add_argument('--extra-maps', type=Path)
parser.add_argument('--require-gpu-events', action='store_true')
parser.add_argument('--require-reusable-uploads', action='store_true')
parser.add_argument('--case', choices=('metalfx_cpu', 'full_retina', 'ui_retina', 'metalfx_shared',
                                      'ui_retina_shared', 'full_retina_shared'))
args = parser.parse_args()
assert args.repeats > 0
assert args.replay_start >= 0
app, content, output = args.app.resolve(), args.content.resolve(), args.output.resolve()
assert (app / 'Contents/MacOS/Zero-K').is_file()
assert (content / 'maps').is_dir() and (content / 'games').is_dir()
output.mkdir(parents=True, exist_ok=True)
cases = [
    ('metalfx_cpu', 1, 1, 0),
    ('full_retina', 2, 0, 0),
    ('ui_retina', 1, 0, 0),
    ('metalfx_shared', 1, 1, 1),
    ('ui_retina_shared', 1, 0, 1),
    ('full_retina_shared', 2, 0, 1),
]
if args.case:
    cases = [case for case in cases if case[0] == args.case]
runs = []
expected_backing = None

for repeat in range(args.repeats):
    order = cases if repeat % 2 == 0 else list(reversed(cases))
    for name, mode, metalfx, sharing in order:
        profile = output / f'{name}-{repeat + 1}'
        profile.mkdir()
        for folder in ('games', 'maps', 'packages', 'pool', 'rapid'):
            if (content / folder).exists():
                if folder == 'maps' and args.extra_maps:
                    (profile / folder).mkdir()
                    for directory in (content / folder, args.extra_maps):
                        for file in directory.iterdir():
                            target = profile / folder / file.name
                            if not target.exists():
                                target.symlink_to(file.resolve(), target_is_directory=file.is_dir())
                else:
                    (profile / folder).symlink_to((content / folder).resolve(), target_is_directory=True)
        (profile / 'LuaUI/Config').mkdir(parents=True)
        (profile / 'LuaUI/Widgets').mkdir(parents=True)
        shutil.copy2(root / 'app/defaults/LuaUI/Config/ZK_data.lua', profile / 'LuaUI/Config/ZK_data.lua')
        shutil.copy2(root / 'tests/widget_metalfx_benchmark.lua', profile / 'LuaUI/Widgets/')
        if args.replay:
            (profile / 'benchmark_replay_start.txt').write_text(str(args.replay_start))
        settings = (root / 'app/defaults/springsettings.cfg').read_text()
        values = {'MacRetinaMode': mode, 'MacMetalFXSpatial': metalfx, 'MacGPUSharing': sharing,
                  'MacDisplayLink': args.display_link, 'Fullscreen': 1}
        for key, value in values.items():
            settings = re.sub(rf'(?m)^{key} = .*$', f'{key} = {value}', settings)
        (profile / 'springsettings.cfg').write_text(settings)
        environment = os.environ.copy()
        environment.pop('MTL_DEBUG_LAYER', None)
        environment['ZKMACOS_DATA_DIR'] = str(profile)
        print(f'Running {name}, pass {repeat + 1}', flush=True)
        with (profile / 'stdout.log').open('w') as stdout:
            process = subprocess.Popen([str(app / 'Contents/MacOS/Zero-K'), '--engine',
                                        str(args.replay.resolve() if args.replay else root / 'tests/static-skirmish.tdf')],
                                       env=environment, stdout=stdout, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                process.wait(timeout=600 if args.replay else 120)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
                raise RuntimeError(f'{name}: benchmark did not finish')
        log = (profile / 'infolog.txt').read_text(errors='replace')
        assert process.returncode == 0 and '[Benchmark] completed' in log, profile
        selection = 0 if args.replay else 1
        assert re.search(rf'\[Benchmark selected\], {selection}(?:\s|$)', log), f'Unexpected selection: {profile}'
        assert '[Benchmark selection changes], 0' in log, f'Selection changed during sampling: {profile}'
        assert f'[Benchmark selected at end], {selection}' in log, f'Selection did not persist: {profile}'
        assert 'sharing unavailable' not in log and 'presentation unavailable' not in log, profile
        assert ('presenting shared GPU texture' in log) == bool(sharing), profile
        assert ('[MacDisplayLink] display-driven frame pacing enabled' in log) == bool(args.display_link), profile
        if sharing and args.require_gpu_events:
            assert 'GPU event synchronization enabled' in log, f'GPU event handoff inactive: {profile}'
        if not sharing and args.require_reusable_uploads:
            assert 'presenting PBO pixels through reusable Metal textures' in log, profile
            assert 'reusable Metal presentation failed' not in log, profile
        if metalfx:
            assert ('shared GPU textures, native-resolution UI' if sharing else
                    'CPU staging, native-resolution UI') in log, profile
        sizes = re.findall(r'\[MacRetina\] mode=\d+ logical=(\d+x\d+) backing=(\d+x\d+) scene=(\d+x\d+)', log)
        assert sizes, profile
        logical, backing, scene = sizes[-1]
        assert all(size == sizes[-1] for size in sizes), f'Window changed during benchmark: {sizes}'
        if expected_backing is None:
            expected_backing = backing
        assert backing == expected_backing, f'Output resolution changed: {backing} vs {expected_backing}'
        viewports = re.findall(r'\[Benchmark viewport\], ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)', log)
        backing_size = tuple(map(int, backing.split('x')))
        assert len(viewports) == 2 and all(tuple(map(float, viewport)) == (0, 0, *backing_size)
                                           for viewport in viewports), f'Incorrect UI viewport: {viewports}'
        with (profile / 'benchmark_frames.csv').open() as csv_file:
            intervals = [float(row['interval_ms']) for row in csv.DictReader(csv_file)]
        assert len(intervals) > (10 if args.replay else 100) and sum(intervals) >= 29000, profile
        ordered = sorted(intervals)
        run = {'case': name, 'pass': repeat + 1, 'settings': values,
               'logical': logical, 'backing': backing, 'scene': scene,
               'ui_viewports': viewports,
               'frames': len(intervals), 'seconds': sum(intervals) / 1000,
               'fps': len(intervals) * 1000 / sum(intervals),
               'mean_ms': statistics.mean(intervals),
               'median_ms': statistics.median(intervals),
               'stddev_ms': statistics.pstdev(intervals),
               'max_ms': max(intervals),
               'over_16_67_ms_pct': 100 * sum(value > 1000 / 60 for value in intervals) / len(intervals),
               'p95_ms': ordered[math.ceil(len(ordered) * .95) - 1],
               'p99_ms': ordered[math.ceil(len(ordered) * .99) - 1],
               'profile': str(profile)}
        if args.replay:
            run['replay_frames'] = re.findall(r'\[Benchmark replay frames\], (\d+), (\d+)', log)
            run['replay_units'] = re.findall(r'\[Benchmark replay units\], (\d+), (\d+)', log)
            assert run['replay_frames'] and run['replay_units'], profile
        runs.append(run)
        (output / 'runs.json').write_text(json.dumps(runs, indent=2) + '\n')
        print(json.dumps(run), flush=True)

summary = {'hardware': {key: subprocess.check_output(['sysctl', '-n', key], text=True).strip()
                        for key in ('machdep.cpu.brand_string', 'hw.memsize', 'hw.ncpu')},
           'display': expected_backing, 'warmup_seconds': 15, 'sample_seconds_per_run': 30,
           'vsync': 1, 'display_link': args.display_link,
           'graphics': 'Fresh isolated game profiles with identical app defaults',
           'scene': args.label if args.replay else 'Fairyland 1.31, static skirmish, fixed TA camera',
           'replay': {'path': str(args.replay.resolve()), 'sha256': hashlib.sha256(args.replay.read_bytes()).hexdigest(),
                      'seek_seconds': args.replay_start} if args.replay else None,
           'engine_sha256': hashlib.sha256((app / 'Contents/MacOS/spring').read_bytes()).hexdigest(),
           'runs': runs, 'cases': []}
for name, mode, metalfx, sharing in cases:
    selected = [run for run in runs if run['case'] == name]
    intervals = []
    for run in selected:
        with (Path(run['profile']) / 'benchmark_frames.csv').open() as csv_file:
            intervals.extend(float(row['interval_ms']) for row in csv.DictReader(csv_file))
    intervals.sort()
    summary['cases'].append({'case': name,
                             'fps': sum(run['frames'] for run in selected) / sum(run['seconds'] for run in selected),
                             'fps_runs': [run['fps'] for run in selected],
                             'mean_ms': sum(run['seconds'] for run in selected) * 1000 / sum(run['frames'] for run in selected),
                             'median_ms': statistics.median(intervals),
                             'stddev_ms': statistics.pstdev(intervals),
                             'max_ms': max(intervals),
                             'over_16_67_ms_pct': 100 * sum(value > 1000 / 60 for value in intervals) / len(intervals),
                             'p95_ms_runs': [run['p95_ms'] for run in selected],
                             'p95_ms': intervals[math.ceil(len(intervals) * .95) - 1],
                             'p99_ms': intervals[math.ceil(len(intervals) * .99) - 1]})
(output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary['cases'], indent=2))

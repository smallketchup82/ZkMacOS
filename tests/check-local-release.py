"""Check local release safety, pinned sources, CLI drafts and progress reporting."""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch
import base64
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, NoEncryption

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
import build_progress
spec = importlib.util.spec_from_file_location('local_release', root / 'scripts/create-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class LocalReleaseChecks(unittest.TestCase):
    def test_only_the_matching_production_key_is_accepted(self):
        key = Ed25519PrivateKey.generate()
        secret = base64.b64encode(key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())).decode()
        public = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
        release.check_key(secret, public)
        for invalid in ('invalid', base64.b64encode(bytes(31)).decode()):
            with self.assertRaisesRegex(ValueError, 'encoding'):
                release.check_key(invalid, public)
        with self.assertRaisesRegex(ValueError, 'does not match'):
            release.check_key(secret, base64.b64encode(bytes(32)).decode())

    def test_release_is_a_draft_with_version_title_and_only_download_artifacts(self):
        display = Mock()
        expected = [release.ASSET, release.ASSET + '.sha256', 'appcast.xml']
        metadata = {'isDraft': True, 'assets': [{'name': name} for name in expected],
                    'url': 'https://github.com/smallketchup82/ZkMacOS/releases/tag/untagged-test'}
        with patch.object(release.subprocess, 'check_output', return_value=json.dumps(metadata)):
            url = release.create_draft(display, '202610.29.0', 'a' * 40, Path('/tmp/my notes.md'))
        command = list(map(str, display.run.call_args.args[0]))
        self.assertEqual(command[:3], ['gh', 'release', 'create'])
        self.assertEqual(command[command.index('--title') + 1], '202610.29.0')
        self.assertEqual(command[command.index('--target') + 1], 'a' * 40)
        self.assertEqual(command[command.index('--notes-file') + 1], '/tmp/my notes.md')
        self.assertIn('--draft', command)
        self.assertNotIn('--draft=false', command)
        self.assertTrue(url.endswith('/releases/edit/untagged-test'))
        uploaded = [Path(arg).name for arg in command if Path(arg).parent == release.ROOT / 'dist']
        self.assertCountEqual(uploaded, expected)
        metadata['assets'].pop()
        with patch.object(release.subprocess, 'check_output', return_value=json.dumps(metadata)):
            with self.assertRaisesRegex(ValueError, 'uploads are missing'):
                release.create_draft(display, '202610.29.0', 'a' * 40, Path('/tmp/notes.md'))

    def test_source_check_requires_clean_pinned_fork_commits(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            source = folder / 'source'
            source.mkdir()
            def git(*arguments):
                return subprocess.check_output(['git', '-C', str(source), *arguments], text=True).strip()
            git('init', '-q')
            (source / 'code.txt').write_text('original\n')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'base')
            revision = git('rev-parse', 'HEAD')
            release.check_source(source, revision)
            with self.assertRaisesRegex(ValueError, 'not at its release pin'):
                release.check_source(source, '0' * 40)
            (source / 'code.txt').write_text('uncommitted feature\n')
            with self.assertRaisesRegex(ValueError, 'uncommitted source'):
                release.check_source(source, revision)
            git('checkout', '--', 'code.txt')
            (source / 'surprise.lua').write_text('untracked feature\n')
            with self.assertRaisesRegex(ValueError, 'uncommitted source'):
                release.check_source(source, revision)

    def test_source_fetcher_checks_out_pin_and_preserves_developer_edits(self):
        spec = importlib.util.spec_from_file_location('fetch_sources', root / 'scripts/fetch-sources.py')
        fetcher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fetcher)
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            source = folder / 'fork'
            source.mkdir()
            def git(*arguments):
                return subprocess.check_output(['git', '-C', str(source), *arguments], text=True).strip()
            git('init', '-q')
            (source / 'feature.txt').write_text('committed macOS feature\n')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'port')
            revision = git('rev-parse', 'HEAD')
            destination = folder / 'checkout'
            pin = {'url': str(source), 'revision': revision}
            fetcher.prepare_source(destination, pin)
            release.check_source(destination, revision)
            self.assertEqual((destination / 'feature.txt').read_text(), 'committed macOS feature\n')
            (destination / 'feature.txt').write_text('local work in progress\n')
            fetcher.prepare_source(destination, pin)
            self.assertEqual((destination / 'feature.txt').read_text(), 'local work in progress\n')

    def test_progress_records_failure_and_does_not_pass_signing_key_to_children(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(build_progress, 'ROOT', Path(folder)), \
                patch.dict(os.environ, {'SPARKLE_PRIVATE_ED_KEY': 'should-not-reach-child'}), redirect_stdout(StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'exit 3'):
                with build_progress.BuildProgress('Test pipeline', 'test', 1, plain=True) as display:
                    display.run([sys.executable, '-c', "import os,sys; print('::zk-step::1|1|Compile'); print('[1/2] source.cpp'); assert 'SPARKLE_PRIVATE_ED_KEY' not in os.environ; print('compiler error example'); sys.exit(3)"], build_steps=True)
            result = json.loads((Path(folder) / 'build/logs/test-result.json').read_text())
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['step'], 'Compile')
            self.assertIn('compiler error example', (Path(folder) / 'build/logs/test.log').read_text())
            # The failed process must release the checkout lock for a retry.
            with build_progress.BuildProgress('Retry', 'test', 1, plain=True) as display:
                display.step(1, 'Retry')
                display.run([sys.executable, '-c', "print('done')"])
            result = json.loads((Path(folder) / 'build/logs/test-result.json').read_text())
            self.assertEqual(result['status'], 'success')

    def test_engine_progress_uses_ninja_completed_tasks_not_time_or_output_lines(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(build_progress, 'ROOT', Path(folder)), redirect_stdout(StringIO()):
            with build_progress.BuildProgress('Engine', 'engine', 1, plain=True) as display:
                display.step(1, 'Compile engine')
                display.run([sys.executable, '-c', "import os; assert os.environ['NINJA_STATUS'] == '[%f/%t] '; print('::zk-step::5|9|Compile engine'); print('[742/1641] Building source.cpp'); print('a compiler warning'); print('another compiler warning')"])
                task = display.progress.tasks[display.engine]
                self.assertTrue(task.visible)
                self.assertEqual(task.description, 'Engine compilation')
                self.assertEqual(task.completed, 742)
                self.assertEqual(display.progress.tasks[display.overall].completed, 0)
                self.assertEqual(task.total, 1641)
                self.assertEqual(task.fields['count'], '742 / 1641 tasks')
                self.assertAlmostEqual(task.percentage, 742 / 1641 * 100)

    def test_a_second_pipeline_cannot_overwrite_build_outputs(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(build_progress, 'ROOT', Path(folder)), redirect_stdout(StringIO()):
            with build_progress.BuildProgress('First', 'first', 1, plain=True):
                with self.assertRaisesRegex(RuntimeError, 'Another build or release'):
                    with build_progress.BuildProgress('Second', 'second', 1, plain=True):
                        self.fail('Concurrent pipeline acquired the same checkout')


if __name__ == '__main__':
    unittest.main()

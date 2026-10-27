"""Exercise release checks and cask upgrade behavior without publishing a release."""
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import tempfile
import unittest
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('update_cask', root / 'scripts/update-cask.py')
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class CaskChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.dmg = self.directory / updater.ASSET
        self.dmg.write_bytes(b'test release artifact')
        self.checksum = self.directory / (updater.ASSET + '.sha256')
        self.digest = hashlib.sha256(self.dmg.read_bytes()).hexdigest()
        self.checksum.write_text(self.digest + '  ' + updater.ASSET + '\n')
        self.output = self.directory / 'Casks/zkmacos.rb'

    def update(self, tag):
        return updater.update_cask(tag, self.dmg, self.checksum, self.output, 'smallketchup82/ZkMacOS')

    def test_pins_release_checksum_and_supported_platform(self):
        self.assertTrue(self.update('202610.27.0'))
        cask = self.output.read_text()
        self.assertIn('version "202610.27.0"', cask)
        self.assertIn('sha256 "' + self.digest + '"', cask)
        self.assertIn('/releases/download/202610.27.0/' + updater.ASSET, cask)
        self.assertIn('depends_on arch: :arm64', cask)
        self.assertIn('depends_on macos: :tahoe', cask)
        self.assertNotIn('auto_updates', cask)
        self.assertNotIn('zap ', cask)

    def test_new_version_advances_but_older_or_identical_does_not(self):
        self.update('202610.27.0')
        self.assertTrue(self.update('202610.27.1'))
        saved = self.output.read_bytes()
        self.assertFalse(self.update('202610.27.0'))
        self.assertFalse(self.update('202610.27.1'))
        self.assertEqual(saved, self.output.read_bytes())
        self.assertTrue(self.update('202611.01.0'))

    def test_checksum_mismatch_keeps_existing_cask(self):
        self.update('202610.27.0')
        saved = self.output.read_bytes()
        self.dmg.write_bytes(b'corrupted download')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            self.update('202610.27.1')
        self.assertEqual(saved, self.output.read_bytes())

    def test_same_version_cannot_replace_existing_artifact(self):
        self.update('202610.27.0')
        self.dmg.write_bytes(b'different artifact with valid new checksum')
        digest = hashlib.sha256(self.dmg.read_bytes()).hexdigest()
        self.checksum.write_text(digest + '  ' + updater.ASSET)
        with self.assertRaisesRegex(ValueError, 'publish a new version'):
            self.update('202610.27.0')

    def test_invalid_tags_and_checksum_filename_are_rejected(self):
        for tag in ('202610.27.0-beta.1', 'latest', '202610.27.0"', '../202610.27.0',
                    '202602.30.0', '202613.01.0', '202610.7.0', 'v202610.27.0'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.update(tag)
        self.checksum.write_text(self.digest + '  unrelated.dmg')
        with self.assertRaises(ValueError):
            self.update('202610.27.0')
        self.assertFalse(self.output.exists())

    def test_unpublished_or_incomplete_releases_are_rejected(self):
        releases = [
            {'draft': True, 'prerelease': False},
            {'draft': False, 'prerelease': True},
            {'draft': False, 'prerelease': False, 'assets': []},
        ]
        for release in releases:
            with self.subTest(release=release), \
                    patch('sys.argv', ['update-cask.py', '--tag', '202610.27.0']), \
                    patch.object(updater.subprocess, 'check_output', return_value=json.dumps(release)), \
                    patch.object(updater.subprocess, 'run') as download, \
                    self.assertRaises(ValueError):
                updater.main()
            download.assert_not_called()

    def test_release_command_downloads_assets_and_generates_cask(self):
        release = {'draft': False, 'prerelease': False, 'assets': [
            {'name': updater.ASSET}, {'name': updater.ASSET + '.sha256'},
        ]}

        def download(command, check):
            self.assertTrue(check)
            self.assertEqual(command[:3], ['gh', 'release', 'download'])
            destination = Path(command[-1])
            shutil.copy2(self.dmg, destination / self.dmg.name)
            shutil.copy2(self.checksum, destination / self.checksum.name)

        with patch('sys.argv', ['update-cask.py', '--tag', '202610.27.0']), \
                patch.object(updater, 'ROOT', self.directory), \
                patch.object(updater.subprocess, 'check_output', return_value=json.dumps(release)), \
                patch.object(updater.subprocess, 'run', side_effect=download):
            updater.main()
        self.assertIn('version "202610.27.0"', self.output.read_text())


if __name__ == '__main__':
    unittest.main()

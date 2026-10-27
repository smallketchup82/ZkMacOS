"""Check daily CalVer allocation without creating tags or releases."""
from datetime import date
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from contextlib import redirect_stdout
from io import StringIO

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_version', root / 'scripts/next-release-version.py')
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class ReleaseVersionChecks(unittest.TestCase):
    def test_first_release_and_new_day_start_at_zero(self):
        self.assertEqual(version.next_version([], date(2026, 10, 27)), '202610.27.0')
        self.assertEqual(version.next_version(['202610.27.9'], date(2026, 10, 28)), '202610.28.0')
        self.assertEqual(version.next_version(['202610.31.9'], date(2026, 11, 1)), '202611.01.0')

    def test_numeric_order_gaps_duplicates_and_unrelated_tags(self):
        tags = ['202610.27.0', '202610.27.2', '202610.27.10', '202610.27.2',
                '202610.26.99', 'latest', '202610.27.11-beta', '202610.27.012']
        self.assertEqual(version.next_version(tags, date(2026, 10, 27)), '202610.27.11')

    def test_all_release_and_tag_pages_are_considered(self):
        pages = [
            json.dumps([[{'tag_name': '202610.27.0'}], [{'tag_name': '202610.27.3'}]]),
            json.dumps([[{'name': '202610.27.5'}]]),
        ]
        with patch('sys.argv', ['next-release-version.py']), \
                patch.object(version.subprocess, 'check_output', side_effect=pages) as api, \
                patch.object(version, 'datetime') as clock, redirect_stdout(StringIO()) as output:
            clock.now.return_value.date.return_value = date(2026, 10, 27)
            version.main()
        self.assertEqual(output.getvalue().strip(), '202610.27.6')
        self.assertEqual(str(clock.now.call_args.args[0]), 'America/Toronto')
        self.assertEqual(api.call_count, 2)
        for call in api.call_args_list:
            self.assertIn('--paginate', call.args[0])
            self.assertIn('--slurp', call.args[0])


if __name__ == '__main__':
    unittest.main()

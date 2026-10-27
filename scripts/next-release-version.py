"""Choose the next YYYYMM.DD.PATCH release version using the Toronto date."""
from datetime import datetime
import argparse
import json
import os
import re
import subprocess
from zoneinfo import ZoneInfo


def next_version(tags, day):
    prefix = day.strftime('%Y%m.%d.')
    patches = []
    for tag in tags:
        if tag.startswith(prefix) and re.fullmatch(r'0|[1-9][0-9]*', tag[len(prefix):]):
            patches.append(int(tag[len(prefix):]))
    return prefix + str(max(patches, default=-1) + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY', 'smallketchup82/ZkMacOS'))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        raise ValueError('Expected a GitHub owner/repository.')
    tags = []
    for endpoint, field in (('releases', 'tag_name'), ('tags', 'name')):
        pages = json.loads(subprocess.check_output([
            'gh', 'api', '--paginate', '--slurp', f'repos/{args.repository}/{endpoint}?per_page=100',
        ], text=True))
        tags.extend(item[field] for page in pages for item in page)
    print(next_version(tags, datetime.now(ZoneInfo('America/Toronto')).date()))


if __name__ == '__main__':
    main()

"""
Sync the hand-collected asset folder (Drive) into an environment's S3.

The Drive folder is the human collection and keeps **display-name** filenames
forever (`Bench Press (Barbell).gif`) — helpers know that convention and it
does not change. Everything downstream is derived:

  Drive (names, human) ──this script──▶ exercise-uploads/<slug>.<ext>   pipeline intake
                                              │ heart-assets Lambda
                                              ▼
                                        exercises/<slug>/…              machine output — never hand-written

There is no S3 copy of the collection: Drive (and its local copy in
content/assets/, gitignored) is the fallback. The processed asset object holds
the original bytes verbatim, so change detection diffs the local file size
against exercises/<slug>/asset.<ext>.

The per-addition process: run with --dry-run, fix the reported typos IN DRIVE
(to the correct display names — same convention), re-run for real. Only new or
changed files upload, so a run after a big drop moves just the delta — and the
coverage report at the end shows which library exercises still have no asset
anywhere (the "did everything propagate" check).

A filename stem that matches no library en name is reported with the closest
match and never uploaded — typos are fixed at the source, not guessed at here.

Run per environment:
  AWS_PROFILE=heart-dev  uv run python scripts/sync_assets.py --source <drive-dir> --bucket <content-bucket> --dry-run
  AWS_PROFILE=heart-dev  uv run python scripts/sync_assets.py --source <drive-dir> --bucket <content-bucket>
"""

import argparse
import difflib
import os

import boto3
import yaml

UPLOAD_PREFIX = 'exercise-uploads/'
DEST_PREFIX = 'exercises/'
EXTENSIONS = {'gif', 'png', 'jpg', 'jpeg', 'webp'}


def name_to_slug() -> dict[str, str]:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, '..', 'content', 'exercise_library.yml')) as f:
        master = yaml.safe_load(f)
    return {ex['i18n']['en']['name']: key for key, ex in master['exercises'].items()}


def s3_sizes(s3, bucket: str, prefix: str) -> dict[str, int]:
    sizes = {}
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get('Contents', []):
            sizes[obj['Key']] = obj['Size']
    return sizes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, help='local Drive-synced folder (display-name stems)')
    parser.add_argument('--bucket', required=True, help='the environment content bucket')
    parser.add_argument('--dry-run', action='store_true', help='report the plan, upload nothing')
    args = parser.parse_args()

    by_name = name_to_slug()
    s3 = boto3.client('s3')
    processed = s3_sizes(s3, args.bucket, DEST_PREFIX)
    # slug -> size of its processed asset object (the original bytes verbatim)
    asset_sizes = {
        k.split('/')[1]: size
        for k, size in processed.items()
        if k.count('/') >= 2 and k.rsplit('/', 1)[-1].startswith('asset')
    }

    def upload(path: str, key: str) -> None:
        print(f'  {os.path.basename(path)} -> {key}')
        if not args.dry_run:
            s3.upload_file(path, args.bucket, key)

    uploaded, unchanged, unmatched = 0, 0, []
    covered = set()
    for entry in sorted(os.listdir(args.source)):
        path = os.path.join(args.source, entry)
        if not os.path.isfile(path):
            continue
        stem, dot, ext = entry.rpartition('.')
        if not dot or ext.lower() not in EXTENSIONS:
            continue
        slug = by_name.get(stem)
        if slug is None:
            hint = difflib.get_close_matches(stem, by_name.keys(), n=1, cutoff=0.6)
            unmatched.append(f'{entry}' + (f'  — did you mean {hint[0]!r}?' if hint else ''))
            continue
        covered.add(slug)

        if os.path.getsize(path) != asset_sizes.get(slug):
            upload(path, f'{UPLOAD_PREFIX}{slug}.{ext.lower()}')
            uploaded += 1
        else:
            unchanged += 1

    missing = sorted(set(by_name.values()) - set(asset_sizes) - covered)
    print(f'>> {uploaded} sent through the pipeline, {unchanged} unchanged, {len(unmatched)} unmatched filenames')
    for line in unmatched:
        print(f'   fix in Drive: {line}')
    if missing:
        print(f'>> {len(missing)} library exercises still have no asset anywhere:')
        for slug in missing:
            print(f'   missing: {slug}')
    if args.dry_run:
        print('>> dry run: nothing uploaded')


if __name__ == '__main__':
    main()

"""
One-shot: re-key exercise assets in S3 from display-name stems to slug stems.

The source of truth is the serving set itself: `exercises/<Exercise Name>/`
holds the processed assets the database rows link to, and the asset object is
the original upload bytes verbatim. Each directory name is slugified with the
same rule as everywhere else (lowercase, non-alphanumeric runs to '-', edges
trimmed) and the asset is copied to `exercise-uploads/<slug>.<ext>` — which
fires the assets Lambda, reprocesses under `exercises/<slug>/`, and sends
`exercise.asset.processed` so the API rewrites the row's asset/thumbnail
links. No hand-edited CDN URLs, no direct DB writes.

A directory whose slug matches no library exercise (typos in old hand-named
uploads, removed exercises) is reported and left untouched — not repaired.
Idempotent: a slug directory that already exists is skipped.

Old name-keyed `exercises/<Name>/` directories keep serving the not-yet-
rewritten links; pass --delete-old only after verifying the new links.

Run per environment, with the profile pointing at that env's account:
  AWS_PROFILE=heart-dev  uv run python scripts/migrate_asset_keys.py --bucket <content-bucket> --dry-run
  AWS_PROFILE=heart-dev  uv run python scripts/migrate_asset_keys.py --bucket <content-bucket>
"""

import argparse
import os
import re

import boto3
import yaml

UPLOAD_PREFIX = 'exercise-uploads/'
DEST_PREFIX = 'exercises/'


def slugify(name: str) -> str:
    """The platform slug rule — must match the content keys and the DB backfill."""
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def library_keys() -> set[str]:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, '..', 'content', 'exercise_library.yml')) as f:
        return set(yaml.safe_load(f)['exercises'])


def list_keys(s3, bucket: str, prefix: str) -> list[str]:
    keys = []
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=prefix):
        keys.extend(obj['Key'] for obj in page.get('Contents', []))
    return keys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bucket', required=True, help='the content bucket holding exercises/')
    parser.add_argument('--dry-run', action='store_true', help='print the plan, copy nothing')
    parser.add_argument('--delete-old', action='store_true',
                        help='delete the name-keyed exercises/<Name>/ directories '
                             '(run only after verifying the new links serve)')
    args = parser.parse_args()

    keys = library_keys()
    s3 = boto3.client('s3')
    processed = list_keys(s3, args.bucket, DEST_PREFIX)

    # directory name -> its objects
    dirs: dict[str, list[str]] = {}
    for key in processed:
        rest = key[len(DEST_PREFIX):]
        if '/' in rest:
            dirs.setdefault(rest.split('/', 1)[0], []).append(key)

    triggered, skipped, unknown, deleted = 0, 0, [], 0
    for name, objects in sorted(dirs.items()):
        slug = slugify(name)
        if name == slug:
            continue  # already slug-keyed
        if slug not in keys:
            unknown.append(name)
            continue
        if slug in dirs:
            skipped += 1  # slug directory already exists
        else:
            asset = next((k for k in objects if k.rsplit('/', 1)[-1].startswith('asset')), None)
            if asset is None:
                unknown.append(f'{name} (no asset object)')
                continue
            _stem, dot, ext = asset.rsplit('/', 1)[-1].rpartition('.')
            dst = f'{UPLOAD_PREFIX}{slug}.{ext}' if dot else f'{UPLOAD_PREFIX}{slug}'
            print(f'  {asset} -> {dst}')
            if not args.dry_run:
                s3.copy_object(Bucket=args.bucket, CopySource={'Bucket': args.bucket, 'Key': asset}, Key=dst)
            triggered += 1

        if args.delete_old and not args.dry_run:
            for key in objects:
                s3.delete_object(Bucket=args.bucket, Key=key)
                deleted += 1

    print(f'>> {triggered} sent through the pipeline, {skipped} already slug-keyed, '
          f'{deleted} old objects deleted, {len(unknown)} unmapped directories')
    for name in unknown:
        print(f'   unmapped: {name}')
    if args.dry_run:
        print('>> dry run: nothing copied')


if __name__ == '__main__':
    main()

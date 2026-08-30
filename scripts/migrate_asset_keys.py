"""
One-shot: re-key exercise assets in S3 from display-name stems to slug stems.

The pipeline itself is the migration tool: for every source upload at
`exercise-uploads/<Exercise Name>.<ext>` whose stem matches a library exercise,
copy the object to `exercise-uploads/<slug>.<ext>`. The copy fires the assets
Lambda, which reprocesses under `exercises/<slug>/` and sends the
`exercise.asset.processed` event, and the API rewrites the row's asset/thumbnail
links — no hand-edited CDN URLs, no direct DB writes.

Old objects (name-keyed sources and their `exercises/<Name>/` outputs) are left
in place; pass --delete-old after verifying the new links serve, or clean up by
hand. Idempotent: a source already at its slug key is skipped.

Run per environment, with the profile pointing at that env's account:
  AWS_PROFILE=heart-dev  uv run python scripts/migrate_asset_keys.py --bucket <content-bucket> [--dry-run]
  AWS_PROFILE=heart-prod uv run python scripts/migrate_asset_keys.py --bucket <content-bucket> [--dry-run]
"""

import argparse
import os

import boto3
import yaml

SOURCE_PREFIX = 'exercise-uploads/'
DEST_PREFIX = 'exercises/'


def slugs() -> dict[str, str]:
    """en display name -> slug, from the library master (i18n.en.name -> map key)."""
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, '..', 'content', 'exercise_library.yml')) as f:
        master = yaml.safe_load(f)
    return {ex['i18n']['en']['name']: key for key, ex in master['exercises'].items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bucket', required=True, help='the content bucket holding exercise-uploads/')
    parser.add_argument('--dry-run', action='store_true', help='print the plan, copy nothing')
    parser.add_argument('--delete-old', action='store_true',
                        help='also delete the name-keyed sources and processed dirs (run only after verifying)')
    args = parser.parse_args()

    by_name = slugs()
    slug_set = set(by_name.values())
    s3 = boto3.client('s3')

    paginator = s3.get_paginator('list_objects_v2')
    copied, skipped, unknown = 0, 0, []
    for page in paginator.paginate(Bucket=args.bucket, Prefix=SOURCE_PREFIX):
        for obj in page.get('Contents', []):
            key = obj['Key']
            base = key.rsplit('/', 1)[-1]
            stem, dot, ext = base.rpartition('.')
            if not dot:
                stem, ext = base, ''
            if stem in slug_set:
                skipped += 1  # already migrated
                continue
            if stem not in by_name:
                unknown.append(key)  # not a library exercise name; leave it
                continue
            new_key = f'{SOURCE_PREFIX}{by_name[stem]}.{ext}' if ext else f'{SOURCE_PREFIX}{by_name[stem]}'
            print(f'{key} -> {new_key}')
            if not args.dry_run:
                s3.copy_object(Bucket=args.bucket, CopySource={'Bucket': args.bucket, 'Key': key}, Key=new_key)
                if args.delete_old:
                    s3.delete_object(Bucket=args.bucket, Key=key)
                    # the processed outputs of the old name
                    old_dir = f'{DEST_PREFIX}{stem}/'
                    for out in s3.list_objects_v2(Bucket=args.bucket, Prefix=old_dir).get('Contents', []):
                        s3.delete_object(Bucket=args.bucket, Key=out['Key'])
            copied += 1

    print(f'>> {copied} to migrate, {skipped} already slug-keyed, {len(unknown)} unknown stems')
    for key in unknown:
        print(f'   unknown: {key}')
    if args.dry_run:
        print('>> dry run: nothing copied')


if __name__ == '__main__':
    main()

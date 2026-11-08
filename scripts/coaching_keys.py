#!/usr/bin/env python3
"""Puts coaching's two keys where Terraform reads them, so messages and reports turn on.

Usage:
    uv run scripts/coaching_keys.py dev|prod [--rotate] [--review-key PUBLIC] [--dry-run]

Each environment's static bucket holds them under secrets/coaching/, as text/plain
(Terraform reads any other type back as empty):

- message-tag-keys.txt: the HMAC keys that tag messages, `id:base64` pairs, newest
  first. Made here when missing, one per environment. `--rotate` puts a new pair in
  front and keeps the old ones, because a message is checked with the key it was
  tagged with.
- report-review-key.txt: the public half of the key reports are sealed to. Made here
  when missing, and the private half is printed once, for a password manager: it is
  never written anywhere, and without it no report can be opened (open_report.py).
  `--review-key` uses a public half made earlier instead, so one pair can serve both
  environments.

What is already there is kept, so running it twice changes nothing. Nothing secret
touches the disk: the keys go from memory to S3. Afterwards, apply Terraform in
infrastructure/app/environments/<env>, which puts them on the Lambdas.
"""

import argparse
import base64
import os
import sys
from datetime import UTC, datetime

import boto3
from botocore.exceptions import ClientError
from open_report import generate

PREFIX = 'secrets/coaching/'
TAG_KEYS = PREFIX + 'message-tag-keys.txt'
REVIEW_KEY = PREFIX + 'report-review-key.txt'
REGION = 'ca-central-1'


def new_tag_pair(now: datetime) -> str:
    """One `id:base64` pair: 32 random bytes, named for the minute it was made."""
    return f'k{now:%Y%m%d%H%M}:{base64.b64encode(os.urandom(32)).decode()}'


def tag_keys(existing: str | None, *, rotate: bool, now: datetime) -> str | None:
    """The tag keys to store, or None to leave what's there."""
    if existing and not rotate:
        return None
    pair = new_tag_pair(now)
    if existing and pair.split(':', 1)[0] in {entry.split(':', 1)[0] for entry in existing.split(',')}:
        raise SystemExit('a key was already made this minute; rotate again in a minute')
    return f'{pair},{existing}' if existing else pair


def valid_public_key(value: str) -> bool:
    try:
        return len(base64.b64decode(value, validate=True)) == 32
    except ValueError:
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('env', choices=['dev', 'prod'])
    parser.add_argument('--rotate', action='store_true', help='put a new tag key in front of the old ones')
    parser.add_argument('--review-key', help="a report review key's public half, made earlier")
    parser.add_argument('--dry-run', action='store_true', help='say what would change, change nothing')
    args = parser.parse_args()

    if args.review_key and not valid_public_key(args.review_key):
        raise SystemExit('--review-key must be the base64 public half open_report.py --generate printed')

    session = boto3.Session(profile_name=f'heart-{args.env}', region_name=REGION)
    account = session.client('sts').get_caller_identity()['Account']
    bucket = f'{account}-{REGION}-static'
    s3 = session.client('s3')

    def read(key: str) -> str | None:
        try:
            return s3.get_object(Bucket=bucket, Key=key)['Body'].read().decode().strip() or None
        except ClientError as error:
            if error.response['Error']['Code'] in ('NoSuchKey', '404'):
                return None
            raise

    def write(key: str, value: str) -> None:
        if args.dry_run:
            return
        s3.put_object(Bucket=bucket, Key=key, Body=value.encode(), ContentType='text/plain')

    print(f'{args.env}: s3://{bucket}/{PREFIX}')

    existing_tags = read(TAG_KEYS)
    tags = tag_keys(existing_tags, rotate=args.rotate, now=datetime.now(UTC))
    if tags is None:
        print(f'  tag keys: kept ({len(existing_tags.split(","))} key(s), newest {existing_tags.split(":")[0]})')
    else:
        write(TAG_KEYS, tags)
        print(f'  tag keys: {"rotated" if existing_tags else "made"}, newest {tags.split(":")[0]}')

    existing_review = read(REVIEW_KEY)
    private = None
    if existing_review and (not args.review_key or args.review_key == existing_review):
        print('  review key: kept')
    elif existing_review:
        raise SystemExit(
            '  review key: this environment already has a different one; reports sealed to it '
            'need its private half, so replace it by hand if you mean to'
        )
    else:
        public = args.review_key
        if not public:
            private, public = generate()
        write(REVIEW_KEY, public)
        print(f'  review key: {"given" if args.review_key else "made"}, public {public}')

    if args.dry_run:
        print('dry run: nothing written')
        return
    if private:
        print(
            '\nThe private half, shown this once. Put it in your password manager now: without it\n'
            'no report can be opened, and it is stored nowhere else.\n\n'
            f'  {private}\n\n'
            f'To use the same pair for the other environment: --review-key {public}',
            file=sys.stderr,
        )
    if tags is not None or private or (args.review_key and not existing_review):
        print(f'\nNext: terraform -chdir=infrastructure/app/environments/{args.env} apply')


if __name__ == '__main__':
    main()

"""
Backfill profiles.created_at from each account's Firebase Auth creation time
(heart-api#407).

Reads:
  - Firebase Auth: every user's creation time, via the Admin SDK
  - Firebase service-account key: s3://SECRETS_BUCKET/secrets/firebase/firebase-terraform-sa.json,
    or the file FIREBASE_CRED_PATH names
  - Supabase creds: s3://SECRETS_BUCKET/secrets/supabase.json (as library_locales.connect)

Writes:
  - profiles.created_at, only with --apply. A row keeps the earlier of what it
    holds and its Firebase time, so a re-run changes nothing, and a row inserted
    after the migration (stamped with its insert time) still moves back to the
    moment the account was made. A profile with no Firebase user is left as it is
    and counted.

Without --apply it reports what it would do and writes nothing. Run once per
environment, after the migration has been applied there:

    AWS_PROFILE=heart-dev SECRETS_BUCKET=583168578067-ca-central-1-static \\
        uv run scripts/profile_created_at.py [--apply]
    AWS_PROFILE=heart-prod SECRETS_BUCKET=922419543441-ca-central-1-static \\
        uv run scripts/profile_created_at.py [--apply]

Env:
  SECRETS_BUCKET      the environment's static bucket; unset, the local database
                      (PG* env) and FIREBASE_CRED_PATH are used
  FIREBASE_CRED_PATH  a service-account key file, instead of the bucket's
"""

import argparse
import json
import os
from collections.abc import Iterable
from datetime import UTC, datetime

import boto3
import firebase_admin
from firebase_admin import auth, credentials
from library_locales import connect

FIREBASE_KEY = 'secrets/firebase/firebase-terraform-sa.json'

_BACKFILL = """
UPDATE profiles
SET
    created_at = least(profiles.created_at, made.at)
FROM unnest(%(ids)s::text[], %(ats)s::timestamptz[]) AS made (id, at)
WHERE profiles.id = made.id
    AND profiles.created_at IS DISTINCT FROM least(profiles.created_at, made.at)
"""


def creation_times(users: Iterable) -> dict[str, datetime]:
    """Each Firebase user's uid → when the account was made. A user without a
    creation time, which Firebase shouldn't have, is left out rather than guessed."""
    return {
        user.uid: datetime.fromtimestamp(made / 1000, tz=UTC)
        for user in users
        if (made := user.user_metadata.creation_timestamp) is not None
    }


def firebase_credentials() -> credentials.Certificate:
    if path := os.environ.get('FIREBASE_CRED_PATH'):
        return credentials.Certificate(path)
    bucket = os.environ['SECRETS_BUCKET']
    print(f'>> Fetching the Firebase key from s3://{bucket}/{FIREBASE_KEY}')
    key = boto3.client('s3').get_object(Bucket=bucket, Key=FIREBASE_KEY)['Body'].read()
    return credentials.Certificate(json.loads(key))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--apply', action='store_true', help='write; without it, only report')
    args = parser.parse_args()

    firebase_admin.initialize_app(firebase_credentials())
    made = creation_times(auth.list_users().iterate_all())
    print(f'>> {len(made)} Firebase users')

    with connect() as conn:
        ids, ats = list(made), list(made.values())
        changed = conn.execute(_BACKFILL, {'ids': ids, 'ats': ats}).rowcount
        unknown = conn.execute('SELECT count(*) FROM profiles WHERE NOT (id = ANY(%s))', (ids,)).fetchone()[0]
        empty = conn.execute('SELECT count(*) FROM profiles WHERE created_at IS NULL').fetchone()[0]
        print(f'>> {changed} profiles {"set" if args.apply else "would be set"}')
        print(f'>> {unknown} profiles have no Firebase user')
        print(f'>> {empty} profiles {"are" if args.apply else "would be"} left without created_at')
        if not args.apply:
            conn.rollback()
            print('>> Nothing written (pass --apply)')


if __name__ == '__main__':
    main()

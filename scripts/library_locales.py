"""
Sync the exercise library from content/exercise_library.yml to Postgres.

Reads:
  - Source YAML: ../content/exercise_library.yml
  - Asset listing: s3://CONTENT_BUCKET/exercises/exercises/<name>/{asset,thumbnail}.<ext>
  - Supabase creds: s3://SECRETS_BUCKET/secrets/supabase.json

Writes:
  - exercises (global, user_id IS NULL) — fallback locale fields, asset, thumbnail, muscles
  - exercise_translations — one row per non-fallback locale that has its own name/instructions
  - Archives any global exercise not in the source YAML.

Env:
  CONTENT_BUCKET     content bucket holding processed exercise assets
  SECRETS_BUCKET     static bucket holding secrets/supabase.json
  BASE_URL           public CloudFront base for asset links
"""

import json
import os
import sys
from dataclasses import dataclass
from typing import Callable, Self

import boto3
import psycopg
import yaml
from psycopg.types.json import Json

s3 = boto3.client('s3')

ASSET_PREFIX = 'exercises/exercises/'  # processed assets live here


def list_assets(bucket: str) -> list[str]:
    paginator = s3.get_paginator('list_objects_v2')
    return [
        item['Key']
        for page in paginator.paginate(Bucket=bucket, Prefix=ASSET_PREFIX)
        for item in page.get('Contents', [])
    ]


def sort_assets(keys: list[str], make_link: Callable[[str], str]) -> dict:
    by_name: dict[str, dict] = {}
    for key in keys:
        parts = key.split('/')
        # expect: exercises/exercises/<name>/<asset_type>.<ext>
        if len(parts) != 4:
            continue
        _, _, name, filename = parts
        if filename.startswith('asset'):
            by_name.setdefault(name, {})['asset'] = {'link': make_link(key)}
        elif filename.startswith('thumbnail'):
            by_name.setdefault(name, {})['thumbnail'] = {'link': make_link(key)}
    return by_name


@dataclass
class MuscleRole:
    groups: list[str]
    ids: list[str]

    @classmethod
    def parse(cls, source: dict) -> Self:
        return cls(groups=source.get('groups', []), ids=source.get('ids', []))

    def to_dict(self) -> dict:
        return {'groups': self.groups, 'ids': self.ids}


@dataclass
class Muscles:
    primary: MuscleRole
    secondary: MuscleRole

    @classmethod
    def parse(cls, source: dict | None) -> Self | None:
        if source is None:
            return None
        return cls(
            primary=MuscleRole.parse(source.get('primary', {})),
            secondary=MuscleRole.parse(source.get('secondary', {})),
        )

    def to_dict(self) -> dict:
        return {'primary': self.primary.to_dict(), 'secondary': self.secondary.to_dict()}


@dataclass
class ExerciseLocalization:
    exercise_name: str
    instructions: str | None
    fallback_to: str | None

    @classmethod
    def parse(cls, source: dict) -> Self:
        return cls(
            exercise_name=source.get('name'),
            instructions=source.get('instructions'),
            fallback_to=source.get('fallback_to'),
        )

    def is_concrete(self) -> bool:
        return self.fallback_to is None and self.exercise_name is not None


@dataclass
class Exercise:
    name: str
    category: str
    target: str
    muscles: Muscles | None
    localizations: dict[str, ExerciseLocalization]
    fallback: str

    @classmethod
    def parse(cls, source: dict, name: str, global_fallback: str) -> Self:
        return cls(
            name=name,
            category=source['category'],
            target=source['target'],
            muscles=Muscles.parse(source.get('muscles')),
            localizations={
                locale: ExerciseLocalization.parse(loc)
                for locale, loc in source.get('i18n', {}).items()
            },
            fallback=source.get('fallback') or global_fallback,
        )

    def fallback_localization(self) -> ExerciseLocalization:
        loc = self.localizations.get(self.fallback)
        if loc is None or not loc.is_concrete():
            raise ValueError(f'exercise {self.name!r}: fallback locale {self.fallback!r} missing concrete localization')
        return loc


@dataclass
class Library:
    version: str
    locales: list[str]
    exercises: dict[str, Exercise]
    fallback_to: str

    @classmethod
    def parse(cls, source: dict) -> Self:
        fallback_to = source['fallback_to_default']
        return cls(
            version=source['version'],
            locales=source['locales'],
            fallback_to=fallback_to,
            exercises={
                key: Exercise.parse(ex, key, global_fallback=fallback_to)
                for key, ex in source['exercises'].items()
            },
        )


def fetch_db_creds(secrets_bucket: str) -> dict:
    obj = s3.get_object(Bucket=secrets_bucket, Key='secrets/supabase.json')
    return json.loads(obj['Body'].read())


def get_source() -> dict:
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, '..', 'content', 'exercise_library.yml'), 'r') as f:
        return yaml.safe_load(f)


UPSERT_EXERCISE = '''
INSERT INTO exercises (name, category, target, instructions, asset, thumbnail, muscles, archived)
VALUES (%s, %s, %s, %s, %s, %s, %s, false)
ON CONFLICT (name) WHERE user_id IS NULL
DO UPDATE SET
    category = EXCLUDED.category,
    target = EXCLUDED.target,
    instructions = EXCLUDED.instructions,
    asset = EXCLUDED.asset,
    thumbnail = EXCLUDED.thumbnail,
    muscles = EXCLUDED.muscles,
    archived = false
RETURNING id
'''

UPSERT_TRANSLATION = '''
INSERT INTO exercise_translations (exercise_id, locale, name, instructions)
VALUES (%s, %s, %s, %s)
ON CONFLICT (exercise_id, locale)
DO UPDATE SET name = EXCLUDED.name, instructions = EXCLUDED.instructions
'''

ARCHIVE_MISSING = '''
UPDATE exercises
SET archived = true
WHERE user_id IS NULL AND name <> ALL(%s) AND archived = false
'''


def sync(library: Library, sorted_assets: dict, conn: psycopg.Connection) -> tuple[int, int, int]:
    upserted = 0
    translations = 0
    with conn.cursor() as cur:
        for name, exercise in library.exercises.items():
            asset = sorted_assets.get(name) or {}
            fallback = exercise.fallback_localization()

            cur.execute(UPSERT_EXERCISE, (
                name,
                exercise.category,
                exercise.target,
                fallback.instructions,
                Json(asset.get('asset')) if asset.get('asset') else None,
                Json(asset.get('thumbnail')) if asset.get('thumbnail') else None,
                Json(exercise.muscles.to_dict()) if exercise.muscles else None,
            ))
            exercise_id = cur.fetchone()[0]
            upserted += 1

            for locale, loc in exercise.localizations.items():
                if locale == exercise.fallback or not loc.is_concrete():
                    continue
                cur.execute(UPSERT_TRANSLATION, (exercise_id, locale, loc.exercise_name, loc.instructions))
                translations += 1

        cur.execute(ARCHIVE_MISSING, (list(library.exercises.keys()),))
        archived = cur.rowcount
    return upserted, translations, archived


def main():
    content_bucket = os.environ['CONTENT_BUCKET']
    secrets_bucket = os.environ['SECRETS_BUCKET']
    base_url = os.environ['BASE_URL']

    print(f'>> Reading source')
    library = Library.parse(get_source())

    print(f'>> Listing assets in s3://{content_bucket}/{ASSET_PREFIX}')
    keys = list_assets(content_bucket)
    sorted_assets = sort_assets(keys, make_link=lambda k: f'{base_url}/{k}')
    print(f'   {len(sorted_assets)} exercises have assets')

    print(f'>> Fetching DB credentials from s3://{secrets_bucket}/secrets/supabase.json')
    creds = fetch_db_creds(secrets_bucket)

    print(f'>> Connecting to {creds["host"]}:{creds["port"]}')
    with psycopg.connect(
        host=creds['host'],
        port=int(creds['port']),
        user=creds['user'],
        password=creds['password'],
        dbname=creds.get('database', 'heart'),
        sslmode='require',
    ) as conn:
        upserted, translations, archived = sync(library, sorted_assets, conn)

    print(f'>> Done: {upserted} exercises upserted, {translations} translations, {archived} archived')


if __name__ == '__main__':
    main()

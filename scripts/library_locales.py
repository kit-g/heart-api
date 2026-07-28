"""
Sync the exercise library from content/exercise_library.yml to Postgres.

Reads:
  - Source YAML: ../content/exercise_library.yml
  - Supabase creds: s3://SECRETS_BUCKET/secrets/supabase.json

Writes:
  - exercises (global, user_id IS NULL) — fallback locale fields, muscles, movement
  - exercise_translations — one row per non-fallback locale that has its own name/instructions
  - Archives any global exercise not in the source YAML.

The exercises.asset / .thumbnail columns are NOT touched here — the assets
pipeline (S3 exercise-uploads/ -> heart-assets Lambda -> API /events) is the
sole writer of those, link + dimensions included. This script must never
write them, or it would clobber the pipeline's rows with nulls.

Env:
  SECRETS_BUCKET     static bucket holding secrets/supabase.json
"""

import json
import os
from dataclasses import dataclass
from typing import Self

import boto3
import psycopg
import yaml
from psycopg.types.json import Json

s3 = boto3.client('s3')


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
class Movement:
    """Movement pattern + load attributes; exercises sharing a group are swappable.

    Parsed from the snake_cased YAML (that vocabulary is the content schema's own)
    and written to Postgres camelCased, so the blob is already in its API wire form
    and every read path can ship the column verbatim. Converting here rather than
    per-read is the whole point: this data is static content that changes only when
    the sync runs, so camelCasing it on every library read recomputed a constant
    (measured at ~20ms per full-library query, ~85% of it).

    exercises.movement is therefore camelCase in the database. That matches
    profiles.settings, which the client writes camelCased for the same reason: the
    snake_case convention governs column names, not the contents of a jsonb blob.
    """

    groups: list[str]
    axial_load: str
    stability: str
    unilateral: bool
    impact: str
    skill: str

    @classmethod
    def parse(cls, source: dict | None) -> Self | None:
        if source is None:
            return None
        return cls(
            groups=source.get('groups', []),
            axial_load=source.get('axial_load', 'none'),
            stability=source.get('stability', 'free'),
            unilateral=source.get('unilateral', False),
            impact=source.get('impact', 'none'),
            skill=source.get('skill', 'low'),
        )

    def to_dict(self) -> dict:
        """The camelCased wire/storage form. Keys must match Movement.fromJson in
        shared/heart_models — a mismatch does not fail loudly, it silently reads
        as the field's default."""
        return {
            'groups': self.groups,
            'axialLoad': self.axial_load,
            'stability': self.stability,
            'unilateral': self.unilateral,
            'impact': self.impact,
            'skill': self.skill,
        }


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
    movement: Movement | None
    localizations: dict[str, ExerciseLocalization]
    fallback: str

    @classmethod
    def parse(cls, source: dict, name: str, global_fallback: str) -> Self:
        return cls(
            name=name,
            category=source['category'],
            target=source['target'],
            muscles=Muscles.parse(source.get('muscles')),
            movement=Movement.parse(source.get('movement')),
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
INSERT INTO exercises (name, category, target, instructions, muscles, movement, archived)
VALUES (%s, %s, %s, %s, %s, %s, false)
ON CONFLICT (name) WHERE user_id IS NULL
DO UPDATE SET
    category = EXCLUDED.category,
    target = EXCLUDED.target,
    instructions = EXCLUDED.instructions,
    muscles = EXCLUDED.muscles,
    movement = EXCLUDED.movement,
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


def sync(library: Library, conn: psycopg.Connection) -> tuple[int, int, int]:
    upserted = 0
    translations = 0
    with conn.cursor() as cur:
        for name, exercise in library.exercises.items():
            fallback = exercise.fallback_localization()

            cur.execute(UPSERT_EXERCISE, (
                name,
                exercise.category,
                exercise.target,
                fallback.instructions,
                Json(exercise.muscles.to_dict()) if exercise.muscles else None,
                Json(exercise.movement.to_dict()) if exercise.movement else None,
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
    secrets_bucket = os.environ['SECRETS_BUCKET']

    print(f'>> Reading source')
    library = Library.parse(get_source())

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
        upserted, translations, archived = sync(library, conn)

    print(f'>> Done: {upserted} exercises upserted, {translations} translations, {archived} archived')


if __name__ == '__main__':
    main()

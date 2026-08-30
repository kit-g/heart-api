"""
Sync the exercise library from content/exercise_library.yml to Postgres.

Reads:
  - Source YAML: ../content/exercise_library.yml
  - Locale overlays: ../content/i18n/<locale>.yml (merged into the master's
    i18n maps before parsing; the fallback locale lives in the master itself)
  - Supabase creds: s3://SECRETS_BUCKET/secrets/supabase.json

Writes:
  - exercises (global, user_id IS NULL) — fallback locale fields, muscles, movement
  - exercise_translations — one row per non-fallback locale that has its own
    name/instructions; rows the source no longer defines are pruned (archived
    exercises keep theirs)
  - Archives any global exercise not in the source YAML.

The exercises.asset / .thumbnail columns are NOT touched here — the assets
pipeline (S3 exercise-uploads/ -> heart-assets Lambda -> API /events) is the
sole writer of those, link + dimensions included. This script must never
write them, or it would clobber the pipeline's rows with nulls.

Env:
  SECRETS_BUCKET     static bucket holding secrets/supabase.json
"""

import hashlib
import json
import os
from dataclasses import dataclass
from typing import Self

import boto3
import psycopg
import yaml
from psycopg.types.json import Json

# A truncated or half-edited YAML must not archive the whole library: the sync
# aborts (rolling the transaction back) when it would archive more than this
# many exercises in one run. A deliberate mass-archive raises the cap via env:
#   MAX_ARCHIVED=100 python scripts/library_locales.py
MAX_ARCHIVED_DEFAULT = 10


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
class Health:
    """Health store representation: the canonical activity type a session of the
    exercise is written to HealthKit / Health Connect as.

    Same wire discipline as Movement, applied to the value rather than the keys:
    the YAML spells activities snake_case (the content schema's own vocabulary,
    `cycling_indoor`), the database stores them camelCased (`cyclingIndoor`) so
    the blob is already in its API wire form and read paths ship it verbatim.

    None is the common case -- the client derives the activity from category --
    and cross_training / mixed_cardio never appear here: they are session-level,
    derived by the client, and the schema enum deliberately excludes them.
    """

    activity: str

    @classmethod
    def parse(cls, source: dict | None) -> Self | None:
        if source is None:
            return None
        return cls(activity=source['activity'])

    def to_dict(self) -> dict:
        """The camelCased wire/storage form. Keys and value spelling must match
        Health.fromJson / HealthActivity.fromString in shared/heart_models --
        which throws on a snake_cased value, so a regression here fails the app
        read loudly rather than mislabeling a workout."""
        head, *tail = self.activity.split('_')
        return {'activity': head + ''.join(word.capitalize() for word in tail)}


@dataclass
class ExerciseLocalization:
    exercise_name: str
    instructions: str | None
    fallback_to: str | None
    # a human has reviewed this locale's copy; false is the schema default and
    # marks machine-authored copy the client labels as such (the spark icon)
    validated: bool

    @classmethod
    def parse(cls, source: dict) -> Self:
        return cls(
            exercise_name=source.get('name'),
            instructions=source.get('instructions'),
            fallback_to=source.get('fallback_to'),
            validated=source.get('validated', False),
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
    health: Health | None
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
            health=Health.parse(source.get('health')),
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
    # Client construction needs AWS config (region/credentials), so it must not
    # happen at import time — validate_library.py imports this module without any.
    s3 = boto3.client('s3')
    obj = s3.get_object(Bucket=secrets_bucket, Key='secrets/supabase.json')
    return json.loads(obj['Body'].read())


def content_dir() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, '..', 'content')


def source_digest(name: str, instructions: str | None) -> str:
    """Fingerprint of the fallback-locale copy a translation was made from.

    Stored on overlay entries as `source_digest`; when the fallback copy later
    changes, the stored digest no longer matches and the coverage report
    (validate_library.py) flags the translation as stale. Bookkeeping only —
    stripped during merge, never synced to the database.
    """
    payload = f'{name}\n\n{instructions or ""}'.encode()
    return hashlib.sha256(payload).hexdigest()[:12]


# Overlay keys that exist for the translation workflow, not for the library
# document itself; merge_overlays drops them so the merged document stays
# valid against the master schema's closed i18nEntry.
OVERLAY_BOOKKEEPING_KEYS = frozenset({'source_digest'})


def load_overlays(content: str | None = None) -> list[tuple[str, dict]]:
    """All content/i18n/<locale>.yml files as (filename, document) pairs."""
    i18n_dir = os.path.join(content or content_dir(), 'i18n')
    if not os.path.isdir(i18n_dir):
        return []
    overlays = []
    for filename in sorted(os.listdir(i18n_dir)):
        if not filename.endswith('.yml'):
            continue
        with open(os.path.join(i18n_dir, filename)) as f:
            overlays.append((filename, yaml.safe_load(f)))
    return overlays


def merge_overlays(master: dict, overlays: list[tuple[str, dict]]) -> dict:
    """Fold per-locale overlay files into the master document's i18n maps.

    The master owns the structure and the fallback locale; every other locale
    lives in its own overlay so the master file doesn't multiply in size per
    locale and translation diffs stay isolated. Mutates and returns `master`.

    Collects every problem before failing, mirroring validate_library.py:
    a translator fixing an overlay should see the full list, not the first hit.
    """
    declared = set(master.get('locales', []))
    fallback = master.get('fallback_to_default')
    problems = []

    for filename, overlay in overlays:
        locale = (overlay or {}).get('locale')
        stem = os.path.splitext(filename)[0]
        if locale != stem:
            problems.append(f'i18n/{filename}: declares locale {locale!r}, expected {stem!r} from its filename')
            continue
        if locale not in declared:
            problems.append(f'i18n/{filename}: locale {locale!r} is not declared in the master `locales` list')
            continue
        if locale == fallback:
            problems.append(f'i18n/{filename}: {locale!r} is the fallback locale and lives in the master file')
            continue

        for name, entry in (overlay.get('exercises') or {}).items():
            exercise = master['exercises'].get(name)
            if exercise is None:
                problems.append(f'i18n/{filename}: unknown exercise {name!r}')
                continue
            i18n = exercise.setdefault('i18n', {})
            if locale in i18n:
                problems.append(f'i18n/{filename}: exercise {name!r} already defines {locale!r} in the master file')
                continue
            i18n[locale] = {k: v for k, v in entry.items() if k not in OVERLAY_BOOKKEEPING_KEYS}

    if problems:
        raise ValueError('overlay merge failed:\n' + '\n'.join(f'  {p}' for p in problems))
    return master


def get_source() -> dict:
    content = content_dir()
    with open(os.path.join(content, 'exercise_library.yml')) as f:
        master = yaml.safe_load(f)
    return merge_overlays(master, load_overlays(content))


UPSERT_EXERCISE = '''
INSERT INTO exercises (name, category, target, instructions, muscles, movement, health, validated, archived)
VALUES (%s, %s, %s, %s, %s, %s, %s, %s, false)
ON CONFLICT (name) WHERE user_id IS NULL
DO UPDATE SET
    category = EXCLUDED.category,
    target = EXCLUDED.target,
    instructions = EXCLUDED.instructions,
    muscles = EXCLUDED.muscles,
    movement = EXCLUDED.movement,
    health = EXCLUDED.health,
    validated = EXCLUDED.validated,
    archived = false
RETURNING id
'''

UPSERT_TRANSLATION = '''
INSERT INTO exercise_translations (exercise_id, locale, name, instructions, validated)
VALUES (%s, %s, %s, %s, %s)
ON CONFLICT (exercise_id, locale)
DO UPDATE SET name = EXCLUDED.name, instructions = EXCLUDED.instructions, validated = EXCLUDED.validated
'''

ARCHIVE_MISSING = '''
UPDATE exercises
SET archived = true
WHERE user_id IS NULL AND name <> ALL(%s) AND archived = false
'''

# A translation the source no longer defines must stop being served, or it
# lingers with stale copy forever. Scoped to the exercises this run touched:
# archived exercises (absent from the source) keep whatever translations they
# had when they shipped.
PRUNE_TRANSLATIONS = '''
DELETE FROM exercise_translations t
WHERE t.exercise_id = ANY(%s::uuid[])
  AND NOT EXISTS (
    SELECT 1 FROM unnest(%s::uuid[], %s::text[]) AS kept(exercise_id, locale)
    WHERE kept.exercise_id = t.exercise_id AND kept.locale = t.locale
  )
'''


def sync(library: Library, conn: psycopg.Connection) -> tuple[int, int, int, int]:
    upserted = 0
    translations = 0
    exercise_ids = []
    kept = []  # (exercise_id, locale) pairs the source still defines
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
                Json(exercise.health.to_dict()) if exercise.health else None,
                fallback.validated,
            ))
            exercise_id = cur.fetchone()[0]
            exercise_ids.append(exercise_id)
            upserted += 1

            for locale, loc in exercise.localizations.items():
                if locale == exercise.fallback or not loc.is_concrete():
                    continue
                cur.execute(
                    UPSERT_TRANSLATION, (
                        exercise_id, locale, loc.exercise_name, loc.instructions, loc.validated
                    )
                )
                kept.append((exercise_id, locale))
                translations += 1

        cur.execute(
            PRUNE_TRANSLATIONS, (
                exercise_ids,
                [exercise_id for exercise_id, _ in kept],
                [locale for _, locale in kept],
            )
        )
        pruned = cur.rowcount

        cur.execute(ARCHIVE_MISSING, (list(library.exercises.keys()),))
        archived = cur.rowcount

        max_archived = int(os.environ.get('MAX_ARCHIVED', MAX_ARCHIVED_DEFAULT))
        if archived > max_archived:
            raise RuntimeError(
                f'sync would archive {archived} exercises (cap: {max_archived}) — '
                f'usually a truncated or half-edited exercise_library.yml. '
                f'If intended, re-run with MAX_ARCHIVED={archived}.'
            )
    return upserted, translations, pruned, archived


def connect() -> psycopg.Connection:
    """
    CI and deploys set SECRETS_BUCKET and get Supabase credentials from S3.
    Without it, connect via the standard PG* env vars, defaulting to the local
    dev database — the `make db-seed` path. The split is deliberate: local
    seeding must be possible with zero AWS involvement, and forgetting the env
    var must land you on localhost, never on the shared instance.
    """
    if bucket := os.environ.get('SECRETS_BUCKET'):
        print(f'>> Fetching DB credentials from s3://{bucket}/secrets/supabase.json')
        creds = fetch_db_creds(bucket)
        print(f'>> Connecting to {creds["host"]}:{creds["port"]}')
        return psycopg.connect(
            host=creds['host'],
            port=int(creds['port']),
            user=creds['user'],
            password=creds['password'],
            dbname=creds.get('database', 'heart'),
            sslmode='require',
        )

    host = os.environ.get('PGHOST', 'localhost')
    dbname = os.environ.get('PGDATABASE', 'heart')
    print(f'>> Connecting to {host}/{dbname} (local; user/port/password from PG* env)')
    return psycopg.connect(host=host, dbname=dbname)


def main():
    print('>> Reading source')
    library = Library.parse(get_source())

    with connect() as conn:
        upserted, translations, pruned, archived = sync(library, conn)

    print(
        f'>> Done: {upserted} exercises upserted, {translations} translations '
        f'({pruned} pruned), {archived} archived'
    )


if __name__ == '__main__':
    main()

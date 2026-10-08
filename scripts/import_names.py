"""
Load an exporting app's exercise titles, in every language it writes, into
import_names — the table the CSV importer resolves a title through before
matching it against the library.

Reads:
  - the app's catalog, a local path or an s3:// URI (--catalog). Hevy's is
    its own catalog with each title in all 17 app languages, kept in the dev
    account's static bucket under imports/hevy/ and never in this repository.
  - Postgres: as library_locales.connect() — Supabase credentials from S3
    when SECRETS_BUCKET is set, the local PG* env otherwise.

Writes:
  - import_names (source, title, name): one row per translated title, upserted;
    rows for the source that the catalog no longer carries are pruned. Titles
    differing only in case share one row, as the lookup is case-insensitive;
    the loader refuses a catalog where such a pair names two exercises.

A title shared by two catalog exercises (Hevy has eleven) resolves to the
first live one in catalog order; the choice is printed, and the user can
re-point a wrongly guessed history afterwards (heart-api#140).

    uv run scripts/import_names.py --source hevy \\
        --catalog s3://583168578067-ca-central-1-static/imports/hevy/2026-10-04/catalog/hevy-catalog-i18n.json
"""

import argparse
import json
from pathlib import Path

import psycopg
from library_locales import connect

UPSERT = """
INSERT INTO import_names (source, title, name)
VALUES (%(source)s, %(title)s, %(name)s)
ON CONFLICT (source, lower(title)) DO UPDATE SET title = excluded.title, name = excluded.name
"""

# the database folds both sides: its lower() and Python's disagree on a few
# characters, and a title pruned for that reason would vanish on every run
PRUNE = """
DELETE FROM import_names
WHERE source = %(source)s
  AND lower(title) NOT IN (SELECT lower(t) FROM unnest(%(titles)s::text[]) t)
"""

HEVY_LANGUAGES = (
    'ar',
    'ca',
    'de',
    'es',
    'fr',
    'hi',
    'it',
    'ja',
    'ko',
    'pl',
    'pt',
    'pt_br',
    'ru',
    'tr',
    'zh_cn',
    'zh_tw',
)


def hevy_names(catalog: list[dict]) -> tuple[dict[str, str], list[tuple[str, list[str], str]]]:
    """
    Translated title -> English title over Hevy's catalog (entries with
    `title`, `is_archived` and `<lang>_title` fields). A title equal to any
    English title is already canonical and left out. Returns the table and the
    ambiguous titles with their candidates and the pick.
    """
    english = {entry['title'] for entry in catalog}
    carriers: dict[str, list[int]] = {}
    for i, entry in enumerate(catalog):
        for lang in HEVY_LANGUAGES:
            title = entry.get(f'{lang}_title')
            if title and title not in english:
                carriers.setdefault(title, []).append(i)
    table: dict[str, str] = {}
    ambiguous: list[tuple[str, list[str], str]] = []
    for title, indices in carriers.items():
        names = sorted({catalog[i]['title'] for i in indices})
        pick = min(indices, key=lambda i: (catalog[i]['is_archived'], i))
        table[title] = catalog[pick]['title']
        if len(names) > 1:
            ambiguous.append((title, names, catalog[pick]['title']))
    return table, ambiguous


def case_conflicts(names: dict[str, str]) -> list[tuple[str, str]]:
    """Pairs of titles equal but for case that resolve to different names."""
    seen: dict[str, tuple[str, str]] = {}
    conflicts: list[tuple[str, str]] = []
    for title, name in names.items():
        folded = title.casefold()
        if folded in seen and seen[folded][1] != name:
            conflicts.append((seen[folded][0], title))
        seen.setdefault(folded, (title, name))
    return conflicts


def read_catalog(location: str) -> list[dict]:
    if location.startswith('s3://'):
        import boto3

        bucket, key = location[5:].split('/', 1)
        body = boto3.client('s3').get_object(Bucket=bucket, Key=key)['Body'].read()
        return json.loads(body)
    return json.loads(Path(location).read_text())


def load(conn: psycopg.Connection, source: str, names: dict[str, str]) -> tuple[int, int]:
    """Upserts [names] for [source] and prunes the rest, in one transaction."""
    with conn.cursor() as cur, conn.transaction():
        cur.executemany(UPSERT, [{'source': source, 'title': t, 'name': n} for t, n in names.items()])
        cur.execute(PRUNE, {'source': source, 'titles': list(names)})
        pruned = cur.rowcount
    return len(names), pruned


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--source', choices=['hevy'], required=True)
    parser.add_argument('--catalog', required=True, help='local path or s3:// URI of the catalog JSON')
    args = parser.parse_args()

    print(f'>> Reading {args.catalog}')
    names, ambiguous = hevy_names(read_catalog(args.catalog))
    for title, candidates, pick in ambiguous:
        print(f'   {title!r} is {" / ".join(candidates)}: taking {pick}')
    if conflicts := case_conflicts(names):
        raise SystemExit(f'titles equal but for case name different exercises: {conflicts}')

    with connect() as conn:
        loaded, pruned = load(conn, args.source, names)
    print(f'>> Done: {loaded} titles for {args.source}, {pruned} pruned')


if __name__ == '__main__':
    main()

"""
Validate content/exercise_library.yml before a sync touches any database.

Two layers:
  1. JSON Schema — the YAML against content/exercise_library_schema.json.
  2. The sync's own parser — Library.parse plus the per-exercise concrete-fallback
     rule, so anything that would abort library_locales.py mid-run fails here,
     with every problem listed instead of the first one hit.

Run:
  uv run python scripts/validate_library.py
"""

import json
import os
import sys

import jsonschema

from library_locales import Library, get_source

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(HERE, '..', 'content', 'exercise_library_schema.json')


def main() -> int:
    with open(SCHEMA) as f:
        schema = json.load(f)

    source = get_source()

    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(source), key=lambda e: list(map(str, e.absolute_path)))
    for error in errors:
        path = '/'.join(str(p) for p in error.absolute_path) or '<root>'
        print(f'schema: {path}: {error.message}', file=sys.stderr)
    if errors:
        return 1

    library = Library.parse(source)
    problems = []
    for exercise in library.exercises.values():
        try:
            exercise.fallback_localization()
        except ValueError as e:
            problems.append(str(e))
    for problem in problems:
        print(f'content: {problem}', file=sys.stderr)
    if problems:
        return 1

    print(f'>> OK: version {library.version}, {len(library.exercises)} exercises, locales {library.locales}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

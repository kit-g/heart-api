"""
Fold content/exercise_movement.yml into content/exercise_library.yml.

The sidecar is the authoring surface — small enough to review in one pass. The
master is the source of truth the DB sync reads, so the annotation has to land
there eventually. This script does that mechanically: round-trip YAML, so the
block-literal instructions, key order and quoting in the 15k-line master survive
untouched, and the diff shows only the added `movement` blocks.

Validates before writing, against the enums in exercise_library_schema.json:
  - every sidecar key names a real exercise (and vice versa, as a warning)
  - groups / axial_load / stability / impact / skill are legal values
  - no group has a single member, which almost always means a typo

Run:
  uv run python scripts/movement_merge.py --check   # validate, write nothing
  uv run python scripts/movement_merge.py
"""

import argparse
import json
import os
import sys
from collections import defaultdict

from ruamel.yaml import YAML

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, '..', 'content')
MASTER = os.path.join(CONTENT, 'exercise_library.yml')
SIDECAR = os.path.join(CONTENT, 'exercise_movement.yml')
SCHEMA = os.path.join(CONTENT, 'exercise_library_schema.json')

# Groups whose only member has no substitute anywhere in the library. Anything
# else landing at size 1 is a mistake worth failing on.
KNOWN_SINGLETONS = {'knee_extension', 'hip_abduction', 'hip_adduction'}

# Where `movement` is inserted in each exercise mapping, to match the property
# order declared in the schema.
INSERT_AFTER = 'target'


def load_schema_enums() -> dict[str, set[str]]:
    with open(SCHEMA) as f:
        defs = json.load(f)['$defs']
    movement = defs['movement']['properties']
    return {
        'groups': set(defs['movementGroupList']['items']['enum']),
        'axial_load': set(movement['axial_load']['enum']),
        'stability': set(movement['stability']['enum']),
        'impact': set(movement['impact']['enum']),
        'skill': set(movement['skill']['enum']),
    }


def validate(annotations: dict, exercises: dict, enums: dict[str, set[str]]) -> list[str]:
    errors = []

    for name, record in annotations.items():
        if name not in exercises:
            errors.append(f'{name}: not an exercise in the library')
            continue

        groups = record.get('groups')
        if not groups:
            errors.append(f'{name}: missing or empty groups')
        else:
            for group in groups:
                if group not in enums['groups']:
                    errors.append(f'{name}: unknown group {group!r}')
            if len(set(groups)) != len(groups):
                errors.append(f'{name}: duplicate entries in groups')

        for field in ('axial_load', 'stability', 'impact', 'skill'):
            value = record.get(field)
            if value is not None and value not in enums[field]:
                errors.append(f'{name}: {field}={value!r} not one of {sorted(enums[field])}')

        unilateral = record.get('unilateral')
        if unilateral is not None and not isinstance(unilateral, bool):
            errors.append(f'{name}: unilateral must be a boolean, got {unilateral!r}')

        unknown = set(record) - {'groups', 'axial_load', 'stability',
                                 'unilateral', 'impact', 'skill'}
        if unknown:
            errors.append(f'{name}: unknown fields {sorted(unknown)}')

    by_group = defaultdict(list)
    for name, record in annotations.items():
        for group in record.get('groups') or []:
            by_group[group].append(name)
    for group, members in sorted(by_group.items()):
        if len(members) == 1 and group not in KNOWN_SINGLETONS:
            errors.append(f'group {group!r} has one member ({members[0]}) — '
                          f'no substitutes can be offered; merge it or add to KNOWN_SINGLETONS')

    return errors


def build_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    yaml.indent(mapping=2, sequence=4, offset=2)
    return yaml


def merge(exercises, annotations) -> tuple[int, int]:
    added = updated = 0
    for name, record in annotations.items():
        exercise = exercises[name]
        if 'movement' in exercise:
            exercise['movement'] = record
            updated += 1
            continue
        keys = list(exercise.keys())
        position = keys.index(INSERT_AFTER) + 1 if INSERT_AFTER in keys else len(keys)
        exercise.insert(position, 'movement', record)
        added += 1
    return added, updated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true',
                        help='validate only; do not modify the master')
    args = parser.parse_args()

    yaml = build_yaml()
    with open(MASTER) as f:
        library = yaml.load(f)
    with open(SIDECAR) as f:
        annotations = yaml.load(f) or {}

    exercises = library['exercises']
    enums = load_schema_enums()

    errors = validate(annotations, exercises, enums)
    if errors:
        print(f'{len(errors)} validation error(s):', file=sys.stderr)
        for error in errors:
            print(f'  {error}', file=sys.stderr)
        return 1

    missing = [n for n in exercises if n not in annotations]
    if missing:
        print(f'note: {len(missing)} exercise(s) have no movement record and will '
              f'offer no substitutes: {", ".join(missing)}')

    if args.check:
        print(f'ok: {len(annotations)} movement records valid')
        return 0

    added, updated = merge(exercises, annotations)
    with open(MASTER, 'w') as f:
        yaml.dump(library, f)
    print(f'merged into {MASTER}: {added} added, {updated} updated')
    return 0


if __name__ == '__main__':
    sys.exit(main())

"""
Check and render "go easy on" (heart-api#236): content/go_easy.yml, the map
from a body area or a movement to the exercises that are harder on it and
kinder to it, served as static/go-easy. The user's own list never leaves the
phone; this is only the mapping, so it can change without an app release.

Run:
  uv run python scripts/go_easy_content.py                     # check
  uv run python scripts/go_easy_content.py --render out.json   # check, then render
"""

import argparse
import json
import os
import sys

import yaml
from library_locales import content_dir

SOURCE = os.path.join(content_dir(), 'go_easy.yml')
LIBRARY = os.path.join(content_dir(), 'exercise_library.yml')
SCHEMA = os.path.join(content_dir(), 'exercise_library_schema.json')

PREDICATE_KEYS = {'groups', 'axial_load', 'impact', 'stability', 'category'}


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def vocabulary(library: dict) -> dict[str, set]:
    """What each predicate key can name: the library's own values."""
    exercises = library['exercises'].values()
    movement = [e.get('movement') or {} for e in exercises]
    return {
        'groups': {g for m in movement for g in m.get('groups') or []},
        'axial_load': {'none', 'low', 'moderate', 'high'},
        'impact': {'none', 'low', 'high'},
        'stability': {'free', 'supported', 'machine'},
        'category': {e['category'] for e in exercises},
    }


def matches(predicate: dict, exercise: dict) -> bool:
    """Every key of [predicate] holds for [exercise]: one of its values."""
    movement = exercise.get('movement') or {}
    for key, values in predicate.items():
        if key == 'groups':
            if not set(values) & set(movement.get('groups') or []):
                return False
        elif key == 'category':
            if exercise['category'] not in values:
                return False
        elif movement.get(key) not in values:
            return False
    return True


def check(document: dict, library: dict) -> list[str]:
    vocab = vocabulary(library)
    locales = document.get('locales') or []
    problems = []

    def copy(where, text):
        if not isinstance(text, dict) or not str(text.get('en') or '').strip():
            problems.append(f'{where}: needs an en text')
            return
        for locale in locales:
            if not str(text.get(locale) or '').strip():
                problems.append(f'{where}: missing {locale}')

    for key, text in (document.get('copy') or {}).items():
        copy(f'copy.{key}', text)
    for section in ('areas', 'movements'):
        for key, entry in (document.get(section) or {}).items():
            where = f'{section}.{key}'
            copy(f'{where}.name', entry.get('name'))
            copy(f'{where}.easier_on', entry.get('easier_on'))
            for field in ('easier', 'prefer'):
                predicates = entry.get(field) or []
                if field == 'easier' and not predicates:
                    problems.append(f'{where}: easier names what is harder on it')
                for at, predicate in enumerate(predicates):
                    if not isinstance(predicate, dict) or not predicate or set(predicate) - PREDICATE_KEYS:
                        problems.append(f'{where}.{field}[{at}]: a predicate on {sorted(PREDICATE_KEYS)}')
                        continue
                    # a list, always: the app reads one, and a bare string would
                    # match letter by letter
                    lists = {name: values for name, values in predicate.items() if isinstance(values, list) and values}
                    for name in set(predicate) - set(lists):
                        problems.append(f'{where}.{field}[{at}]: {name} must be a non-empty list')
                    for name, values in lists.items():
                        for value in values:
                            if value not in vocab[name]:
                                problems.append(f'{where}.{field}[{at}]: {name} {value!r} is not in the library')
                    if len(lists) < len(predicate):
                        continue
                    if not any(matches(predicate, e) for e in library['exercises'].values()):
                        problems.append(f'{where}.{field}[{at}]: matches no exercise')
    return problems


def render(document: dict) -> dict:
    locales = document['locales']

    def text(field: dict) -> dict:
        return {'en': field['en'], **{locale: field[locale] for locale in locales}}

    def entries(section: str) -> dict:
        return {
            key: {
                'name': text(entry['name']),
                'easierOn': text(entry['easier_on']),
                'easier': entry['easier'],
                'prefer': entry.get('prefer') or [],
            }
            for key, entry in document[section].items()
        }

    return {
        'version': document['version'],
        'copy': {key: text(value) for key, value in document['copy'].items()},
        'areas': entries('areas'),
        'movements': entries('movements'),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--render', metavar='PATH', help='write the static/go-easy JSON here')
    args = parser.parse_args()
    document = load(SOURCE)
    problems = check(document, load(LIBRARY))
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f'{len(document["areas"])} areas, {len(document["movements"])} movements, no problems')
    if args.render:
        with open(args.render, 'w', encoding='utf-8') as f:
            json.dump(render(document), f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f'rendered {args.render}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

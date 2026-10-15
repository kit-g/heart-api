"""
Check and render the balance pairs (heart-api#270): content/balance_pairs.yml,
opposing movement patterns the app sets against each other over recent weeks,
served as static/balance so the pairs change without an app release. Counts
only: the content names the sides and carries no verdict or threshold.

Run:
  uv run python scripts/balance_content.py                     # check
  uv run python scripts/balance_content.py --render out.json   # check, then render
"""

import argparse
import json
import os
import re
import sys

import yaml
from library_locales import content_dir

SOURCE = os.path.join(content_dir(), 'balance_pairs.yml')
LIBRARY = os.path.join(content_dir(), 'exercise_library.yml')

KEY = re.compile(r'^[a-z][a-z0-9_]{0,63}$')


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def patterns(library: dict) -> set[str]:
    """The library's movement patterns: what a side can count."""
    return {g for e in library['exercises'].values() for g in (e.get('movement') or {}).get('groups') or []}


def check(document: dict, library: dict) -> list[str]:
    known = patterns(library)
    locales = document.get('locales') or []
    problems = []

    def copy(where, text):
        if not isinstance(text, dict) or not str(text.get('en') or '').strip():
            problems.append(f'{where}: needs an en text')
            return
        for locale in locales:
            if not str(text.get(locale) or '').strip():
                problems.append(f'{where}: missing {locale}')

    pairs = document.get('pairs') or []
    if not pairs:
        problems.append('pairs: one pair or more')
    seen = set()
    for at, pair in enumerate(pairs):
        key = pair.get('key')
        where = f'pairs[{at}]' if not isinstance(key, str) else key
        if not isinstance(key, str) or not KEY.fullmatch(key) or key in seen:
            problems.append(f'{where}: key must be snake_case and unique')
        seen.add(key)
        sides = []
        for name in ('left', 'right'):
            side = pair.get(name)
            if not isinstance(side, dict):
                problems.append(f'{where}.{name}: a side is {{key, name, patterns}}')
                continue
            if extra := set(side) - {'key', 'name', 'patterns'}:
                problems.append(f'{where}.{name}: unknown {sorted(extra)}')
            if not isinstance(side.get('key'), str) or not KEY.fullmatch(side['key']):
                problems.append(f'{where}.{name}: key must be snake_case')
            copy(f'{where}.{name}.name', side.get('name'))
            listed = side.get('patterns')
            if not isinstance(listed, list) or not listed:
                problems.append(f'{where}.{name}: patterns is a non-empty list')
                continue
            for pattern in listed:
                if pattern not in known:
                    problems.append(f'{where}.{name}: {pattern!r} is not a library pattern')
            sides.append(side)
        if len(sides) == 2:
            if sides[0].get('key') == sides[1].get('key'):
                problems.append(f'{where}: its sides have the same key')
            # a set counted on both sides would weigh nothing either way
            if shared := set(sides[0]['patterns']) & set(sides[1]['patterns']):
                problems.append(f'{where}: {sorted(shared)} on both sides')
    return problems


def render(document: dict) -> dict:
    locales = document['locales']

    def text(field: dict) -> dict:
        return {'en': field['en'], **{locale: field[locale] for locale in locales}}

    def side(entry: dict) -> dict:
        return {'key': entry['key'], 'name': text(entry['name']), 'patterns': entry['patterns']}

    return {
        'version': document['version'],
        'pairs': [
            {'key': pair['key'], 'left': side(pair['left']), 'right': side(pair['right'])} for pair in document['pairs']
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--render', metavar='PATH', help='write the static/balance JSON here')
    args = parser.parse_args()
    document = load(SOURCE)
    problems = check(document, load(LIBRARY))
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f'{len(document["pairs"])} pairs, no problems')
    if args.render:
        with open(args.render, 'w', encoding='utf-8') as f:
            json.dump(render(document), f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f'rendered {args.render}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

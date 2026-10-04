"""
Validate content/exercise_library.yml and its locale overlays before a sync
touches any database.

Three layers:
  1. JSON Schema — each content/i18n/<locale>.yml against
     content/exercise_i18n_schema.json, then the merged document against
     content/exercise_library_schema.json.
  2. The sync's own parser — overlay merge plus Library.parse plus the
     per-exercise concrete-fallback rule, so anything that would abort
     library_locales.py mid-run fails here, with every problem listed instead
     of the first one hit.
  3. Search vocabulary — per served locale: an alias is never another
     exercise's name, a glossary word is not itself a word of the names (it
     would shadow it), and everything a glossary word stands for reaches some
     exercise.
  4. Coverage — per-locale translation counts, with missing and stale (the
     fallback copy changed since translation) entries. Informational by
     default: a new exercise must not break CI until every locale catches up.

Run:
  uv run python scripts/validate_library.py             # validate + summary
  uv run python scripts/validate_library.py --coverage  # also list each missing/stale exercise
"""

import json
import os
import re
import sys

import jsonschema
import yaml
from library_locales import Exercise, Library, content_dir, load_overlays, merge_overlays, source_digest

MASTER_SCHEMA = os.path.join(content_dir(), 'exercise_library_schema.json')
OVERLAY_SCHEMA = os.path.join(content_dir(), 'exercise_i18n_schema.json')


def validate_schema(document: dict, schema: dict, label: str) -> int:
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(document), key=lambda e: list(map(str, e.absolute_path)))
    for error in errors:
        path = '/'.join(str(p) for p in error.absolute_path) or '<root>'
        print(f'schema: {label}: {path}: {error.message}', file=sys.stderr)
    return len(errors)


# Mirrors searchNormalized in shared/heart_models (src/models/search.dart):
# the app matches in this form, so uniqueness and shadowing are checked in it.
_FOLDS = str.maketrans({
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'œ': 'oe',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
    'ё': 'е',
})


def search_words(s: str) -> list[str]:
    return re.sub(r'[^\w\s]|_', '', s.lower().translate(_FOLDS)).split()


def served(exercise: Exercise, locale: str, field: str):
    """What the library query serves for `field` in `locale`: the locale's own
    copy, then its base language's, then the fallback's — field by field."""
    for each in dict.fromkeys([locale, locale.split('_')[0]]):
        loc = exercise.localizations.get(each)
        if loc is not None and loc.is_concrete() and getattr(loc, field) is not None:
            return getattr(loc, field)
    return getattr(exercise.fallback_localization(), field)


def search_problems(library: Library, muscle_groups: set[str], muscle_ids: set[str]) -> list[str]:
    problems = []
    for locale in library.locales:
        names = set()
        full_names = {}
        aliases = []
        primaries = []
        for key, exercise in library.exercises.items():
            name = search_words(served(exercise, locale, 'exercise_name'))
            names.update(name)
            names.update(key.split('-'))
            full_names[' '.join(name)] = key
            aliases.extend((key, alias) for alias in served(exercise, locale, 'aliases') or [])
            if exercise.muscles:
                primaries.append(exercise.muscles.primary)

        # an alias shared by variants (rdl on the barbell and the dumbbell
        # Romanian deadlift) is the point; one that names another exercise
        # outright would send a lifter to the wrong one
        for key, alias in aliases:
            named = full_names.get(' '.join(search_words(alias)), key)
            if named != key:
                problems.append(f'{locale}: alias {alias!r} of {key} is the name of {named}')

        for word, term in library.resolved_glossary(locale).items():
            normalized = search_words(word)
            if len(normalized) != 1 or word != word.lower():
                problems.append(f'{locale}: glossary word {word!r} must be one lower-case word')
                continue
            if normalized[0] in names:
                problems.append(f'{locale}: glossary word {word!r} is a word of the names it would shadow')
            for phrase in term.get('words', []):
                if not all(any(part in name for name in names) for part in search_words(phrase)):
                    problems.append(f'{locale}: glossary word {word!r} stands for {phrase!r}, which no name has')
            for muscle in term.get('muscles', []):
                if muscle not in muscle_groups and not any(each.startswith(muscle) for each in muscle_ids):
                    problems.append(f'{locale}: glossary word {word!r} names {muscle!r}, not a muscle group or id')
                elif not any(
                    muscle in role.groups or any(each.startswith(muscle) for each in role.ids) for role in primaries
                ):
                    problems.append(f'{locale}: glossary word {word!r} names {muscle!r}, no exercise\'s primary muscle')
    return problems


def coverage(master: dict, overlays: list[tuple[str, dict]], detailed: bool) -> None:
    """Per-locale translation coverage against the declared `locales` list.

    A locale entry counts as translated when it is concrete (own name, no
    fallback_to) and stale when its stored source_digest no longer matches the
    fallback copy it was translated from.

    Regional overlays (en_CA, es_ES — a declared locale whose base language is
    also served) are reported by what they hold, never as incomplete: absence
    there is the normal state, covered by the serving chain (es_ES -> es -> en),
    so a "missing" count would just be noise.
    """
    fallback = master['fallback_to_default']
    exercises = master['exercises']
    by_locale = {doc['locale']: doc.get('exercises') or {} for _, doc in overlays}

    for locale in master['locales']:
        if locale == fallback:
            continue
        entries = by_locale.get(locale, {})
        concrete = {
            name: entry for name, entry in entries.items()
            if entry.get('fallback_to') is None and entry.get('name')
        }

        stale = []
        untracked = []
        for name, entry in concrete.items():
            source = exercises[name]['i18n'][fallback]
            expected = source_digest(source['name'], source.get('instructions'))
            match entry.get('source_digest'):
                case None:
                    untracked.append(name)
                case digest if digest != expected:
                    stale.append(name)
        validated = sum(1 for entry in concrete.values() if entry.get('validated'))

        base = locale.split('_')[0]
        if '_' in locale and (base == fallback or base in master['locales']):
            print(
                f'>> {locale}: regional overlay over {base}: '
                f'{len(concrete)} concrete of {len(entries)} entries '
                f'({len(stale)} stale, {len(untracked)} untracked, {validated} validated)'
            )
        else:
            missing = [name for name in exercises if name not in concrete]
            print(
                f'>> {locale}: {len(concrete)}/{len(exercises)} translated '
                f'({len(missing)} missing, {len(stale)} stale, {len(untracked)} untracked, {validated} validated)'
            )
            if detailed:
                for name in missing:
                    print(f'   missing: {name}')
        if detailed:
            for name in stale:
                print(f'   stale: {name}')
            for name in untracked:
                print(f'   untracked: {name}')


def main() -> int:
    detailed = '--coverage' in sys.argv[1:]

    with open(MASTER_SCHEMA) as f:
        master_schema = json.load(f)
    with open(OVERLAY_SCHEMA) as f:
        overlay_schema = json.load(f)

    with open(os.path.join(content_dir(), 'exercise_library.yml')) as f:
        master = yaml.safe_load(f)
    overlays = load_overlays()

    errors = 0
    for filename, document in overlays:
        errors += validate_schema(document, overlay_schema, f'i18n/{filename}')
    if errors:
        return 1

    try:
        merged = merge_overlays(master, overlays)
    except ValueError as e:
        print(f'content: {e}', file=sys.stderr)
        return 1

    if validate_schema(merged, master_schema, 'exercise_library.yml'):
        return 1

    library = Library.parse(merged)
    problems = []
    for exercise in library.exercises.values():
        try:
            exercise.fallback_localization()
        except ValueError as e:
            problems.append(str(e))
    if not problems:
        muscle_groups = set(master_schema['$defs']['muscleGroupList']['items']['enum'])
        muscle_ids = set(master_schema['$defs']['muscleList']['items']['enum'])
        problems = search_problems(library, muscle_groups, muscle_ids)
    for problem in problems:
        print(f'content: {problem}', file=sys.stderr)
    if problems:
        return 1

    print(f'>> OK: version {library.version}, {len(library.exercises)} exercises, locales {library.locales}')
    coverage(master, overlays, detailed)
    return 0


if __name__ == '__main__':
    sys.exit(main())

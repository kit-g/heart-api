"""
Check and render the free program library (heart-api#198).

content/sample_programs.yml is the source people review. This checks it
against the exercise library and the program rules the API enforces, then
renders the JSON the CDN serves as static/programs: each session in the shape
static/templates already uses, exercises by key, so the app reads both the
same way. The shape is docs/2026-10-14.program-library.md.

Run:
  uv run python scripts/programs_content.py                    # check
  uv run python scripts/programs_content.py --render out.json  # check, then render
"""

import argparse
import json
import os
import re
import sys
import uuid

import yaml
from library_locales import content_dir

SOURCE = os.path.join(content_dir(), 'sample_programs.yml')
LIBRARY = os.path.join(content_dir(), 'exercise_library.yml')

AUDIENCES = {'starting_out', 'getting_back', 'keep_muscle', 'getting_stronger'}
EQUIPMENT = {'none', 'home', 'gym'}
KEY = re.compile(r'^[a-z][a-z0-9_]{0,63}$')

# Which set columns each exercise category has, as the app draws them.
WEIGHTED = {'Barbell', 'Dumbbell', 'Machine', 'Weighted Body Weight', 'Assisted Body Weight'}
REPS = WEIGHTED | {'Reps Only'}
TIMED = {'Duration', 'Cardio', 'Weighted Duration'}

# Mirrors GrowthRule in shared/heart_models (src/models/program.dart): the
# kinds, their parameters, and the exercises each one can grow.
RULES = {
    'none': ({}, None),
    'addWeight': ({'step'}, WEIGHTED),
    'rangeThenWeight': ({'step'}, WEIGHTED),
    'longer': ({'step'}, TIMED),
    'shareOfMax': ({'step', 'waves'}, WEIGHTED),
}

# Ids are stable across renders, so a republish doesn't look like new content.
NAMESPACE = uuid.UUID('5f2b6a1e-9c1d-4f5e-8a57-3c1f0e2d7b90')


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def categories(library: dict) -> dict[str, str]:
    return {key: exercise['category'] for key, exercise in library['exercises'].items()}


def parse_measure(value) -> dict:
    """`5` exactly, `[8, 12]` a range, `'5+'` as many as possible."""
    match value:
        case bool():
            raise ValueError(f'{value!r} is not a target')
        case int() | float():
            return {'min': value, 'max': value}
        case [int() | float() as low, int() | float() as high] if low <= high:
            return {'min': low, 'max': high}
        case str() if re.fullmatch(r'\d+\+', value):
            return {'min': int(value[:-1])}
    raise ValueError(f'{value!r} is not a target: a number, [min, max], or "n+"')


def target_of(spec: dict) -> dict:
    target = {}
    for key, value in spec.items():
        if key == 'share':
            if not isinstance(value, (int, float)) or not 0 < value <= 2:
                raise ValueError(f'share {value!r} must be above 0 and at most 2')
            target['share'] = value
        elif key in ('reps', 'duration', 'distance'):
            target[key] = parse_measure(value)
        else:
            raise ValueError(f'unknown target measure {key!r}')
    return target


def set_targets(entry: dict) -> list[dict]:
    """Each set's target: `sets: 3` with one `target`, or `sets` listing each."""
    match entry.get('sets'):
        case int() as count if count >= 1:
            return [target_of(entry.get('target') or {}) for _ in range(count)]
        case list() as sets if sets:
            if 'target' in entry:
                raise ValueError('a list of sets carries its own targets')
            return [target_of(each) for each in sets]
    raise ValueError('sets must be a count with a target, or a list of targets')


def check_rule(where: str, rule, category: str | None, targets: list[list[dict]]) -> list[str]:
    if not isinstance(rule, dict) or rule.get('kind') not in RULES:
        return [f'{where}: unknown rule {rule!r}']
    params, fits = RULES[rule['kind']]
    problems = []
    if extra := set(rule) - params - {'kind', 'missCut', 'misses'}:
        problems.append(f'{where}: unknown parameters {sorted(extra)}')
    if 'step' in params and not (isinstance(rule.get('step'), (int, float)) and rule['step'] > 0):
        problems.append(f'{where}: step must be above 0')
    if fits is not None and category not in fits:
        problems.append(f'{where}: a {rule["kind"]} rule cannot grow a {category} exercise')
    if rule['kind'] == 'rangeThenWeight':
        for sets in targets:
            if not any('max' in t.get('reps', {}) and t['reps']['max'] > t['reps']['min'] for t in sets):
                problems.append(f'{where}: rangeThenWeight needs a rep range to reach the top of')
    if rule['kind'] == 'shareOfMax':
        waves = rule.get('waves')
        if not isinstance(waves, list) or not waves:
            problems.append(f'{where}: waves must be a non-empty list of weeks')
        else:
            for index, week in enumerate(waves):
                ok = (
                    isinstance(week, list)
                    and week
                    and all(
                        isinstance(s, dict)
                        and isinstance(s.get('share'), (int, float))
                        and 0 < s['share'] <= 2
                        and isinstance(s.get('reps'), int)
                        and s['reps'] >= 1
                        and set(s) <= {'share', 'reps', 'amrap'}
                        for s in week
                    )
                )
                if not ok:
                    problems.append(f'{where}: waves[{index}] is not a list of {{share, reps, amrap?}}')
            for sets in targets:
                if any(len(week) != len(sets) for week in waves if isinstance(week, list)):
                    problems.append(f'{where}: every week of the wave must have as many sets as the session')
                if not all('share' in t for t in sets):
                    problems.append(f'{where}: shareOfMax sets carry a share target')
    return problems


def check(document: dict, library: dict) -> list[str]:
    """Every problem in [document], or none."""
    kinds = categories(library)
    locales = document.get('locales') or []
    problems = []

    def copy(where: str, text, required=True):
        if text is None and not required:
            return
        if not isinstance(text, dict) or not isinstance(text.get('en'), str) or not text['en'].strip():
            problems.append(f'{where}: needs an en text')
            return
        for locale in locales:
            if not isinstance(text.get(locale), str) or not text[locale].strip():
                problems.append(f'{where}: missing {locale}')

    seen = set()
    for index, program in enumerate(document.get('programs') or []):
        key = program.get('key')
        where = f'programs[{index}]' if not isinstance(key, str) else key
        if not isinstance(key, str) or not KEY.fullmatch(key):
            problems.append(f'{where}: key must be snake_case')
        elif key in seen:
            problems.append(f'{where}: key is used twice')
        seen.add(key)
        if program.get('audience') not in AUDIENCES:
            problems.append(f'{where}: audience must be one of {sorted(AUDIENCES)}')
        if program.get('equipment') not in EQUIPMENT:
            problems.append(f'{where}: equipment must be one of {sorted(EQUIPMENT)}')
        per_week = program.get('per_week')
        if not (isinstance(per_week, int) and 1 <= per_week <= 28):
            problems.append(f'{where}: per_week must be 1 to 28')
        weeks = program.get('weeks')
        if weeks is not None and not (isinstance(weeks, int) and 1 <= weeks <= 104):
            problems.append(f'{where}: weeks must be 1 to 104, or left out for ongoing')
        copy(f'{where}.name', program.get('name'))
        copy(f'{where}.note', program.get('note'))

        sessions = program.get('sessions') or []
        if not sessions or len(sessions) > 50:
            problems.append(f'{where}: a program has 1 to 50 sessions')
        used: dict[str, list[list[dict]]] = {}
        session_keys = set()
        for session in sessions:
            at = f'{where}.{session.get("key")}'
            if not KEY.fullmatch(str(session.get('key'))) or session['key'] in session_keys:
                problems.append(f'{at}: session key must be snake_case and unique in its program')
            session_keys.add(session.get('key'))
            copy(f'{at}.name', session.get('name'))
            copy(f'{at}.note', session.get('note'), required=False)
            for entry in session.get('exercises') or []:
                exercise = entry.get('exercise')
                if exercise not in kinds:
                    problems.append(f'{at}: {exercise!r} is not in the exercise library')
                    continue
                try:
                    targets = set_targets(entry)
                except ValueError as e:
                    problems.append(f'{at}.{exercise}: {e}')
                    continue
                category = kinds[exercise]
                for target in targets:
                    if 'reps' in target and category not in REPS:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no reps')
                    if 'duration' in target and category not in TIMED:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no duration')
                    if 'share' in target and category not in WEIGHTED:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no weight to share')
                used.setdefault(exercise, []).append(targets)

        rules = program.get('rules') or {}
        for exercise, rule in rules.items():
            if exercise not in used:
                problems.append(f'{where}.rules.{exercise}: no session does this exercise')
                continue
            problems += check_rule(f'{where}.rules.{exercise}', rule, kinds.get(exercise), used[exercise])
        for exercise, targets in used.items():
            if (
                any('share' in t for sets in targets for t in sets)
                and (rules.get(exercise) or {}).get('kind') != 'shareOfMax'
            ):
                problems.append(f'{where}.{exercise}: a share target needs a shareOfMax rule')
    return problems


def _id(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, '/'.join(parts)))


def _texts(text: dict | None, locales: list[str]) -> tuple[str | None, dict]:
    if text is None:
        return None, {}
    return text['en'], {locale: text[locale] for locale in locales}


def render(document: dict) -> dict:
    """The static/programs object. Rules stay keyed by exercise key: the app
    resolves each key through its library when it copies a program, as it
    does a template's exercises."""
    locales = document['locales']
    programs = []
    for program in document['programs']:
        name, name_i18n = _texts(program['name'], locales)
        note, note_i18n = _texts(program['note'], locales)
        sessions = []
        for order, session in enumerate(program['sessions']):
            session_name, session_name_i18n = _texts(session['name'], locales)
            session_note, session_note_i18n = _texts(session.get('note'), locales)
            exercises = []
            for exercise_order, entry in enumerate(session['exercises']):
                exercise_id = _id(program['key'], session['key'], str(exercise_order))
                exercises.append(
                    {
                        'id': exercise_id,
                        'exercise': {'key': entry['exercise']},
                        'exercise_order': exercise_order,
                        'sets': [
                            {'id': _id(exercise_id, str(set_order)), 'completed': False, 'target': target}
                            for set_order, target in enumerate(set_targets(entry))
                        ],
                    }
                )
            sessions.append(
                {
                    'id': _id(program['key'], session['key']),
                    'key': session['key'],
                    'name': session_name,
                    'i18n': session_name_i18n,
                    **({'note': session_note, 'noteI18n': session_note_i18n} if session_note else {}),
                    'order': order,
                    'exercises': exercises,
                }
            )
        programs.append(
            {
                'key': program['key'],
                'audience': program['audience'],
                'equipment': program['equipment'],
                'name': name,
                'i18n': name_i18n,
                'note': note,
                'noteI18n': note_i18n,
                'perWeek': program['per_week'],
                **({'weeks': program['weeks']} if program.get('weeks') else {}),
                'rules': program.get('rules') or {},
                'sessions': sessions,
            }
        )
    return {'version': document['version'], 'programs': programs}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--render', metavar='PATH', help='write the static/programs JSON here')
    args = parser.parse_args()

    document = load(SOURCE)
    problems = check(document, load(LIBRARY))
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f'{len(document["programs"])} programs, no problems')
    if args.render:
        with open(args.render, 'w', encoding='utf-8') as f:
            json.dump(render(document), f, ensure_ascii=False, indent=2)
            f.write('\n')
        print(f'rendered {args.render}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

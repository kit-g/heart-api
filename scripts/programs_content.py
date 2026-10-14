"""
Check and render the free program library (heart-api#198, #235).

content/sample_programs.yml is the source people review, with
program_sources.yml (what each claim rests on), program_safety.yml (what the
app says about safety) and exercise_ladders.yml (the variation ladders). This
checks them against the exercise library and the program rules the API
enforces, then renders the JSON the CDN serves as static/programs: each
session in the shape static/templates already uses, exercises by key, so the
app reads both the same way. The shape is docs/2026-10-14.program-library.md.

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
SOURCES = os.path.join(content_dir(), 'program_sources.yml')
SAFETY = os.path.join(content_dir(), 'program_safety.yml')
LADDERS = os.path.join(content_dir(), 'exercise_ladders.yml')

AUDIENCES = {'starting_out', 'getting_back', 'keep_muscle', 'getting_stronger'}
EQUIPMENT = {'none', 'home', 'gym'}
KEY = re.compile(r'^[a-z][a-z0-9_]{0,63}$')

# Which set columns each exercise category has, as the app draws them.
WEIGHTED = {'Barbell', 'Dumbbell', 'Machine', 'Weighted Body Weight', 'Assisted Body Weight'}
REPS = WEIGHTED | {'Reps Only'}
TIMED = {'Duration', 'Cardio', 'Weighted Duration'}
BODYWEIGHT = {'Reps Only', 'Weighted Body Weight', 'Assisted Body Weight'}

# Mirrors GrowthRule in shared/heart_models (src/models/program.dart): the
# kinds, their parameters, and the exercises each one can grow.
RULES = {
    'none': (set(), None),
    'addWeight': ({'step', 'miss', 'amrap'}, WEIGHTED),
    'rangeThenWeight': ({'step', 'miss', 'amrap'}, WEIGHTED),
    'longer': ({'step'}, TIMED),
    'shareOfMax': ({'step', 'waves', 'missCut', 'misses', 'miss', 'amrap'}, WEIGHTED),
    'ladder': ({'ladder', 'top', 'bottom'}, BODYWEIGHT),
    'stages': ({'stages', 'step', 'miss', 'amrap'}, WEIGHTED),
}
# The rules that keep a base a share can be of.
BASED = {'addWeight', 'rangeThenWeight', 'shareOfMax', 'stages'}
MISS_WHEN = {'anySet', 'amrap', 'totalReps'}

# Ids are stable across renders, so a republish doesn't look like new content.
NAMESPACE = uuid.UUID('5f2b6a1e-9c1d-4f5e-8a57-3c1f0e2d7b90')


def load(path: str) -> dict:
    with open(path, encoding='utf-8') as f:
        return yaml.safe_load(f)


def _number(value, low, high) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and low <= value <= high


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
            if not _number(value, 0.01, 2):
                raise ValueError(f'share {value!r} must be above 0 and at most 2')
            target['share'] = value
        elif key == 'rir':
            if not _number(value, 0, 10) or value * 2 != int(value * 2):
                raise ValueError(f'rir {value!r} must be 0 to 10, in halves')
            target['rir'] = value
        elif key == 'of':
            if not isinstance(value, str) or not value:
                raise ValueError('of names the exercise whose base the share is of, by key')
            target['of'] = value
        elif key == 'of_slot':
            if not isinstance(value, str) or not value:
                raise ValueError('of_slot names the session whose occurrence of the lift the share is of, by key')
            target['of_slot'] = value
        elif key == 'supplemental':
            if value is not True:
                raise ValueError('supplemental is true or left out')
            target['supplemental'] = True
        elif key in ('reps', 'duration', 'distance'):
            target[key] = parse_measure(value)
        else:
            raise ValueError(f'unknown target measure {key!r}')
    if 'of' in target and 'share' not in target:
        raise ValueError('of goes with a share')
    if 'of_slot' in target and 'of' not in target:
        raise ValueError('of_slot goes with of, the lift it is an occurrence of')
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


def _check_miss(where: str, miss) -> list[str]:
    if not isinstance(miss, dict) or set(miss) - {'when', 'floor', 'after', 'cut'}:
        return [f'{where}: miss is {{when?, floor?, after?, cut?}}']
    problems = []
    if miss.get('when', 'anySet') not in MISS_WHEN:
        problems.append(f'{where}: miss.when must be one of {sorted(MISS_WHEN)}')
    if 'after' in miss and not (isinstance(miss['after'], int) and miss['after'] >= 1):
        problems.append(f'{where}: miss.after is a whole number of at least 1')
    if 'cut' in miss and not _number(miss['cut'], 0, 0.99):
        problems.append(f'{where}: miss.cut is a share below 1')
    if 'floor' in miss and not (isinstance(miss['floor'], int) and miss['floor'] >= 1):
        problems.append(f'{where}: miss.floor is a whole number of reps')
    return problems


def check_rule(where, rule, category, targets, ladders) -> list[str]:
    if not isinstance(rule, dict) or rule.get('kind') not in RULES:
        return [f'{where}: unknown rule {rule!r}']
    params, fits = RULES[rule['kind']]
    problems = []
    if extra := set(rule) - params - {'kind'}:
        problems.append(f'{where}: unknown parameters {sorted(extra)}')
    if 'step' in params and not (_number(rule.get('step'), 0.01, 1000)):
        problems.append(f'{where}: step must be above 0')
    if fits is not None and category not in fits:
        problems.append(f'{where}: a {rule["kind"]} rule cannot grow a {category} exercise')
    if 'miss' in rule:
        problems += _check_miss(where, rule['miss'])
    if 'amrap' in rule and not (
        isinstance(rule['amrap'], list)
        and all(
            isinstance(row, dict) and isinstance(row.get('reps'), int) and _number(row.get('step'), -1000, 1000)
            for row in rule['amrap']
        )
    ):
        problems.append(f'{where}: amrap is a list of {{reps, step}}')
    if rule['kind'] == 'rangeThenWeight':
        for sets in targets:
            if not any('max' in t.get('reps', {}) and t['reps']['max'] > t['reps']['min'] for t in sets):
                problems.append(f'{where}: rangeThenWeight needs a rep range to reach the top of')
    if rule['kind'] == 'ladder':
        exercise = where.rsplit('.', 1)[-1]
        rungs = ladders.get(rule.get('ladder'))
        if rungs is None:
            problems.append(f'{where}: no ladder {rule.get("ladder")!r} in exercise_ladders.yml')
        elif exercise not in rungs:
            problems.append(f'{where}: {exercise} is not on the {rule["ladder"]} ladder')
        top, bottom = rule.get('top'), rule.get('bottom')
        if not (isinstance(top, int) and isinstance(bottom, int) and 1 <= bottom < top):
            problems.append(f'{where}: a ladder climbs from bottom to top reps, bottom below top')
        else:
            for sets in targets:
                if not all(t.get('reps', {}).get('max') == top for t in sets):
                    problems.append(f"{where}: the sets' range must top out where the ladder climbs ({top})")
    if rule['kind'] == 'stages':
        stages = rule.get('stages')
        ok = (
            isinstance(stages, list)
            and 2 <= len(stages) <= 20
            and all(
                isinstance(s, dict)
                and set(s) <= {'sets', 'reps', 'amrap'}
                and isinstance(s.get('sets'), int)
                and 1 <= s['sets'] <= 20
                and isinstance(s.get('reps'), int)
                and 1 <= s['reps'] <= 100
                and s.get('amrap', False) in (True, False)
                for s in stages
            )
        )
        if not ok:
            problems.append(f'{where}: stages is 2 to 20 {{sets 1–20, reps 1–100, amrap?}}')
        else:
            # the session's sets are the first stage, as the plan lays it out
            first = stages[0]
            want = [{'min': first['reps'], 'max': first['reps']}] * first['sets']
            if first.get('amrap'):
                want = want[:-1] + [{'min': first['reps']}]
            for sets in targets:
                if [t.get('reps') for t in sets] != want:
                    problems.append(f'{where}: the sets must be the first stage, {first["sets"]}×{first["reps"]}')
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
                        and _number(s.get('share'), 0.01, 2)
                        and isinstance(s.get('reps'), int)
                        and s['reps'] >= 1
                        and set(s) <= {'share', 'reps', 'amrap', 'supplemental'}
                        for s in week
                    )
                )
                if not ok:
                    problems.append(f'{where}: waves[{index}] is not a list of {{share, reps, amrap?, supplemental?}}')
            for sets in targets:
                if any(len(week) != len(sets) for week in waves if isinstance(week, list)):
                    problems.append(f'{where}: every week of the wave must have as many sets as the session')
                if not all('share' in t for t in sets):
                    problems.append(f'{where}: shareOfMax sets carry a share target')
    return problems


# What a claim can be about: a part of the program page, by name, or one of
# its rules, sessions or a session's exercise, by key.
ANCHORS = {'program', 'who', 'week', 'grows', 'misses', 'deload', 'phases', 'tests', 'next', 'rest'}
OPTIONAL_ANCHORS = {'deload', 'phases', 'tests', 'next'}


def _anchor_problem(program: dict, anchor) -> str | None:
    """Why [anchor] names nothing in [program], or None when it does."""
    if not isinstance(anchor, str):
        return 'is not a string'
    sessions = {session.get('key'): session for session in program.get('sessions') or []}
    match anchor.split('.'):
        case [name] if name in ANCHORS:
            if name in OPTIONAL_ANCHORS and not program.get(name):
                return f'names a {name} the program does not have'
            return None
        case ['rules', exercise]:
            return None if exercise in (program.get('rules') or {}) else 'names no rule of the program'
        case ['sessions', session]:
            return None if session in sessions else 'names no session of the program'
        case ['sessions', session, exercise]:
            if session not in sessions:
                return 'names no session of the program'
            count = sum(1 for entry in sessions[session].get('exercises') or [] if entry.get('exercise') == exercise)
            if count != 1:
                return 'must name an exercise the session has exactly once'
            return None
    return f'is none of {sorted(ANCHORS)}, rules.<exercise>, sessions.<session>[.<exercise>]'


def check(document: dict, library: dict, sources=None, safety=None, ladders=None) -> list[str]:
    """Every problem in [document], or none."""
    sources = load(SOURCES) if sources is None else sources
    safety = load(SAFETY) if safety is None else safety
    ladders = (load(LADDERS) if ladders is None else ladders)['ladders']
    exercises = library['exercises']
    locales = document.get('locales') or []
    problems = []

    def copy(where: str, text, required=True, langs=locales):
        if text is None and not required:
            return
        if not isinstance(text, dict) or not isinstance(text.get('en'), str) or not text['en'].strip():
            problems.append(f'{where}: needs an en text')
            return
        for locale in langs:
            if not isinstance(text.get(locale), str) or not text[locale].strip():
                problems.append(f'{where}: missing {locale}')

    known_sources = sources.get('sources') or {}
    for key, source in known_sources.items():
        for field in ('title', 'who', 'url'):
            if not isinstance(source.get(field), str) or not source[field].strip():
                problems.append(f'sources.{key}: needs a {field}')
        if not str(source.get('url', '')).startswith('https://'):
            problems.append(f'sources.{key}: the url is https')
        if not isinstance(source.get('year'), int):
            problems.append(f'sources.{key}: needs a year')
        copy(f'sources.{key}.finding', source.get('finding'), langs=sources.get('locales') or [])

    def cites(where: str, keys):
        for key in keys or []:
            if key not in known_sources:
                problems.append(f'{where}: no source {key!r} in program_sources.yml')

    known_notes = safety.get('notes') or {}
    for key, note in known_notes.items():
        copy(f'safety.{key}', note.get('text'), langs=safety.get('locales') or [])
        cites(f'safety.{key}', note.get('sources'))

    programs = document.get('programs') or []
    program_keys = {program.get('key') for program in programs}
    seen = set()
    for index, program in enumerate(programs):
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
        if not (isinstance(program.get('per_week'), int) and 1 <= program['per_week'] <= 28):
            problems.append(f'{where}: per_week must be 1 to 28')
        weeks = program.get('weeks')
        if weeks is not None and not (isinstance(weeks, int) and 1 <= weeks <= 104):
            problems.append(f'{where}: weeks must be 1 to 104, or left out for ongoing')
        if not (isinstance(program.get('minutes'), int) and 5 <= program['minutes'] <= 180):
            problems.append(f"{where}: minutes, a session's length, is 5 to 180")
        for field in ('name', 'note', 'who', 'week', 'grows', 'misses'):
            copy(f'{where}.{field}', program.get(field))
        for following in program.get('next') or []:
            if following not in program_keys or following == key:
                problems.append(f'{where}.next: {following!r} is not another program')
        for note in program.get('safety') or []:
            if note not in known_notes:
                problems.append(f'{where}.safety: no note {note!r} in program_safety.yml')
        if not program.get('why'):
            problems.append(f'{where}: why is the research it rests on, one claim or more')
        for at, claim in enumerate(program.get('why') or []):
            copy(f'{where}.why[{at}]', claim.get('text'))
            if not claim.get('sources'):
                problems.append(f'{where}.why[{at}]: a claim cites a source')
            cites(f'{where}.why[{at}]', claim.get('sources'))
            about = claim.get('about')
            if not isinstance(about, list) or not about:
                problems.append(f'{where}.why[{at}]: about says which part of the program a claim explains')
                continue
            for anchor in about:
                if (why := _anchor_problem(program, anchor)) is not None:
                    problems.append(f'{where}.why[{at}].about: {anchor!r} {why}')
        if (deload := program.get('deload')) is not None and not (
            isinstance(deload, dict)
            and isinstance(deload.get('every'), int)
            and 2 <= deload['every'] <= 52
            and all(_number(deload.get(k, 0.5), 0.01, 1) for k in ('load', 'volume'))
            and set(deload) <= {'every', 'load', 'volume'}
        ):
            problems.append(f'{where}: deload is {{every 2–52, load?, volume?}}')

        sessions = program.get('sessions') or []
        if not sessions or len(sessions) > 50:
            problems.append(f'{where}: a program has 1 to 50 sessions')
        used: dict[str, list[list[dict]]] = {}
        occurrences: dict[tuple, list[dict]] = {}
        slot_rules: dict[tuple, dict] = {}
        shared: list[tuple] = []
        session_keys = set()
        for session in sessions:
            at = f'{where}.{session.get("key")}'
            if not KEY.fullmatch(str(session.get('key'))) or session['key'] in session_keys:
                problems.append(f'{at}: session key must be snake_case and unique in its program')
            session_keys.add(session.get('key'))
            copy(f'{at}.name', session.get('name'))
            copy(f'{at}.note', session.get('note'), required=False)
            supersets: dict[int, int] = {}
            for entry in session.get('exercises') or []:
                exercise = entry.get('exercise')
                if exercise not in exercises:
                    problems.append(f'{at}: {exercise!r} is not in the exercise library')
                    continue
                try:
                    targets = set_targets(entry)
                except ValueError as e:
                    problems.append(f'{at}.{exercise}: {e}')
                    continue
                if extra := set(entry) - {
                    'exercise',
                    'sets',
                    'target',
                    'rest',
                    'superset',
                    'pattern',
                    'total_reps',
                    'rule',
                }:
                    problems.append(f'{at}.{exercise}: unknown {sorted(extra)}')
                if 'rest' in entry and not (isinstance(entry['rest'], int) and 0 <= entry['rest'] <= 1800):
                    problems.append(f'{at}.{exercise}: rest is whole seconds up to 1800')
                if 'superset' in entry:
                    if not (isinstance(entry['superset'], int) and 1 <= entry['superset'] <= 50):
                        problems.append(f'{at}.{exercise}: superset is 1 to 50')
                    else:
                        supersets[entry['superset']] = supersets.get(entry['superset'], 0) + 1
                if 'pattern' in entry:
                    groups = (exercises[exercise].get('movement') or {}).get('groups') or []
                    if entry['pattern'] not in groups:
                        problems.append(f'{at}.{exercise}: its movement is {groups}, not {entry["pattern"]!r}')
                if 'total_reps' in entry:
                    try:
                        parse_measure(entry['total_reps'])
                    except ValueError as e:
                        problems.append(f'{at}.{exercise}: total_reps: {e}')
                category = exercises[exercise]['category']
                for target in targets:
                    if 'reps' in target and category not in REPS:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no reps')
                    if 'duration' in target and category not in TIMED:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no duration')
                    if 'share' in target and category not in WEIGHTED:
                        problems.append(f'{at}.{exercise}: a {category} exercise has no weight to share')
                # a test session finds the bases its rules then grow, so it
                # isn't held to them
                if session.get('key') in (program.get('tests') or {}):
                    continue
                occurrences.setdefault((session.get('key'), exercise), []).append(entry)
                # an occurrence with a rule of its own is held to it, not to its
                # exercise's
                if 'rule' in entry:
                    problems += check_rule(f'{at}.{exercise}.rule', entry['rule'], category, [targets], ladders)
                    slot_rules[(session.get('key'), exercise)] = entry['rule']
                else:
                    used.setdefault(exercise, []).append(targets)
                shared.append((f'{at}.{exercise}', exercise, entry.get('rule'), targets))
            for number, members in supersets.items():
                if members < 2:
                    problems.append(f'{at}: superset {number} has one exercise')

        for phase_at, phase in enumerate(program.get('phases') or []):
            copy(f'{where}.phases[{phase_at}].name', phase.get('name'))
            for session_key in phase.get('sessions') or []:
                if session_key not in session_keys:
                    problems.append(f'{where}.phases[{phase_at}]: no session {session_key!r}')
            if not phase.get('sessions'):
                problems.append(f'{where}.phases[{phase_at}]: a phase runs one session or more')
            cycles = phase.get('cycles')
            if cycles is None and phase_at != len(program['phases']) - 1:
                problems.append(f'{where}.phases[{phase_at}]: only the last phase runs on')
            if cycles is not None and not (isinstance(cycles, int) and 1 <= cycles <= 104):
                problems.append(f'{where}.phases[{phase_at}]: cycles is 1 to 104')
        for session_key, test in (program.get('tests') or {}).items():
            if session_key not in session_keys:
                problems.append(f'{where}.tests: no session {session_key!r}')
            if not _number((test or {}).get('share', 0.9), 0.01, 1):
                problems.append(f'{where}.tests.{session_key}: share is above 0 and at most 1')

        rules = program.get('rules') or {}
        for exercise, rule in rules.items():
            if exercise not in used:
                problems.append(f'{where}.rules.{exercise}: no session does this exercise')
                continue
            problems += check_rule(
                f'{where}.rules.{exercise}', rule, exercises[exercise]['category'], used[exercise], ladders
            )

        def keeps_base(rule) -> bool:
            return (rule or {}).get('kind') in BASED

        for at, exercise, own, targets in shared:
            for target in (t for t in targets if 'share' in t):
                # a share of one occurrence of a lift, of a lift, or of its own
                if (slot := target.get('of_slot')) is not None:
                    of = target['of']
                    if len(occurrences.get((slot, of), [])) != 1:
                        problems.append(f'{at}: of_slot {slot!r} must be a session doing {of} exactly once')
                    elif not keeps_base(slot_rules.get((slot, of)) or rules.get(of)):
                        problems.append(f'{at}: of_slot {slot!r} names an occurrence with no rule that keeps a base')
                elif (of := target.get('of')) is not None:
                    if not keeps_base(rules.get(of)):
                        problems.append(f'{at}: of {of!r} names no exercise with a rule that keeps a base')
                elif not keeps_base(own or rules.get(exercise)):
                    problems.append(f'{at}: a share target needs a rule that keeps a base')
                    break
    return problems


def _id(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, '/'.join(parts)))


def _texts(text: dict | None, locales: list[str]) -> tuple[str | None, dict]:
    if text is None:
        return None, {}
    return text['en'], {locale: text[locale] for locale in locales}


def _slot_id(program: dict, session: str, exercise: str) -> str:
    """The template exercise id of [exercise]'s one occurrence in [session]."""
    entries = next(s for s in program['sessions'] if s['key'] == session)['exercises']
    order = next(i for i, entry in enumerate(entries) if entry['exercise'] == exercise)
    return _id(program['key'], session, str(order))


def _wire_target(program: dict, target: dict) -> dict:
    """A target as the app reads it: `of_slot`, a session key here, is the
    occurrence's template exercise id there, `ofSlot`."""
    wired = {key: value for key, value in target.items() if key != 'of_slot'}
    if (session := target.get('of_slot')) is not None:
        wired['ofSlot'] = _slot_id(program, session, target['of'])
    return wired


def _wire_rule(rule: dict, ladders: dict) -> dict:
    """A rule as heart_models reads it: a ladder's rungs spelled out."""
    if rule['kind'] == 'ladder':
        return {'kind': 'ladder', 'rungs': ladders[rule['ladder']], 'top': rule['top'], 'bottom': rule['bottom']}
    return rule


def _wire_anchor(program: dict, anchor: str, session_ids: dict[str, str]) -> dict:
    """An anchor as the app finds it: a part by name, a rule by exercise key
    (the key rules are under), a session or a session's exercise by id."""
    match anchor.split('.'):
        case ['rules', exercise]:
            return {'on': 'rule', 'exercise': exercise}
        case ['sessions', session]:
            return {'on': 'session', 'session': session_ids[session]}
        case ['sessions', session, exercise]:
            return {'on': 'exercise', 'session': session_ids[session], 'exercise': _slot_id(program, session, exercise)}
        case [name]:
            return {'on': name}
    raise ValueError(anchor)


def render(document: dict, sources=None, safety=None, ladders=None) -> dict:
    """The static/programs object. Rules, ladders and sources stay keyed by
    library and content keys: the app resolves an exercise key through its
    library when it copies a program, as it does a template's exercises."""
    sources = load(SOURCES) if sources is None else sources
    safety = load(SAFETY) if safety is None else safety
    ladders = (load(LADDERS) if ladders is None else ladders)['ladders']
    locales = document['locales']

    def text(field: dict | None, langs=locales) -> dict:
        if field is None:
            return {}
        return {'en': field['en'], **{locale: field[locale] for locale in langs}}

    programs = []
    for program in document['programs']:
        session_ids = {session['key']: _id(program['key'], session['key']) for session in program['sessions']}
        sessions = []
        for order, session in enumerate(program['sessions']):
            name, name_i18n = _texts(session['name'], locales)
            note, note_i18n = _texts(session.get('note'), locales)
            exercises = []
            for exercise_order, entry in enumerate(session['exercises']):
                exercise_id = _id(program['key'], session['key'], str(exercise_order))
                exercises.append(
                    {
                        'id': exercise_id,
                        'exercise': {'key': entry['exercise']},
                        'exercise_order': exercise_order,
                        **({'rest': entry['rest']} if 'rest' in entry else {}),
                        **({'superset': entry['superset']} if 'superset' in entry else {}),
                        **({'pattern': entry['pattern']} if 'pattern' in entry else {}),
                        **({'totalReps': parse_measure(entry['total_reps'])} if 'total_reps' in entry else {}),
                        'sets': [
                            {
                                'id': _id(exercise_id, str(set_order)),
                                'completed': False,
                                'target': _wire_target(program, target),
                            }
                            for set_order, target in enumerate(set_targets(entry))
                        ],
                    }
                )
            sessions.append(
                {
                    'id': session_ids[session['key']],
                    'key': session['key'],
                    'name': name,
                    'i18n': name_i18n,
                    **({'note': note, 'noteI18n': note_i18n} if note else {}),
                    'order': order,
                    'exercises': exercises,
                }
            )

        # by exercise key, and an occurrence's own rule by its template
        # exercise id, which the app's copy maps to the new one
        rules = {exercise: _wire_rule(rule, ladders) for exercise, rule in (program.get('rules') or {}).items()}
        for session in program['sessions']:
            for order, entry in enumerate(session['exercises']):
                if 'rule' in entry:
                    rules[_id(program['key'], session['key'], str(order))] = _wire_rule(entry['rule'], ladders)

        name, name_i18n = _texts(program['name'], locales)
        note, note_i18n = _texts(program['note'], locales)
        cited = sorted({key for claim in program['why'] for key in claim['sources']})
        programs.append(
            {
                'key': program['key'],
                'audience': program['audience'],
                'equipment': program['equipment'],
                'name': name,
                'i18n': name_i18n,
                'note': note,
                'noteI18n': note_i18n,
                'who': text(program['who']),
                'week': text(program['week']),
                'grows': text(program['grows']),
                'misses': text(program['misses']),
                'why': [
                    {
                        'text': text(claim['text']),
                        'sources': claim['sources'],
                        'about': [_wire_anchor(program, anchor, session_ids) for anchor in claim['about']],
                    }
                    for claim in program['why']
                ],
                'sources': cited,
                'safety': program.get('safety') or [],
                'next': program.get('next') or [],
                'perWeek': program['per_week'],
                'minutes': program['minutes'],
                **({'weeks': program['weeks']} if program.get('weeks') else {}),
                **({'deload': program['deload']} if program.get('deload') else {}),
                **(
                    {
                        'phases': [
                            {
                                'name': text(phase['name']),
                                'sessions': [session_ids[key] for key in phase['sessions']],
                                **({'cycles': phase['cycles']} if phase.get('cycles') else {}),
                            }
                            for phase in program['phases']
                        ]
                    }
                    if program.get('phases')
                    else {}
                ),
                **(
                    {
                        'tests': {
                            session_ids[key]: {'share': (test or {}).get('share', 0.9)}
                            for key, test in program['tests'].items()
                        }
                    }
                    if program.get('tests')
                    else {}
                ),
                'rules': rules,
                'sessions': sessions,
            }
        )

    source_locales = sources.get('locales') or []
    safety_locales = safety.get('locales') or []
    return {
        'version': document['version'],
        'programs': programs,
        'sources': {
            key: {
                'title': source['title'],
                'who': source['who'],
                'year': source['year'],
                'url': source['url'],
                'finding': text(source['finding'], source_locales),
                'usedBy': sorted(
                    program['key']
                    for program in document['programs']
                    if any(key in claim['sources'] for claim in program['why'])
                ),
            }
            for key, source in sources['sources'].items()
        },
        'safety': {
            key: {'text': text(note['text'], safety_locales), 'sources': note.get('sources') or []}
            for key, note in safety['notes'].items()
        },
    }


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

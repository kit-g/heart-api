"""The program library's checks and render (scripts/programs_content.py).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

import copy

import pytest
from programs_content import LIBRARY, SOURCE, check, load, parse_measure, render

LIBRARY_DOC = load(LIBRARY)


def one(**program) -> dict:
    base = {
        'key': 'p',
        'audience': 'starting_out',
        'equipment': 'gym',
        'per_week': 3,
        'name': {'en': 'P', 'es': 'P', 'fr': 'P', 'ru': 'P'},
        'note': {'en': 'N', 'es': 'N', 'fr': 'N', 'ru': 'N'},
        'rules': {'squat-barbell': {'kind': 'rangeThenWeight', 'step': 2.5}},
        'sessions': [
            {
                'key': 'a',
                'name': {'en': 'A', 'es': 'A', 'fr': 'A', 'ru': 'A'},
                'exercises': [{'exercise': 'squat-barbell', 'sets': 3, 'target': {'reps': [5, 8]}}],
            }
        ],
    }
    base.update(program)
    return {'version': 1, 'locales': ['es', 'fr', 'ru'], 'programs': [base]}


def test_the_library_as_written_has_no_problems():
    assert check(load(SOURCE), LIBRARY_DOC) == []


def test_a_minimal_program_passes():
    assert check(one(), LIBRARY_DOC) == []


@pytest.mark.parametrize(
    ('value', 'expected'),
    [(5, {'min': 5, 'max': 5}), ([8, 12], {'min': 8, 'max': 12}), ('5+', {'min': 5})],
)
def test_targets_read_three_ways(value, expected):
    assert parse_measure(value) == expected


@pytest.mark.parametrize('value', [[12, 8], 'five', True, '5-8'])
def test_a_target_that_is_none_of_them_is_refused(value):
    with pytest.raises(ValueError):
        parse_measure(value)


@pytest.mark.parametrize(
    ('change', 'problem'),
    [
        ({'audience': 'lifters'}, 'audience'),
        ({'per_week': 29}, 'per_week'),
        ({'weeks': 0}, 'weeks'),
        ({'name': {'en': 'P', 'es': 'P', 'fr': 'P'}}, 'missing ru'),
        ({'rules': {'squat-barbell': {'kind': 'autoregulated'}}}, 'unknown rule'),
        ({'rules': {'squat-barbell': {'kind': 'addWeight', 'step': 0}}}, 'step must be above 0'),
        ({'rules': {'plank': {'kind': 'longer', 'step': 5}}}, 'no session does this exercise'),
        ({'rules': {'squat-barbell': {'kind': 'longer', 'step': 5}}}, 'cannot grow a Barbell exercise'),
    ],
)
def test_program_problems_are_named(change, problem):
    problems = check(one(**change), LIBRARY_DOC)
    assert any(problem in each for each in problems), problems


def exercise(entry: dict, rules: dict | None = None) -> list[str]:
    doc = one(rules=rules or {})
    doc['programs'][0]['sessions'][0]['exercises'] = [entry]
    return check(doc, LIBRARY_DOC)


def test_an_exercise_outside_the_library_is_refused():
    assert any('not in the exercise library' in p for p in exercise({'exercise': 'bench-press-pounds', 'sets': 3}))


def test_targets_fit_the_category():
    assert any(
        'has no duration' in p for p in exercise({'exercise': 'squat-barbell', 'sets': 1, 'target': {'duration': 30}})
    )
    assert any('has no reps' in p for p in exercise({'exercise': 'plank', 'sets': 1, 'target': {'reps': 5}}))


def test_range_then_weight_needs_a_range():
    problems = exercise(
        {'exercise': 'squat-barbell', 'sets': 3, 'target': {'reps': 5}},
        {'squat-barbell': {'kind': 'rangeThenWeight', 'step': 2.5}},
    )
    assert any('needs a rep range' in p for p in problems)


def test_share_of_max_waves_match_the_sets_and_need_a_share():
    waves = [[{'share': 0.65, 'reps': 5}, {'share': 0.75, 'reps': 5}]]
    rule = {'squat-barbell': {'kind': 'shareOfMax', 'step': 5, 'waves': waves}}
    assert any(
        'as many sets' in p for p in exercise({'exercise': 'squat-barbell', 'sets': [{'share': 0.65, 'reps': 5}]}, rule)
    )
    assert any(
        'carry a share' in p for p in exercise({'exercise': 'squat-barbell', 'sets': 2, 'target': {'reps': 5}}, rule)
    )
    assert any(
        'needs a shareOfMax rule' in p
        for p in exercise({'exercise': 'squat-barbell', 'sets': [{'share': 0.65, 'reps': 5}]}, {})
    )


def test_render_is_stable_and_in_the_template_shape():
    document = load(SOURCE)
    first, second = render(document), render(copy.deepcopy(document))
    assert first == second, 'ids must not change between renders'

    waves = next(p for p in first['programs'] if p['key'] == 'strength_waves')
    squat = waves['sessions'][0]['exercises'][0]
    assert squat['exercise'] == {'key': 'squat-barbell'}
    assert squat['sets'][2]['target'] == {'share': 0.85, 'reps': {'min': 5}}
    assert waves['rules']['squat-barbell']['kind'] == 'shareOfMax'
    assert 'weeks' not in waves, 'ongoing'

    steps = next(p for p in first['programs'] if p['key'] == 'first_steps')
    assert steps['weeks'] == 8
    assert steps['i18n']['ru'] == 'Первые шаги'
    assert steps['sessions'][0]['noteI18n']['es'].startswith('Piernas')

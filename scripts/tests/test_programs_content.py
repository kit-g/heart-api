"""The program library's checks and render (scripts/programs_content.py).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

import copy

import pytest
from programs_content import LIBRARY, SOURCE, check, load, parse_measure, render

LIBRARY_DOC = load(LIBRARY)


def _t(word: str) -> dict:
    return {'en': word, 'es': word, 'fr': word, 'ru': word}


def one(**program) -> dict:
    base = {
        'key': 'p',
        'audience': 'starting_out',
        'equipment': 'gym',
        'per_week': 3,
        'minutes': 45,
        'name': _t('P'),
        'note': _t('N'),
        'who': _t('W'),
        'week': _t('K'),
        'grows': _t('G'),
        'misses': _t('M'),
        'why': [{'text': _t('Y'), 'sources': ['acsm_2026'], 'about': ['program']}],
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


def test_a_claim_cites_a_source_that_exists():
    assert any('no source' in p for p in check(one(why=[{'text': _t('Y'), 'sources': ['vibes']}]), LIBRARY_DOC))
    assert any('cites a source' in p for p in check(one(why=[{'text': _t('Y'), 'sources': []}]), LIBRARY_DOC))


@pytest.mark.parametrize(
    ('about', 'problem'),
    [
        (None, 'about says which part'),
        ([], 'about says which part'),
        (['footer'], 'is none of'),
        (['deload'], 'names a deload the program does not have'),
        (['rules.bench-press-barbell'], 'names no rule'),
        (['sessions.z'], 'names no session'),
        (['sessions.a.bench-press-barbell'], 'exactly once'),
    ],
)
def test_a_claim_is_about_a_part_the_program_has(about, problem):
    claim = {'text': _t('Y'), 'sources': ['acsm_2026'], 'about': about}
    assert any(problem in p for p in check(one(why=[claim]), LIBRARY_DOC))


def test_a_claim_may_be_about_rules_sessions_and_a_session_s_exercise():
    claim = {
        'text': _t('Y'),
        'sources': ['acsm_2026'],
        'about': ['grows', 'rules.squat-barbell', 'sessions.a', 'sessions.a.squat-barbell', 'rest'],
    }
    assert check(one(why=[claim]), LIBRARY_DOC) == []


def test_safety_notes_and_next_programs_exist():
    assert any('no note' in p for p in check(one(safety=['be careful']), LIBRARY_DOC))
    assert any('not another program' in p for p in check(one(next=['nowhere']), LIBRARY_DOC))


def test_a_ladder_names_a_ladder_the_exercise_is_on_and_tops_out_with_it():
    rule = {'wall-push-up': {'kind': 'ladder', 'ladder': 'push', 'top': 12, 'bottom': 8}}
    ok = {'exercise': 'wall-push-up', 'sets': 3, 'target': {'reps': [8, 12]}}
    assert exercise(ok, rule) == []
    assert any('top out' in p for p in exercise({**ok, 'target': {'reps': [8, 10]}}, rule))
    assert any(
        'not on the pull ladder' in p
        for p in exercise(ok, {'wall-push-up': {**rule['wall-push-up'], 'ladder': 'pull'}})
    )


def test_an_open_slot_names_the_pattern_its_exercise_has():
    slot = {'exercise': 'lat-pulldown-cable', 'sets': 3, 'target': {'reps': [10, 20]}, 'total_reps': [50, 100]}
    assert exercise({**slot, 'pattern': 'vertical_pull'}) == []
    assert any('movement is' in p for p in exercise({**slot, 'pattern': 'horizontal_press'}))


def test_a_superset_has_a_partner():
    lone = {'exercise': 'bicep-curl-dumbbell', 'sets': 2, 'target': {'reps': [10, 15]}, 'superset': 1}
    assert any('one exercise' in p for p in exercise(lone))


def test_phases_name_sessions_and_only_the_last_runs_on():
    bad = one(phases=[{'name': _t('A'), 'sessions': ['a']}, {'name': _t('B'), 'sessions': ['a'], 'cycles': 2}])
    assert any('only the last phase runs on' in p for p in check(bad, LIBRARY_DOC))
    missing = one(phases=[{'name': _t('A'), 'sessions': ['zz']}])
    assert any("no session 'zz'" in p for p in check(missing, LIBRARY_DOC))


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
        'needs a rule that keeps a base' in p
        for p in exercise({'exercise': 'squat-barbell', 'sets': [{'share': 0.65, 'reps': 5}]}, {})
    )


def test_render_is_stable_and_in_the_template_shape():
    document = load(SOURCE)
    first, second = render(document), render(copy.deepcopy(document))
    assert first == second, 'ids must not change between renders'

    waves = next(p for p in first['programs'] if p['key'] == 'strength_waves')
    squat_day = next(s for s in waves['sessions'] if s['key'] == 'squat')
    squat = squat_day['exercises'][0]
    assert squat['exercise'] == {'key': 'squat-barbell'}
    assert squat['sets'][2]['target'] == {'share': 0.85, 'reps': {'min': 5}}
    assert squat['sets'][3]['target']['supplemental'] is True
    assert squat_day['exercises'][1]['pattern'] == 'vertical_pull'
    assert squat_day['exercises'][1]['totalReps'] == {'min': 50, 'max': 100}
    assert waves['rules']['squat-barbell']['kind'] == 'shareOfMax'
    assert 'weeks' not in waves, 'ongoing'
    test_lower = next(s for s in waves['sessions'] if s['key'] == 'test_lower')
    assert waves['phases'][0]['sessions'] == [test_lower['id'], waves['phases'][0]['sessions'][1]]
    assert waves['tests'][test_lower['id']] == {'share': 0.9}

    steps = next(p for p in first['programs'] if p['key'] == 'first_steps')
    assert steps['weeks'] == 8
    assert steps['i18n']['ru'] == 'Первые шаги'
    assert steps['rules']['wall-push-up']['rungs'][0] == 'wall-push-up'
    assert steps['who']['es'].startswith('Para empezar')
    assert {'acsm_2026', 'kotarsky_2018'} <= set(steps['sources'])
    assert first['sources']['acsm_2026']['url'].startswith('https://')
    assert first['safety']['mecfs']['sources'] == ['nice_mecfs']

    # claims are anchored where the program shows them, by the ids it uses
    plank = next(claim for claim in steps['why'] if 'lee_mcgill_2015' in claim['sources'])
    assert plank['about'] == [{'on': 'rule', 'exercise': 'plank'}]
    walk = next(p for p in first['programs'] if p['key'] == 'walk_and_move')
    otago = next(claim for claim in walk['why'] if 'otago_2022' in claim['sources'])
    strength = next(s for s in walk['sessions'] if s['key'] == 'strength')
    assert {'on': 'session', 'session': strength['id']} in otago['about']
    # and a source knows the programs that cite it
    assert 'first_steps' in first['sources']['acsm_2026']['usedBy']
    assert first['sources']['lee_mcgill_2015']['usedBy'] == ['first_steps']


def test_a_session_s_exercise_is_anchored_by_its_template_exercise_id():
    claim = {'text': _t('Y'), 'sources': ['acsm_2026'], 'about': ['sessions.a.squat-barbell']}
    rendered = render(one(why=[claim]))['programs'][0]
    exercise = rendered['sessions'][0]['exercises'][0]
    assert rendered['why'][0]['about'] == [
        {'on': 'exercise', 'session': rendered['sessions'][0]['id'], 'exercise': exercise['id']}
    ]


STAGES = {
    'kind': 'stages',
    'step': 2.5,
    'stages': [{'sets': 5, 'reps': 3, 'amrap': True}, {'sets': 6, 'reps': 2, 'amrap': True}],
}


def test_stages_hold_the_sets_to_the_first_stage():
    good = {'exercise': 'squat-barbell', 'sets': [{'reps': 3}] * 4 + [{'reps': '3+'}]}
    assert exercise(good, {'squat-barbell': STAGES}) == []
    wrong = {'exercise': 'squat-barbell', 'sets': 3, 'target': {'reps': 3}}
    assert any('the first stage, 5×3' in p for p in exercise(wrong, {'squat-barbell': STAGES}))
    one_stage = {**STAGES, 'stages': STAGES['stages'][:1]}
    assert any('stages is 2 to 20' in p for p in exercise(good, {'squat-barbell': one_stage}))


def _two_days(monday: dict, thursday: dict, rules: dict) -> dict:
    return one(
        rules=rules,
        sessions=[
            {'key': 'monday', 'name': _t('Mon'), 'exercises': [monday]},
            {'key': 'thursday', 'name': _t('Thu'), 'exercises': [thursday]},
        ],
    )


def test_an_occurrence_s_own_rule_is_checked_against_its_own_sets_and_rendered_by_its_id():
    heavy = {'exercise': 'squat-barbell', 'sets': [{'reps': 3}] * 4 + [{'reps': '3+'}]}
    volume = {
        'exercise': 'squat-barbell',
        'sets': 3,
        'target': {'reps': 10},
        'rule': {**STAGES, 'stages': [{'sets': 3, 'reps': 10}, {'sets': 3, 'reps': 8}]},
    }
    document = _two_days(heavy, volume, {'squat-barbell': STAGES})
    assert check(document, LIBRARY_DOC) == []
    rendered = render(document)['programs'][0]
    thursday = rendered['sessions'][1]['exercises'][0]
    assert rendered['rules'][thursday['id']]['stages'][0] == {'sets': 3, 'reps': 10}
    assert rendered['rules']['squat-barbell'] == STAGES

    wrong = {**volume, 'target': {'reps': 8}}
    assert any(
        'thursday.squat-barbell.rule' in p
        for p in check(_two_days(heavy, wrong, {'squat-barbell': STAGES}), LIBRARY_DOC)
    )


def test_a_share_of_one_occurrence_names_its_session_and_renders_its_id():
    heavy = {'exercise': 'squat-barbell', 'sets': 1, 'target': {'reps': 5}, 'rule': {'kind': 'addWeight', 'step': 2.5}}
    volume = {
        'exercise': 'squat-barbell',
        'sets': 5,
        'target': {'reps': 5, 'share': 0.9, 'of': 'squat-barbell', 'of_slot': 'monday'},
    }
    document = _two_days(heavy, volume, {})
    assert check(document, LIBRARY_DOC) == []
    rendered = render(document)['programs'][0]
    monday = rendered['sessions'][0]['exercises'][0]
    target = rendered['sessions'][1]['exercises'][0]['sets'][0]['target']
    assert target == {'reps': {'min': 5, 'max': 5}, 'share': 0.9, 'of': 'squat-barbell', 'ofSlot': monday['id']}

    nowhere = {**volume, 'target': {**volume['target'], 'of_slot': 'friday'}}
    assert any('must be a session doing' in p for p in check(_two_days(heavy, nowhere, {}), LIBRARY_DOC))
    unruled = {**heavy}
    del unruled['rule']
    assert any('no rule that keeps a base' in p for p in check(_two_days(unruled, volume, {}), LIBRARY_DOC))
    lone = {'exercise': 'squat-barbell', 'sets': 1, 'target': {'reps': 5, 'share': 0.9, 'of_slot': 'monday'}}
    assert any('of_slot goes with of' in p for p in check(_two_days(heavy, lone, {}), LIBRARY_DOC))


def test_an_occurrence_s_own_ladder_is_checked_against_its_own_exercise():
    ladder = {'kind': 'ladder', 'ladder': 'push', 'top': 12, 'bottom': 8}
    entry = {'exercise': 'push-up', 'sets': 3, 'target': {'reps': [8, 12]}, 'rule': ladder}
    plain = {'exercise': 'push-up', 'sets': 3, 'target': {'reps': [8, 12]}}
    assert not [p for p in check(_two_days(entry, plain, {}), LIBRARY_DOC) if 'ladder' in p]

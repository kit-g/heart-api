"""Balance pairs (scripts/balance_content.py, heart-api#270).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts -q
"""

import copy

from balance_content import LIBRARY, SOURCE, check, load, render

LIBRARY_DOC = load(LIBRARY)


def test_the_pairs_as_written_have_no_problems():
    assert check(load(SOURCE), LIBRARY_DOC) == []


def test_push_against_pull_and_hinge_against_squat():
    pairs = {pair['key']: pair for pair in render(load(SOURCE))['pairs']}
    assert 'horizontal_press' in pairs['push_pull']['left']['patterns']
    assert pairs['push_pull']['right']['patterns'] == ['horizontal_row', 'vertical_pull']
    assert pairs['hinge_squat']['left']['key'] == 'hinge'
    assert pairs['push_pull']['left']['name'] == {'en': 'Push', 'es': 'Empuje', 'fr': 'Poussée', 'ru': 'Жимы'}


def _with(**changes) -> dict:
    document = copy.deepcopy(load(SOURCE))
    document['pairs'][0]['right'].update(changes)
    return document


def test_a_pattern_the_library_lacks_is_refused():
    assert any('is not a library pattern' in p for p in check(_with(patterns=['rowing_sideways']), LIBRARY_DOC))


def test_a_pattern_on_both_sides_is_refused():
    assert any('on both sides' in p for p in check(_with(patterns=['horizontal_press']), LIBRARY_DOC))


def test_every_side_is_named_in_every_locale():
    assert any(
        'missing ru' in p for p in check(_with(name={'en': 'Pull', 'es': 'Tracción', 'fr': 'Tirage'}), LIBRARY_DOC)
    )


def test_a_side_carries_nothing_but_its_key_name_and_patterns():
    assert any('unknown' in p for p in check(_with(verdict={'en': 'Too much push'}), LIBRARY_DOC))


def test_what_render_reads_is_checked_first():
    document = copy.deepcopy(load(SOURCE))
    del document['locales'], document['version']
    problems = check(document, LIBRARY_DOC)
    assert any(p.startswith('version') for p in problems)
    assert any(p.startswith('locales') for p in problems)


def test_a_malformed_pair_or_pattern_is_a_problem_not_a_crash():
    assert any('patterns are pattern keys' in p for p in check(_with(patterns=[{'row': 1}]), LIBRARY_DOC))
    document = copy.deepcopy(load(SOURCE))
    document['pairs'].append('push_pull')
    document['pairs'][1]['key'] = {'hinge': 'squat'}
    problems = check(document, LIBRARY_DOC)
    assert any('a pair is' in p for p in problems)
    assert any('key must be snake_case' in p for p in problems)

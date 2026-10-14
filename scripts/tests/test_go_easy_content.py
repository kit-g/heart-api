""" "Go easy on" (scripts/go_easy_content.py, heart-api#236).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts -q
"""

from go_easy_content import LIBRARY, SOURCE, check, load, matches, render

LIBRARY_DOC = load(LIBRARY)
EXERCISES = LIBRARY_DOC['exercises']


def test_the_mapping_as_written_has_no_problems():
    assert check(load(SOURCE), LIBRARY_DOC) == []


def test_the_mapping_says_what_a_lifter_would_expect():
    document = load(SOURCE)

    def harder(section, key, exercise):
        return any(matches(p, EXERCISES[exercise]) for p in document[section][key]['easier'])

    assert harder('areas', 'lower_back', 'deadlift-barbell')
    assert not harder('areas', 'lower_back', 'leg-press')
    assert harder('areas', 'knee', 'jump-squat')
    assert harder('areas', 'shoulder', 'overhead-press-barbell')
    assert not harder('areas', 'shoulder', 'seated-row-cable')
    assert harder('areas', 'wrist', 'push-up')
    assert not harder('areas', 'wrist', 'bench-press-dumbbell')
    assert harder('movements', 'jumping', 'box-jump')
    assert harder('movements', 'overhead', 'seated-overhead-press-dumbbell')


def test_a_predicate_naming_what_the_library_lacks_is_refused():
    document = load(SOURCE)
    document['areas']['knee']['easier'] = [{'groups': ['knee_bending']}]
    assert any("'knee_bending' is not in the library" in p for p in check(document, LIBRARY_DOC))
    document['areas']['knee']['easier'] = [{'groups': ['vertical_press'], 'impact': ['high']}]
    assert any('matches no exercise' in p for p in check(document, LIBRARY_DOC))


def test_a_predicate_value_must_be_a_list():
    document = load(SOURCE)
    document['areas']['knee']['easier'] = [{'groups': 'vertical_press'}, {'impact': 'high'}]
    problems = check(document, LIBRARY_DOC)
    assert any('groups must be a non-empty list' in p for p in problems)
    assert any('impact must be a non-empty list' in p for p in problems)


def test_render_carries_copy_and_predicates():
    rendered = render(load(SOURCE))
    assert rendered['areas']['knee']['easierOn']['en'] == 'Easier on your knee'
    assert rendered['copy']['explainer']['ru']
    assert rendered['movements']['spine_load']['easier'] == [{'axialLoad': ['high']}], 'the wire names Movement uses'

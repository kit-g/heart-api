"""The title table built from an exporting app's catalog (scripts/import_names.py).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

from import_names import case_conflicts, hevy_names


def entry(title: str, archived: bool = False, **titles: str) -> dict:
    return {'title': title, 'is_archived': archived, **{f'{lang}_title': t for lang, t in titles.items()}}


def test_translated_titles_resolve_to_the_english_one():
    table, ambiguous = hevy_names(
        [entry('Bench Press (Barbell)', de='Bankdrücken (Langhantel)', ko='벤치 프레스 (바벨)')]
    )
    assert table == {'Bankdrücken (Langhantel)': 'Bench Press (Barbell)', '벤치 프레스 (바벨)': 'Bench Press (Barbell)'}
    assert ambiguous == []


def test_a_title_equal_to_any_english_title_is_left_out():
    # the archived Farmers Walk (Distance Duration) is called plain "Farmers
    # Walk" in German, which is the live exercise's English title
    table, _ = hevy_names(
        [
            entry('Farmers Walk', de='Farmers Walk'),
            entry('Farmers Walk (Distance Duration)', archived=True, de='Farmers Walk', fr='Marche du Fermier'),
        ]
    )
    assert 'Farmers Walk' not in table
    assert table['Marche du Fermier'] == 'Farmers Walk (Distance Duration)'


def test_a_shared_title_takes_the_first_live_exercise_in_catalog_order():
    table, ambiguous = hevy_names(
        [
            entry('Stair Machine', archived=True, es='Máquina Escaladora'),
            entry('Stair Machine (Floors)', es='Máquina Escaladora'),
            entry('Stair Machine (Steps)', es='Máquina Escaladora'),
            entry('Crunch', pl='Brzuszki'),
            entry('Sit Up', pl='Brzuszki'),
        ]
    )
    assert table == {'Máquina Escaladora': 'Stair Machine (Floors)', 'Brzuszki': 'Crunch'}
    assert ambiguous == [
        (
            'Máquina Escaladora',
            ['Stair Machine', 'Stair Machine (Floors)', 'Stair Machine (Steps)'],
            'Stair Machine (Floors)',
        ),
        ('Brzuszki', ['Crunch', 'Sit Up'], 'Crunch'),
    ]


def test_case_variants_are_one_title_unless_they_name_different_exercises():
    assert case_conflicts({'Squat (Langhantel)': 'Squat (Barbell)', 'Squat (langhantel)': 'Squat (Barbell)'}) == []
    assert case_conflicts({'Brzuszki': 'Crunch', 'brzuszki': 'Sit Up'}) == [('Brzuszki', 'brzuszki')]

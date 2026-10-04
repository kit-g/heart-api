"""Locale-overlay merge and digest behavior (scripts/library_locales.py).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

import pytest
from library_locales import (
    ARCHIVE_MISSING,
    UPSERT_EXERCISE,
    UPSERT_TRANSLATION,
    Library,
    merge_overlays,
    source_digest,
)
from validate_library import search_problems, search_words


def master(**overrides) -> dict:
    doc = {
        'version': '2026-08-29',
        'locales': ['en', 'en_CA', 'ru'],
        'fallback_to_default': 'en',
        'exercises': {
            'crunch': {
                'category': 'Reps Only',
                'target': 'Core',
                'i18n': {'en': {'name': 'crunch', 'instructions': 'Curl up.', 'validated': True}},
            },
        },
    }
    doc.update(overrides)
    return doc


def test_merge_folds_overlay_into_i18n():
    overlay = {
        'locale': 'ru',
        'exercises': {
            'crunch': {
                'name': 'Скручивания',
                'instructions': 'Поднимите корпус.',
                'validated': False,
                'source_digest': 'abcdef012345',
            },
        },
    }
    merged = merge_overlays(master(), [('ru.yml', overlay)])
    entry = merged['exercises']['crunch']['i18n']['ru']
    assert entry == {'name': 'Скручивания', 'instructions': 'Поднимите корпус.', 'validated': False}
    # bookkeeping stays in the overlay, never in the merged document
    assert 'source_digest' not in entry


def test_merged_document_parses_as_library():
    overlay = {'locale': 'ru', 'exercises': {'crunch': {'name': 'Скручивания'}}}
    library = Library.parse(merge_overlays(master(), [('ru.yml', overlay)]))
    localization = library.exercises['crunch'].localizations['ru']
    assert localization.is_concrete()
    assert localization.validated is False


def test_alias_entries_stay_non_concrete():
    overlay = {'locale': 'en_CA', 'exercises': {'crunch': {'name': 'crunch', 'fallback_to': 'en'}}}
    library = Library.parse(merge_overlays(master(), [('en_CA.yml', overlay)]))
    assert not library.exercises['crunch'].localizations['en_CA'].is_concrete()


@pytest.mark.parametrize(
    'filename,overlay,message',
    [
        ('ru.yml', {'locale': 'fr', 'exercises': {}}, 'expected'),
        ('fr.yml', {'locale': 'fr', 'exercises': {}}, 'not declared'),
        ('en.yml', {'locale': 'en', 'exercises': {}}, 'fallback locale'),
        ('ru.yml', {'locale': 'ru', 'exercises': {'typo': {'name': 'x'}}}, 'unknown exercise'),
    ],
)
def test_merge_rejects_bad_overlays(filename, overlay, message):
    with pytest.raises(ValueError, match=message):
        merge_overlays(master(), [(filename, overlay)])


def test_merge_rejects_locale_defined_in_both_places():
    doc = master()
    doc['exercises']['crunch']['i18n']['ru'] = {'name': 'Скручивания'}
    overlay = {'locale': 'ru', 'exercises': {'crunch': {'name': 'Скручивания'}}}
    with pytest.raises(ValueError, match='already defines'):
        merge_overlays(doc, [('ru.yml', overlay)])


def test_merge_reports_every_problem_at_once():
    overlay = {'locale': 'ru', 'exercises': {'typo-a': {'name': 'x'}, 'typo-b': {'name': 'y'}}}
    with pytest.raises(ValueError) as exc:
        merge_overlays(master(), [('ru.yml', overlay)])
    assert 'typo-a' in str(exc.value) and 'typo-b' in str(exc.value)


def test_source_digest_tracks_fallback_copy():
    before = source_digest('crunch', 'Curl up.')
    assert before == source_digest('crunch', 'Curl up.')
    assert before != source_digest('crunch', 'Curl up slowly.')
    assert len(before) == 12


def test_sync_identity_is_the_key_not_the_name():
    # the whole point of slug keys: a rename of the fallback copy must update
    # the row in place, so the upsert conflicts on key and updates name
    assert 'ON CONFLICT (key) WHERE user_id IS NULL' in UPSERT_EXERCISE
    assert 'name = EXCLUDED.name' in UPSERT_EXERCISE
    assert 'key <> ALL' in ARCHIVE_MISSING


def vocabulary_master(**overrides) -> dict:
    doc = master(
        locales=['en', 'es', 'es_ES'],
        glossary={'en': {'db': {'words': ['dumbbell']}, 'lats': {'muscles': ['latissimus_dorsi']}}},
        exercises={
            'lat-pulldown-cable': {
                'category': 'Machine',
                'target': 'Back',
                'muscles': {'primary': {'ids': ['latissimus_dorsi_l']}, 'secondary': {}},
                'i18n': {'en': {'name': 'Lat Pulldown (Cable)', 'aliases': ['pulldown']}},
            },
            'romanian-deadlift-dumbbell': {
                'category': 'Dumbbell',
                'target': 'Back',
                'i18n': {'en': {'name': 'Romanian Deadlift (Dumbbell)', 'aliases': ['rdl']}},
            },
            'romanian-deadlift-barbell': {
                'category': 'Barbell',
                'target': 'Back',
                'i18n': {'en': {'name': 'Romanian Deadlift (Barbell)', 'aliases': ['rdl']}},
            },
        },
    )
    doc.update(overrides)
    return doc


MUSCLE_GROUPS = {'back', 'hamstrings'}
MUSCLE_IDS = {'latissimus_dorsi_l', 'latissimus_dorsi_r', 'biceps_femoris_l'}


def test_merge_folds_overlay_glossary_by_locale():
    overlay = {'locale': 'es', 'glossary': {'dorsales': {'muscles': ['latissimus_dorsi']}}, 'exercises': {}}
    merged = merge_overlays(vocabulary_master(), [('es.yml', overlay)])
    assert merged['glossary']['es'] == {'dorsales': {'muscles': ['latissimus_dorsi']}}
    assert 'db' in merged['glossary']['en']


def test_merge_rejects_a_glossary_the_master_already_defines():
    overlay = {'locale': 'es', 'glossary': {'x': {'words': ['y']}}, 'exercises': {}}
    doc = vocabulary_master()
    doc['glossary']['es'] = {}
    with pytest.raises(ValueError, match='already defines the \'es\' glossary'):
        merge_overlays(doc, [('es.yml', overlay)])


def test_resolved_glossary_layers_fallback_base_then_own():
    doc = vocabulary_master()
    doc['glossary']['es'] = {'db': {'words': ['mancuerna']}, 'dorsales': {'muscles': ['latissimus_dorsi']}}
    doc['glossary']['es_ES'] = {'gemelos': {'muscles': ['gastrocnemius']}}
    library = Library.parse(doc)

    assert library.resolved_glossary('en') == doc['glossary']['en']
    es_es = library.resolved_glossary('es_ES')
    # a later locale's word replaces the fallback's
    assert es_es['db'] == {'words': ['mancuerna']}
    assert set(es_es) == {'db', 'lats', 'dorsales', 'gemelos'}


def test_aliases_parse_none_as_inherit_and_empty_as_none():
    doc = vocabulary_master()
    doc['exercises']['lat-pulldown-cable']['i18n']['es'] = {'name': 'Jalón', 'aliases': []}
    doc['exercises']['romanian-deadlift-barbell']['i18n']['es'] = {'name': 'Peso muerto rumano'}
    library = Library.parse(doc)
    assert library.exercises['lat-pulldown-cable'].localizations['es'].aliases == []
    assert library.exercises['romanian-deadlift-barbell'].localizations['es'].aliases is None
    assert library.exercises['romanian-deadlift-barbell'].localizations['en'].aliases == ['rdl']


def test_sync_writes_aliases():
    assert 'aliases = EXCLUDED.aliases' in UPSERT_EXERCISE
    assert 'aliases = EXCLUDED.aliases' in UPSERT_TRANSLATION


def test_search_words_mirror_the_app_normalization():
    assert search_words('Développé-Couché (Haltères)') == ['developpecouche', 'halteres']
    assert search_words('Жим лёжа') == ['жим', 'лежа']


def test_vocabulary_passes_when_sound():
    library = Library.parse(vocabulary_master())
    # rdl on both variants is the point, not a clash
    assert search_problems(library, MUSCLE_GROUPS, MUSCLE_IDS) == []


def test_an_alias_naming_another_exercise_is_a_problem():
    doc = vocabulary_master()
    doc['exercises']['romanian-deadlift-dumbbell']['i18n']['en']['aliases'] = ['lat pulldown (cable)']
    problems = search_problems(Library.parse(doc), MUSCLE_GROUPS, MUSCLE_IDS)
    assert any('is the name of lat-pulldown-cable' in p for p in problems)


def test_aliases_resolve_per_locale_like_names():
    doc = vocabulary_master()
    # es's own alias names an exercise only in es — the en name doesn't clash
    doc['exercises']['lat-pulldown-cable']['i18n']['es'] = {'name': 'Jalón al pecho'}
    doc['exercises']['romanian-deadlift-dumbbell']['i18n']['es'] = {'name': 'Rumano', 'aliases': ['jalón al pecho']}
    problems = search_problems(Library.parse(doc), MUSCLE_GROUPS, MUSCLE_IDS)
    assert [p.split(':')[0] for p in problems] == ['es', 'es_ES']


@pytest.mark.parametrize(
    ('word', 'term', 'message'),
    [
        ('lat', {'muscles': ['latissimus_dorsi']}, 'a word of the names it would shadow'),
        ('cable', {'words': ['dumbbell']}, 'a word of the names it would shadow'),
        ('two words', {'words': ['dumbbell']}, 'must be one lower-case word'),
        ('DB', {'words': ['dumbbell']}, 'must be one lower-case word'),
        ('kb', {'words': ['kettlebell']}, "stands for 'kettlebell', which no name has"),
        ('quads', {'muscles': ['quadriceps']}, 'not a muscle group or id'),
        ('hams', {'muscles': ['biceps_femoris']}, "no exercise's primary muscle"),
        ('hams', {'muscles': ['hamstrings']}, "no exercise's primary muscle"),
    ],
)
def test_glossary_problems(word, term, message):
    doc = vocabulary_master()
    doc['glossary']['en'][word] = term
    problems = search_problems(Library.parse(doc), MUSCLE_GROUPS, MUSCLE_IDS)
    assert any(message in p for p in problems), problems


def test_accented_glossary_words_are_fine():
    doc = vocabulary_master()
    doc['glossary']['es'] = {'glúteos': {'words': ['romanian']}}
    assert search_problems(Library.parse(doc), MUSCLE_GROUPS, MUSCLE_IDS) == []

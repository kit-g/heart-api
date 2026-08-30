"""Locale-overlay merge and digest behavior (scripts/library_locales.py).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

import pytest
from library_locales import Library, merge_overlays, source_digest


def master(**overrides) -> dict:
    doc = {
        'version': '2026-08-29',
        'locales': ['en', 'en_CA', 'ru'],
        'fallback_to_default': 'en',
        'exercises': {
            'Crunch': {
                'category': 'Reps Only',
                'target': 'Core',
                'i18n': {'en': {'name': 'Crunch', 'instructions': 'Curl up.', 'validated': True}},
            },
        },
    }
    doc.update(overrides)
    return doc


def test_merge_folds_overlay_into_i18n():
    overlay = {
        'locale': 'ru',
        'exercises': {
            'Crunch': {
                'name': 'Скручивания',
                'instructions': 'Поднимите корпус.',
                'validated': False,
                'source_digest': 'abcdef012345',
            },
        },
    }
    merged = merge_overlays(master(), [('ru.yml', overlay)])
    entry = merged['exercises']['Crunch']['i18n']['ru']
    assert entry == {'name': 'Скручивания', 'instructions': 'Поднимите корпус.', 'validated': False}
    # bookkeeping stays in the overlay, never in the merged document
    assert 'source_digest' not in entry


def test_merged_document_parses_as_library():
    overlay = {'locale': 'ru', 'exercises': {'Crunch': {'name': 'Скручивания'}}}
    library = Library.parse(merge_overlays(master(), [('ru.yml', overlay)]))
    localization = library.exercises['Crunch'].localizations['ru']
    assert localization.is_concrete()
    assert localization.validated is False


def test_alias_entries_stay_non_concrete():
    overlay = {'locale': 'en_CA', 'exercises': {'Crunch': {'name': 'Crunch', 'fallback_to': 'en'}}}
    library = Library.parse(merge_overlays(master(), [('en_CA.yml', overlay)]))
    assert not library.exercises['Crunch'].localizations['en_CA'].is_concrete()


@pytest.mark.parametrize(
    'filename,overlay,message',
    [
        ('ru.yml', {'locale': 'fr', 'exercises': {}}, 'expected'),
        ('fr.yml', {'locale': 'fr', 'exercises': {}}, 'not declared'),
        ('en.yml', {'locale': 'en', 'exercises': {}}, 'fallback locale'),
        ('ru.yml', {'locale': 'ru', 'exercises': {'Typo': {'name': 'x'}}}, 'unknown exercise'),
    ],
)
def test_merge_rejects_bad_overlays(filename, overlay, message):
    with pytest.raises(ValueError, match=message):
        merge_overlays(master(), [(filename, overlay)])


def test_merge_rejects_locale_defined_in_both_places():
    doc = master()
    doc['exercises']['Crunch']['i18n']['ru'] = {'name': 'Скручивания'}
    overlay = {'locale': 'ru', 'exercises': {'Crunch': {'name': 'Скручивания'}}}
    with pytest.raises(ValueError, match='already defines'):
        merge_overlays(doc, [('ru.yml', overlay)])


def test_merge_reports_every_problem_at_once():
    overlay = {'locale': 'ru', 'exercises': {'Typo A': {'name': 'x'}, 'Typo B': {'name': 'y'}}}
    with pytest.raises(ValueError) as exc:
        merge_overlays(master(), [('ru.yml', overlay)])
    assert 'Typo A' in str(exc.value) and 'Typo B' in str(exc.value)


def test_source_digest_tracks_fallback_copy():
    before = source_digest('Crunch', 'Curl up.')
    assert before == source_digest('Crunch', 'Curl up.')
    assert before != source_digest('Crunch', 'Curl up slowly.')
    assert len(before) == 12

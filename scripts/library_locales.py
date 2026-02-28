from dataclasses import dataclass
from typing import Self

import yaml


@dataclass
class ExerciseLocalization:
    localization_name: str
    exercise_name: str
    instructions: str | None
    fallback_to: str | None

    @classmethod
    def parse(cls, source: dict, name: str) -> Self:
        return cls(
            localization_name=name,
            exercise_name=source['name'],
            instructions=source.get('instructions'),
            fallback_to=source.get('fallback_to'),
        )

    def __post_init__(self):
        assert self.fallback_to or (self.instructions and self.exercise_name)

    def to_dict(self) -> dict:
        return {
            'name': self.exercise_name,
            **{'instructions': self.instructions if self.instructions else {}},
        }


@dataclass
class Exercise:
    name: str
    category: str
    target: str
    localizations: dict[str, ExerciseLocalization]
    fallback: str | None

    @classmethod
    def parse(cls, source: dict, name: str, global_fallback: str) -> Self:
        return cls(
            name=name,
            category=source['category'],
            target=source['target'],
            localizations={
                key: ExerciseLocalization.parse(value, key)
                for key, value in source.get('i18n', {}).items()
            },
            fallback=source.get('fallback') or global_fallback,
        )

    def localize(self, locale: str) -> dict:
        """
        Resolves the localization for a specific locale.
        Returns a dictionary compatible with the app's Exercise.fromJson constructor.
        """
        # determine the primary localization entry
        loc = self.localizations.get(locale)
        
        # resolve 'fallback_to' chain if it exists (e.g., en_CA -> en)
        if loc and loc.fallback_to:
            loc = self.localizations.get(loc.fallback_to)

        # if no locale match or alias found, use the default fallback (e.g., 'en')
        if not loc:
            loc = self.localizations.get(self.fallback)

        # if even the fallback is missing, we use the internal key as a last resort name
        return {
            'name': loc.exercise_name if loc else self.name,
            'category': self.category,
            'target': self.target,
            'instructions': loc.instructions if loc else None,
            'asset': None,
            'thumbnail': None,
        }


@dataclass
class Library:
    version: str
    locales: list[str]
    exercises: dict[str, Exercise]
    fallback_to: str

    @classmethod
    def parse(cls, source: dict) -> Self:
        fallback_to = source['fallback_to_default']
        return cls(
            version=source['version'],
            locales=source['locales'],
            exercises={
                key: Exercise.parse(ex, key, global_fallback=fallback_to)
                for key, ex in source['exercises'].items()
            },
            fallback_to=fallback_to,
        )

    def __post_init__(self):
        assert self.fallback_to, 'Fallback localization is required'

    def json_for_locale(self, locale: str) -> list[dict]:
        """
        Generates the full list of exercises for a specific locale.
        """
        return [
            ex.localize(locale)
            for ex in self.exercises.values()
        ]


def get_source() -> dict:
    with open('../content/exercise_library.yml', 'r') as f:
        return yaml.safe_load(f)


if __name__ == '__main__':
    import json
    import os

    raw = get_source()
    library = Library.parse(raw)
    
    output_dir = 'dist'
    os.makedirs(output_dir, exist_ok=True)

    for each in library.locales:
        localized = library.json_for_locale(each)

        with open(f'{output_dir}/exercises_{each.lower()}.json', 'w', encoding='utf-8') as f:
            json.dump({'exercises': localized}, f, ensure_ascii=False, indent=2)

        print(f'Generated {output_dir}/exercises_{each}.json')

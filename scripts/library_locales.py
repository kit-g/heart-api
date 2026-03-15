from dataclasses import dataclass
from typing import Self, Callable

import boto3
import yaml

s3 = boto3.client('s3')


def list_assets(bucket: str, prefix: str) -> list[str]:
    paginator = s3.get_paginator('list_objects_v2')
    iterator = paginator.paginate(Bucket=bucket, Prefix=prefix)
    return [item['Key'] for page in iterator for item in page['Contents']]


def sort_assets(assets: list[str], make_link: Callable[[str], str]) -> dict:
    by_name = {}
    for asset in assets:
        match asset.split('/'):
            case ['exercises', name, asset_type]:
                if name not in by_name:
                    by_name[name] = {}
                if asset_type.startswith('asset'):
                    by_name[name]['asset'] = {
                        'link': make_link(asset),
                        'width': None,  # for now
                        'height': None,
                    }
                if asset_type.startswith('thumbnail'):
                    by_name[name]['thumbnail'] = {
                        'link': make_link(asset),
                        'width': None,  # for now
                        'height': None,
                    }
            case _:
                raise ValueError(asset)

    return by_name


@dataclass
class MuscleRole:
    groups: list[str]
    ids: list[str]

    @classmethod
    def parse(cls, source: dict) -> Self:
        return cls(
            groups=source.get('groups', []),
            ids=source.get('ids', []),
        )

    def to_dict(self) -> dict:
        return {
            'groups': self.groups,
            'ids': self.ids,
        }


@dataclass
class Muscles:
    primary: MuscleRole
    secondary: MuscleRole

    @classmethod
    def parse(cls, source: dict | None) -> Self | None:
        if source is None:
            return None
        return cls(
            primary=MuscleRole.parse(source.get('primary', {})),
            secondary=MuscleRole.parse(source.get('secondary', {})),
        )

    def to_dict(self) -> dict:
        return {
            'primary': self.primary.to_dict(),
            'secondary': self.secondary.to_dict(),
        }


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
    muscles: Muscles | None
    localizations: dict[str, ExerciseLocalization]
    fallback: str | None

    @classmethod
    def parse(cls, source: dict, name: str, global_fallback: str) -> Self:
        return cls(
            name=name,
            category=source['category'],
            target=source['target'],
            muscles=Muscles.parse(source.get('muscles')),
            localizations={
                key: ExerciseLocalization.parse(value, key)
                for key, value in source.get('i18n', {}).items()
            },
            fallback=source.get('fallback') or global_fallback,
        )

    def localize(self, locale: str, get_asset: Callable[[str], dict]) -> dict:
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

        asset = get_asset(self.name) or {}

        # if even the fallback is missing, we use the internal key as a last resort name
        return {
            'name': loc.exercise_name if loc else self.name,
            'category': self.category,
            'target': self.target,
            'muscles': self.muscles.to_dict() if self.muscles else None,
            'instructions': loc.instructions if loc else None,
            'asset': asset.get('asset'),
            'thumbnail': asset.get('thumbnail'),
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

    def __getitem__(self, item):
        return self.exercises[item]

    def json_for_locale(self, locale: str, get_asset: Callable[[str], dict]) -> list[dict]:
        """
        Generates the full list of exercises for a specific locale.
        """
        return [
            ex.localize(locale, get_asset=get_asset)
            for ex in self.exercises.values()
        ]


def get_source() -> dict:
    with open('../content/exercise_library.yml', 'r') as f:
        return yaml.safe_load(f)


if __name__ == '__main__':
    import json
    import os

    _bucket = os.environ['BUCKET']
    _base_url = os.environ['BASE_URL']

    raw = get_source()
    library = Library.parse(raw)

    all_assets = list_assets(bucket=_bucket, prefix='exercises')
    sorted_assets = sort_assets(all_assets, make_link=lambda asset: f'{_base_url}/{asset}')

    output_dir = 'dist'
    os.makedirs(output_dir, exist_ok=True)

    for each in library.locales:
        localized = library.json_for_locale(each, get_asset=lambda name: sorted_assets.get(name))

        with open(f'{output_dir}/exercises_{each.lower()}.json', 'w', encoding='utf-8') as f:
            json.dump({'exercises': localized}, f, ensure_ascii=False, indent=2)

        print(f'Generated {output_dir}/exercises_{each}.json')

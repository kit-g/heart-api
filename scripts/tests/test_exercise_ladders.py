"""Variation ladders (content/exercise_ladders.yml, heart-api#231).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts
"""

import os

import yaml
from library_locales import content_dir

BODYWEIGHT = {'Reps Only', 'Weighted Body Weight', 'Assisted Body Weight'}


def load(name: str) -> dict:
    with open(os.path.join(content_dir(), name), encoding='utf-8') as f:
        return yaml.safe_load(f)


def test_every_rung_is_a_bodyweight_exercise_in_the_library():
    exercises = load('exercise_library.yml')['exercises']
    for key, rungs in load('exercise_ladders.yml')['ladders'].items():
        assert len(rungs) >= 2, f'{key}: a ladder has two rungs or more'
        assert len(set(rungs)) == len(rungs), f'{key}: each rung once'
        for rung in rungs:
            assert rung in exercises, f'{key}: {rung} is not in the library'
            assert exercises[rung]['category'] in BODYWEIGHT, f'{key}: {rung} is not a bodyweight exercise'

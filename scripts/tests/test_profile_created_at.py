"""Backfilling profiles.created_at (scripts/profile_created_at.py, heart-api#407).

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts -q
"""

from datetime import UTC, datetime
from types import SimpleNamespace

from profile_created_at import creation_times


def _user(uid: str, made: int | None) -> SimpleNamespace:
    return SimpleNamespace(uid=uid, user_metadata=SimpleNamespace(creation_timestamp=made))


def test_creation_times_are_utc_from_milliseconds():
    assert creation_times([_user('a', 1_700_000_000_123)]) == {
        'a': datetime(2023, 11, 14, 22, 13, 20, 123_000, tzinfo=UTC),
    }


def test_a_user_without_a_creation_time_is_left_out():
    assert creation_times([_user('a', None), _user('b', 0)]) == {'b': datetime(1970, 1, 1, tzinfo=UTC)}

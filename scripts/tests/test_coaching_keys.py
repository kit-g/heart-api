"""What scripts/coaching_keys.py stores reads back the way the API parses it
(MessageTags.parse in api/lib/notifications/sealing.dart): `id:base64` pairs,
comma-separated, newest first.

Run scoped: uv run pytest scripts/tests -o pythonpath=scripts -q
"""

import base64
from datetime import UTC, datetime

import pytest
from coaching_keys import tag_keys, valid_public_key
from open_report import generate

NOW = datetime(2026, 11, 8, 21, 30, tzinfo=UTC)


def pairs(value: str) -> list[tuple[str, bytes]]:
    return [(entry.split(':')[0], base64.b64decode(entry.split(':')[1])) for entry in value.split(',')]


def test_a_new_environment_gets_one_32_byte_key_named_for_the_minute():
    [(key_id, key)] = pairs(tag_keys(None, rotate=False, now=NOW))
    assert key_id == 'k202611082130'
    assert len(key) == 32


def test_keys_already_there_are_kept():
    assert tag_keys('k202611010000:' + base64.b64encode(b'x' * 32).decode(), rotate=False, now=NOW) is None


def test_rotating_puts_the_new_key_first_and_keeps_the_old():
    old = 'k202611010000:' + base64.b64encode(b'x' * 32).decode()
    rotated = tag_keys(old, rotate=True, now=NOW)
    assert [key_id for key_id, _ in pairs(rotated)] == ['k202611082130', 'k202611010000']
    assert rotated.endswith(old)


def test_two_rotations_in_one_minute_are_refused_rather_than_shadowing_a_key():
    once = tag_keys(None, rotate=False, now=NOW)
    with pytest.raises(SystemExit):
        tag_keys(once, rotate=True, now=NOW)


def test_a_review_key_is_a_32_byte_public_half():
    _, public = generate()
    assert valid_public_key(public)
    assert not valid_public_key('not base64!')
    assert not valid_public_key(base64.b64encode(b'short').decode())

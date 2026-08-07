"""
auth.delete_user tests. Mocks firebase_admin.auth and credential init so
nothing touches Firebase.
"""

import logging

import auth
import pytest
from firebase_admin import auth as fb_auth


@pytest.fixture
def patched(mocker):
    """Patch the Admin SDK call + credential init inside our auth module."""
    mocker.patch("auth.ensure_initialized")
    return mocker.patch("auth.auth.delete_user")


class TestDeleteUser:
    def test_deletes_by_uid(self, patched):
        auth.delete_user("u1")
        patched.assert_called_once_with("u1")

    def test_missing_user_is_a_noop(self, patched, caplog):
        # Idempotency contract: retried SQS deliveries must not fail the batch.
        patched.side_effect = fb_auth.UserNotFoundError("no such user")

        with caplog.at_level(logging.INFO, logger="auth"):
            auth.delete_user("ghost")  # must not raise

        patched.assert_called_once_with("ghost")
        assert any("already absent" in r.getMessage() for r in caplog.records)

    def test_other_sdk_errors_propagate(self, patched):
        # Anything else is a real failure — the handler marks the record failed.
        patched.side_effect = RuntimeError("FB down")

        with pytest.raises(RuntimeError, match="FB down"):
            auth.delete_user("u1")

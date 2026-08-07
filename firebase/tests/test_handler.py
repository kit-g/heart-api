"""
Handler-level routing tests. Mocks the FCM and Admin SDK calls so the test
doesn't hit Firebase.
"""

import json

import pytest


@pytest.fixture
def patched(mocker):
    """Patch both downstream side-effects so handler tests don't touch Firebase."""
    return {
        "send": mocker.patch("app.send_push"),
        "delete": mocker.patch("app.delete_user"),
    }


def _sqs_event(*bodies):
    return {
        "Records": [
            {"messageId": f"m-{i}", "body": json.dumps(b)} for i, b in enumerate(bodies)
        ]
    }


class TestDispatch:
    def test_push_notification_routes_to_notify(self, patched):
        from app import handler

        result = handler(
            _sqs_event(
                {
                    "type": "push.notification",
                    "tokens": ["t1"],
                    "title": "x",
                    "body": "y",
                }
            ),
            None,
        )
        assert result == {"batchItemFailures": []}
        patched["send"].assert_called_once()
        patched["delete"].assert_not_called()

    def test_account_delete_routes_to_auth(self, patched):
        from app import handler

        result = handler(
            _sqs_event({"type": "account.delete", "uid": "u1"}), None
        )
        assert result == {"batchItemFailures": []}
        patched["delete"].assert_called_once_with("u1")
        patched["send"].assert_not_called()

    def test_partial_batch_failure(self, patched):
        from app import handler

        # First record bad, second record fine — only the bad one in failures.
        result = handler(
            _sqs_event(
                {"type": "ghost"},
                {"type": "account.delete", "uid": "u2"},
            ),
            None,
        )
        ids = [f["itemIdentifier"] for f in result["batchItemFailures"]]
        assert ids == ["m-0"]
        patched["delete"].assert_called_once_with("u2")

    def test_handler_exception_marks_failure(self, mocker, patched):
        from app import handler

        patched["delete"].side_effect = RuntimeError("FB down")
        result = handler(
            _sqs_event({"type": "account.delete", "uid": "u1"}), None
        )
        ids = [f["itemIdentifier"] for f in result["batchItemFailures"]]
        assert ids == ["m-0"]

"""
notify.send_push tests. Mocks the FCM messaging layer and credential init
entirely so nothing touches Firebase.
"""

import logging

import notify
import pytest
from events import PushNotification


def _event(tokens, data=None):
    return PushNotification(
        tokens=list(tokens), title="t", body="b", data=data or {}
    )


def _batch(mocker, successes):
    """A BatchResponse-shaped mock: one SendResponse-shaped mock per flag."""
    responses = []
    for ok in successes:
        resp = mocker.Mock()
        resp.success = ok
        resp.exception = None if ok else RuntimeError("unregistered")
        responses.append(resp)
    batch = mocker.Mock()
    batch.responses = responses
    batch.success_count = sum(successes)
    batch.failure_count = len(successes) - batch.success_count
    return batch


@pytest.fixture
def fcm(mocker):
    """Patch the whole messaging module + credential init inside notify."""
    mocker.patch("notify.ensure_initialized")
    return mocker.patch("notify.messaging")


class TestEmptyTokens:
    def test_returns_without_sending(self, fcm):
        notify.send_push(_event([]))
        fcm.send_each_for_multicast.assert_not_called()
        fcm.MulticastMessage.assert_not_called()


class TestSuccessfulSend:
    def test_builds_message_from_event_and_sends_once(self, mocker, fcm):
        fcm.send_each_for_multicast.return_value = _batch(mocker, [True, True])

        notify.send_push(_event(["t1", "t2"], data={"commentId": "c-1"}))

        fcm.MulticastMessage.assert_called_once_with(
            tokens=["t1", "t2"],
            notification=fcm.Notification.return_value,
            data={"commentId": "c-1"},
        )
        fcm.Notification.assert_called_once_with(title="t", body="b")
        fcm.send_each_for_multicast.assert_called_once_with(
            fcm.MulticastMessage.return_value
        )

    def test_all_success_logs_no_warnings(self, mocker, fcm, caplog):
        fcm.send_each_for_multicast.return_value = _batch(mocker, [True])

        with caplog.at_level(logging.WARNING, logger="notify"):
            notify.send_push(_event(["t1"]))

        assert caplog.records == []


class TestPerTokenFailures:
    def test_logs_one_warning_per_failed_token(self, mocker, fcm, caplog):
        fcm.send_each_for_multicast.return_value = _batch(
            mocker, [True, False, False]
        )

        with caplog.at_level(logging.WARNING, logger="notify"):
            notify.send_push(_event(["token-ok", "token-bad-1", "token-bad-2"]))

        warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
        assert len(warnings) == 2
        # Only the token prefix goes to the log, never the full token.
        assert "token-ba" in warnings[0].getMessage()
        assert "token-ok" not in warnings[0].getMessage()
        assert "unregistered" in warnings[0].getMessage()


class TestResponseCountInvariant:
    def test_mismatched_response_count_raises(self, mocker, fcm):
        # zip(strict=True) guards the token↔response pairing; a short response
        # list from FCM must blow up loudly, not silently mis-attribute.
        fcm.send_each_for_multicast.return_value = _batch(mocker, [True])

        with pytest.raises(ValueError):
            notify.send_push(_event(["t1", "t2"]))

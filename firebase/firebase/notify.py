"""FCM send wrapper. Pure dumb pipe — the upstream API decides who gets
notified, in what language, with what title and body. This module just calls
FCM with the pre-baked payload."""

import logging

from firebase_admin import messaging

from creds import ensure_initialized
from events import PushNotification

log = logging.getLogger(__name__)


def send_push(event: PushNotification) -> None:
    ensure_initialized()
    if not event.tokens:
        log.info("no tokens; skipping push")
        return

    message = messaging.MulticastMessage(
        tokens=event.tokens,
        notification=messaging.Notification(title=event.title, body=event.body),
        data=event.data,
    )
    response = messaging.send_each_for_multicast(message)
    log.info(
        "FCM multicast: %d ok, %d failed (of %d)",
        response.success_count,
        response.failure_count,
        len(event.tokens),
    )

    for token, resp in zip(event.tokens, response.responses, strict=True):
        if not resp.success:
            # TODO: stale-token cleanup. The API will purge on next registration
            # anyway, so for now this is just signal. Add a callback if churn
            # gets noisy.
            log.warning("FCM failure for token %s…: %s", token[:8], resp.exception)
"""FCM send wrapper. Pure dumb pipe — the upstream API decides who gets
notified, in what language, with what title and body. This module just calls
FCM with the pre-baked payload."""

import logging
from typing import Any

from creds import ensure_initialized
from events import PushNotification
from firebase_admin import messaging

log = logging.getLogger(__name__)


def _delivery(event: PushNotification) -> dict[str, Any]:
    """How the message travels. A silent push wakes the app and shows nothing, so
    both platforms treat it as background work at low priority."""
    if event.silent:
        return {
            "android": messaging.AndroidConfig(priority="normal", collapse_key=event.collapse_key),
            "apns": messaging.APNSConfig(
                headers={"apns-push-type": "background", "apns-priority": "5"},
                payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)),
            ),
        }
    return {
        "notification": messaging.Notification(title=event.title, body=event.body),
        "android": messaging.AndroidConfig(
            collapse_key=event.collapse_key,
            notification=messaging.AndroidNotification(channel_id=event.channel),
        ),
    }


def send_push(event: PushNotification) -> None:
    ensure_initialized()
    if not event.tokens:
        log.info("no tokens; skipping push")
        return

    message = messaging.MulticastMessage(
        tokens=event.tokens,
        data=event.data,
        **_delivery(event),
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
            # Just signal: the database drops tokens that have gone quiet.
            log.warning("FCM failure for token %s…: %s", token[:8], resp.exception)

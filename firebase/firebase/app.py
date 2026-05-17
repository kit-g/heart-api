"""
SQS-triggered Lambda entry point. Dispatches each record to its event
handler. Failed records are reported via partial-batch response so SQS only
retries the ones that errored, not the whole batch.
"""

import json
import logging
from typing import Any

from auth import delete_user
from events import AccountDelete, Event, PushNotification, parse_event
from notify import send_push

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def handler(event: dict[str, Any], _) -> dict[str, Any]:
    failures: list[dict[str, str]] = []
    for record in event.get("Records", []):
        message_id = record.get("messageId", "?")
        try:
            body = json.loads(record["body"])
            _dispatch(parse_event(body))
        except Exception:
            log.exception("record %s failed", message_id)
            failures.append({"itemIdentifier": message_id})
    return {"batchItemFailures": failures}


def _dispatch(event: Event) -> None:
    match event:
        case PushNotification():
            send_push(event)
        case AccountDelete():
            delete_user(event.uid)
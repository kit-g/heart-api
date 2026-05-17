"""Firebase Auth user lifecycle."""

import logging

from firebase_admin import auth

from creds import ensure_initialized

log = logging.getLogger(__name__)


def delete_user(uid: str) -> None:
    """Idempotent: a missing user is treated as a no-op."""
    ensure_initialized()
    try:
        auth.delete_user(uid)
        log.info("deleted FB Auth user %s", uid)
    except auth.UserNotFoundError:
        log.info("FB Auth user %s already absent", uid)

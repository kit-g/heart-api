"""Lazy Firebase Admin SDK init.

The SA key is baked into the container image at deploy time (the deploy workflow
fetches it from S3 once and COPYs it in), so runtime cold starts pay no S3
latency or per-invocation GetObject billing. Image rotation = key rotation.
"""

import os

import firebase_admin
from firebase_admin import credentials

_CRED_PATH = os.environ.get("FIREBASE_CRED_PATH", "/var/task/firebase.json")


def ensure_initialized() -> firebase_admin.App:
    if firebase_admin._apps:
        return firebase_admin.get_app()
    return firebase_admin.initialize_app(credentials.Certificate(_CRED_PATH))

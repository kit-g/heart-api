#!/usr/bin/env python3
"""Opens a report's sealed words, which only the holder of the private key can do.

Usage: REPORT_REVIEW_PRIVATE_KEY=<base64> scripts/open_report.py < sealed.txt

Generate the pair with --generate. The public half goes in REPORT_REVIEW_KEY on
the API, and the private half stays off every server.

The format is what api/lib/notifications/sealing.dart writes.
"""

import base64
import os
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


def generate() -> tuple[str, str]:
    """A new pair, as (private, public), base64."""
    private = X25519PrivateKey.generate()
    return (
        base64.b64encode(
            private.private_bytes(
                serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()
            )
        ).decode(),
        base64.b64encode(
            private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        ).decode(),
    )


def open_sealed(sealed: str, private_key: str) -> str:
    raw = base64.b64decode(sealed)
    ephemeral, nonce, box = raw[:32], raw[32:44], raw[44:]
    shared = X25519PrivateKey.from_private_bytes(base64.b64decode(private_key)).exchange(
        X25519PublicKey.from_public_bytes(ephemeral)
    )
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=b"heart-report").derive(shared)
    return ChaCha20Poly1305(key).decrypt(nonce, box, None).decode()


if __name__ == "__main__":
    if "--generate" in sys.argv:
        private, public = generate()
        print(f"private: {private}\npublic:  {public}")
    else:
        print(open_sealed(sys.stdin.read().strip(), os.environ["REPORT_REVIEW_PRIVATE_KEY"]))

"""The script opens what the API seals. The fixture was written by
api/lib/notifications/sealing.dart with the private key below."""

import base64
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location("open_report", Path(__file__).parent.parent / "open_report.py")
open_report = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(open_report)


def test_it_opens_what_the_api_sealed():
    # a throwaway pair, used for nothing else
    sealed = "eK4he6cpv4uyXS4bLubBPopcc6EMno+aYt8OnQw4ii1IDNPFg1Ge6Fnj1oTmY7g9wO1xkohiAR+vu5vVaZX8nHtZh2ZUnnQHrSb4HM9rbw=="
    private = "AFqMMM/gnt6MAqUESQEsuTP9VSYqzRsRCEl4ISIseWY="
    assert open_report.open_sealed(sealed, private) == '[{"words":"words"}]'


def test_a_generated_pair_is_32_bytes_each():
    private, public = open_report.generate()
    assert len(base64.b64decode(private)) == 32
    assert len(base64.b64decode(public)) == 32

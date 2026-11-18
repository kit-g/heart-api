#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = ["segno==1.6.6"]
# ///
"""Writes the QR code on the home page, site/assets/get-app-qr.svg.

Usage:
    uv run scripts/site_qr.py

It encodes https://heart-of.me/get.html, which sends a phone to its own store.
Prod's address on every environment: dev mirrors prod's pages, and a code is
scanned by a phone that is meant to end up in a store anyway.

Error correction M and the standard four-module quiet zone, dark on white with
the white drawn in, so it reads the same on the page's dark ground. Run it again
only when the address changes; the output is committed.
"""

from pathlib import Path

import segno

URL = 'https://heart-of.me/get.html'
OUT = Path(__file__).resolve().parent.parent / 'site' / 'assets' / 'get-app-qr.svg'


def main() -> None:
    segno.make(URL, error='m', micro=False, boost_error=False).save(
        OUT,
        kind='svg',
        border=4,
        dark='#000',
        light='#fff',
        xmldecl=False,
        omitsize=True,
        nl=True,
    )
    print(f'wrote {OUT}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Draws a QR code as a heart, in the site's blue and ink, as an SVG.

Usage:
    uv run python scripts/heart_qr.py URL OUT.svg [--seed TEXT]

The heart is the classic construction: a square standing on one corner with a
half-disc on each of its two upper sides. The square is the code itself, turned
135° anticlockwise so that its three finder patterns sit at the heart's tip and sides and the
corner without one points into the notch. The half-discs hold decorative tiles on
the same grid, which a scanner reads as noise outside the code. No tile comes
within two modules of a finder pattern, so the finders stay easy to find.

The tiles are random but seeded from the URL (or --seed), and segno is locked in
uv.lock, so drawing the same address twice gives the same file. The file names its
address in a comment, so a code can be checked against the link beside it. The
colours are the default preset's accent and ink, from shared/heart_design/tokens.json.
"""

import argparse
import json
import math
import random
from pathlib import Path

import segno

TOKENS = json.loads((Path(__file__).parent.parent / 'shared/heart_design/tokens.json').read_text())
PALETTE = TOKENS['presets'][TOKENS['default']]['light']
BLUE = PALETTE['accent']
INK = PALETTE['ink']
TILE = 0.96  # a module's tile, in modules: a hair of gap between neighbours
ROUND = 0.2  # its corner radius
PAD = 2  # white margin around the tiles, in modules: the quiet zone on a dark page
DENSITY = 0.5  # share of decorative cells that get a tile
CLEAR = 2  # decoration-free distance around a finder, in modules
ANGLE = -135


def num(f: float) -> str:
    """A number for a path: two decimals, which every grid coordinate fits, without trailing zeros."""
    return f'{f:.2f}'.rstrip('0').rstrip('.')


def circle(x: float, y: float, r: float) -> str:
    """Clockwise, like rounded(), so overlapping shapes add up under the nonzero rule."""
    x, y, r, d = num(x - r), num(y), num(r), num(2 * r)
    return f'M{x} {y}a{r} {r} 0 1 1 {d} 0a{r} {r} 0 1 1 -{d} 0Z'


def rounded(x: float, y: float, size: float, r: float) -> str:
    x, y, s, r = num(x + r), num(y), num(size - 2 * r), num(r)
    arc = f'a{r} {r} 0 0 1'
    return f'M{x} {y}h{s}{arc} {r} {r}v{s}{arc} -{r} {r}h-{s}{arc} -{r} -{r}v-{s}{arc} {r} -{r}Z'


def tile(x: int, y: int) -> str:
    """One module, as a use of the tile drawn once in defs: the file stays small with a thousand of them."""
    return f'<use href="#t" x="{x}" y="{y}"/>'


def heart(n: int, pad: float) -> str:
    """The silhouette in the code's own frame, grown by pad: the square and the discs on its right and bottom sides."""
    return rounded(-pad, -pad, n + 2 * pad, pad) + circle(n, n / 2, n / 2 + pad) + circle(n / 2, n, n / 2 + pad)


def draw(url: str, seed: str) -> str:
    qr = segno.make(url, error='m', boost_error=True, micro=False)
    matrix = [list(row) for row in qr.matrix]
    n = len(matrix)
    finders = [(0, 0), (n - 7, 0), (0, n - 7)]

    def in_finder(x: int, y: int, margin: int = 0) -> bool:
        return any(fx - margin <= x < fx + 7 + margin and fy - margin <= y < fy + 7 + margin for fx, fy in finders)

    tiles, finder = [], []
    for y, row in enumerate(matrix):
        for x, dark in enumerate(row):
            if dark and not in_finder(x, y):
                tiles.append(tile(x, y))
    for fx, fy in finders:
        finder.append(rounded(fx, fy, 7, 2.2))
        finder.append(rounded(fx + 1, fy + 1, 5, 1.4))  # evenodd: the hole in the ring
        finder.append(rounded(fx + 2, fy + 2, 3, 0.9))

    rng = random.Random(seed)
    r = n / 2
    discs = [(n, n / 2), (n / 2, n)]  # right and bottom sides, which end up on top
    reach = math.ceil(n * 1.5)
    for y in range(reach):
        for x in range(reach):
            if x < n and y < n:
                continue
            cx, cy = x + 0.5, y + 0.5
            if not any(math.dist((cx, cy), d) <= r - 0.5 for d in discs):
                continue
            if in_finder(x, y, CLEAR):
                continue
            if rng.random() < DENSITY:
                tiles.append(tile(x, y))

    # Turn the code frame by ANGLE about its centre, then fit the view box to the heart.
    silhouette = heart(n, PAD)
    a = math.radians(ANGLE)
    c = n / 2

    def turn(x: float, y: float) -> tuple[float, float]:
        dx, dy = x - c, y - c
        return c + dx * math.cos(a) - dy * math.sin(a), c + dx * math.sin(a) + dy * math.cos(a)

    corners = [(0, 0), (n, 0), (0, n), (n, n)]
    rims = [(*corner, PAD) for corner in corners] + [(*d, r + PAD) for d in discs]
    edge = [
        turn(x + rr * math.cos(k * math.pi / 90), y + rr * math.sin(k * math.pi / 90))
        for x, y, rr in rims
        for k in range(180)
    ]
    xs, ys = [p[0] for p in edge], [p[1] for p in edge]
    x0, y0, w, h = min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)
    side = max(w, h)
    x0 -= (side - w) / 2
    y0 -= (side - h) / 2
    t = f'rotate({ANGLE} {c} {c})'
    box = f'x="{num(x0)}" y="{num(y0)}" width="{num(side)}" height="{num(side)}"'

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{num(x0)} {num(y0)} {num(side)} {num(side)}">'
        f'<!-- {url}, drawn by scripts/heart_qr.py -->'
        '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse"'
        f' x1="{num(x0)}" x2="{num(x0 + side)}" y1="0" y2="0">'
        f'<stop offset="0" stop-color="{BLUE}"/><stop offset="1" stop-color="{INK}"/></linearGradient>'
        f'<path id="t" d="{rounded((1 - TILE) / 2, (1 - TILE) / 2, TILE, ROUND)}"/>'
        f'<mask id="m"><g transform="{t}" fill="#fff"><path fill-rule="evenodd" d="{"".join(finder)}"/>'
        f'{"".join(tiles)}</g></mask></defs>'
        f'<path transform="{t}" fill="#fff" d="{silhouette}"/>'
        f'<rect {box} fill="url(#g)" mask="url(#m)"/>'
        '</svg>\n'
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('url')
    parser.add_argument('out')
    parser.add_argument('--seed', help='seeds the decorative tiles; the URL by default')
    args = parser.parse_args()
    with open(args.out, 'w') as f:
        f.write(draw(args.url, args.url if args.seed is None else args.seed))


if __name__ == '__main__':
    main()

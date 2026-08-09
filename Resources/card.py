#!/usr/bin/env python3
# draws the picture on the about card
# one color per cell terminals paint each row separately and anything finer than a cell seams

"""The about card: one full-page picture with the text living inside it.

Called by about.sh with the real terminal size, because a page that fills the
window cannot be a saved picture, it has to be drawn at the size it is being
shown at. Prints ANSI to stdout and nothing else.

The technique, and the one rule everything follows from, is in
docs/full-page-art.md: a cell holds EITHER a picture pixel OR one glyph. A text
cell paints its background from whatever the scene would have been underneath
it, so the words sit in the sky instead of on a strip above it.

ONE COLOUR PER CELL, and the pixel is therefore twice as tall as it is wide
(2026-08-04). The first version used half blocks for double the vertical
resolution and it shipped with a hairline seam across every single row: the
terminal fills a row's background as its own rectangle, and when the view's
height is not a whole number of pixels those rectangles do not quite meet.
Painting a solid block whose foreground AND background are the same colour
cannot show a seam, because there is no second colour for a gap to reveal.
Everything horizontal is scaled by PIXEL_ASPECT to keep the drawing from
looking stretched.

Exits 2 if the window is too small to hold the layout, which is about.sh's
signal to print the plain card instead.
"""

from __future__ import annotations

import argparse
import sys

MIN_COLS, MIN_ROWS = 74, 20

# A cell is about twice as tall as it is wide, and a pixel is now one cell, so
# anything measured against height has to be doubled to come out square.
PIXEL_ASPECT = 2

# Where the tower stands, and where the type has to stop. Both were written
# as bare 0.63s in two different functions, which is how the licence line came
# to run clean through the observation deck: the layout believed it was staying
# out of the tower's way and only the brain path was ever actually measured
# against it (2026-08-08). One number now, used by the drawing and by the type.
TOWER_X = 0.63
# The legs flare wide at the base, so the type stops well short of where the
# tower's centre line is. Everything typed lives left of this and nothing
# crosses it, which is what makes the page read as two columns instead of one
# pile with a tower behind it.
TYPE_EDGE = 0.54

Px = tuple[int, int, int]


def mix(a: Px, b: Px, t: float) -> Px:
    t = max(0.0, min(1.0, t))
    return (
        round(a[0] + (b[0] - a[0]) * t),
        round(a[1] + (b[1] - a[1]) * t),
        round(a[2] + (b[2] - a[2]) * t),
    )


# ---------------------------------------------------------------------------
# The scene
# ---------------------------------------------------------------------------

NIGHT = (0x12, 0x14, 0x2C)
DUSK = (0xE8, 0x8A, 0x60)
HAZE = (0x2A, 0x21, 0x40)
FAR = (0x3A, 0x3E, 0x60)
NEAR = (0x1E, 0x22, 0x40)
GROUND = (0x10, 0x12, 0x22)
LIT = (0xFA, 0xCE, 0x82)
LIT_DIM = (0xC4, 0x96, 0x60)
HOT = (0xEE, 0x6E, 0x33)
HOT_D = (0xC9, 0x55, 0x24)
BAND = (0xF2, 0xE8, 0xDC)
BEACON = (0xFF, 0xE9, 0xB8)

# Deterministic. A picture that comes out different every time it is drawn is a
# picture nobody can review, so the scatter is written down rather than rolled.
# One cell each, dim, and only in the top few rows. They were two cells wide
# and seventy percent white, which on a narrow window punched harder than the
# tower did and parked one of them in the middle of the version block.
STARS = [0.07, 0.16, 0.29, 0.44, 0.58, 0.71, 0.83, 0.94]
STAR_ROWS = [1, 3, 0, 2, 1, 3, 0, 2]
SKYLINE = [
    # (start, width, height) as fractions of the page, back layer then front
    (0.00, 0.08, 0.30), (0.09, 0.06, 0.36), (0.16, 0.09, 0.24), (0.26, 0.05, 0.40),
    (0.32, 0.08, 0.28), (0.41, 0.06, 0.38), (0.75, 0.08, 0.34), (0.84, 0.06, 0.26),
    (0.91, 0.09, 0.38),
]
BLOCKS = [
    (0.03, 0.09, 0.22), (0.13, 0.07, 0.30), (0.21, 0.10, 0.17), (0.33, 0.06, 0.25),
    (0.70, 0.09, 0.20), (0.80, 0.07, 0.31), (0.89, 0.09, 0.16),
]


def build_tokyo(cols: int, prows: int) -> list[list[Px]]:
    grid = [[(0, 0, 0)] * cols for _ in range(prows)]
    for y in range(prows):
        shade = mix(NIGHT, DUSK, (y / (prows - 1)) ** 1.6)
        for x in range(cols):
            grid[y][x] = shade

    # Thinned on a narrow window, where the same count reads as debris.
    keep = len(STARS) if cols >= 96 else max(4, len(STARS) // 2)
    for frac, row in list(zip(STARS, STAR_ROWS))[:keep]:
        x = int(frac * (cols - 1))
        if row >= prows:
            continue
        # The type owns the upper left, and a star is a whole painted CELL, so
        # one that lands in there is not a distant point of light, it is a grey
        # rectangle parked in the middle of a word. Two were sitting on the
        # title and one across "menu-bar" (2026-08-08). Row zero is above every
        # line of type, so it stays open the whole way across.
        if row >= 1 and x < int(cols * TYPE_EDGE):
            continue
        # Dimmer than it was, for the same reason: a cell-sized star at nearly
        # forty percent white was outshining the tower's own beacon.
        grid[row][x] = mix((0xFF, 0xFA, 0xEB), grid[row][x], 0.74)

    # Below the horizon the sky stops being sky. Without this the warm gradient
    # runs to the bottom of the page and the tower's legs stand on a bright
    # wash instead of against dark ground.
    horizon = prows * 0.62
    for y in range(int(horizon), prows):
        # Clamped low as well as high: int(horizon) floors, so the first row of
        # this loop sits a hair ABOVE the horizon and a negative fraction
        # raised to a power stops being a real number.
        t = max(0.0, min(1.0, (y - horizon) / max(1.0, prows - horizon - 2)))
        for x in range(cols):
            grid[y][x] = mix(grid[y][x], HAZE, (t ** 0.7) * 0.92)

    def box(x: int, y: int, w: int, h: int, colour: Px) -> None:
        for r in range(max(y, 0), min(y + h, prows)):
            for c in range(max(x, 0), min(x + w, cols)):
                grid[r][c] = colour

    for start, width, height in SKYLINE:
        top = prows - int(height * prows)
        box(int(start * cols), top, max(2, int(width * cols)), prows, FAR)

    windows: list[tuple[int, int]] = []
    for start, width, height in BLOCKS:
        x, w = int(start * cols), max(3, int(width * cols))
        top = prows - int(height * prows)
        box(x, top, w, prows, NEAR)
        # Lit windows on a lattice, skipping some so it never looks printed.
        for wy in range(top + 2, prows - 2, 3):
            for wx in range(x + 1, x + w - 1, 3):
                if (wx * 7 + wy * 13) % 5 < 2:
                    windows.append((wx, wy))
    for i, (wx, wy) in enumerate(windows):
        grid[wy][wx] = LIT_DIM if i % 4 == 0 else LIT

    # LAST, so it stands in front of the near buildings. It used to be drawn
    # before them and one of the near blocks punched a dark rectangle straight
    # through its lower right leg (2026-08-08), which reads as a hole in the
    # subject rather than as a building in front of it. The tower is the whole
    # reason this picture exists; nothing gets to occlude it.
    draw_tower(grid, cols, prows, box)

    box(0, prows - 2, cols, 2, GROUND)
    return grid


def draw_tower(grid, cols: int, prows: int, box) -> None:
    """Tokyo Tower, and the point is that it can only be Tokyo Tower.

    Three features carry the recognition and none of them are optional: the
    WIDE main observatory shelf partway up, the small upper observatory above
    it, and legs that curve outward with open sky between them. Drop any one
    and it reads as a rocket, which is what the first attempt did.
    """
    tx = int(cols * TOWER_X)
    bottom = prows - 3
    height = int(prows * 0.78)
    top = bottom - height

    def hbar(y: int, half: int, colour: Px, x0: int | None = None, x1: int | None = None) -> None:
        if not 0 <= y < prows:
            return
        a = tx - half if x0 is None else x0
        b = tx + half if x1 is None else x1
        for x in range(max(a, 0), min(b + 1, cols)):
            grid[y][x] = colour

    mast = max(2, int(height * 0.125))
    upper = max(1, int(height * 0.05))
    shaft = max(2, int(height * 0.175))
    deck = max(1, int(height * 0.075))

    y = top
    for _ in range(mast):
        hbar(y, 0, HOT)
        y += 1
    hbar(top, 0, BEACON)
    hbar(top + 1, 0, BEACON)

    hbar(y, 1, BAND)
    y += 1
    for _ in range(upper):
        hbar(y, 1, HOT)
        y += 1
    for _ in range(shaft):
        hbar(y, 1, HOT)
        y += 1

    deck_half = max(4, int(height * 0.13 * PIXEL_ASPECT))
    hbar(y, deck_half, BAND)
    y += 1
    for _ in range(max(1, deck - 1)):
        hbar(y, deck_half, HOT)
        y += 1
    hbar(y, deck_half - 1, HOT_D)
    y += 1

    leg_top, leg_bot = y, bottom
    span = max(1, leg_bot - leg_top)
    flare = max(6, int(height * 0.18 * PIXEL_ASPECT))
    previous = 0
    for i in range(span + 1):
        row = leg_top + i
        t = i / span
        # Monotonic on purpose: a leg that steps back inward for one row reads
        # as a rendering fault, which is what the mockup did at its very base.
        outer = max(previous, int(round(3 + flare * (t ** 1.35))))
        previous = outer
        thick = 3 if t < 0.45 else 4
        colour = BAND if (0.34 < t < 0.42) or (0.72 < t < 0.80) else HOT
        for x in range(tx - outer, tx - outer + thick):
            if 0 <= x < cols:
                grid[row][x] = colour
        for x in range(tx + outer - thick + 1, tx + outer + 1):
            if 0 <= x < cols:
                grid[row][x] = colour
        if i in (int(span * 0.20), int(span * 0.50), int(span * 0.82)):
            hbar(row, 0, HOT_D, tx - outer + thick, tx + outer - thick)

    # Where the legs meet the ground, so they land instead of fading out.
    box(tx - previous, bottom, 2 * previous + 1, 2, HOT_D)


# ---------------------------------------------------------------------------
# Type
# ---------------------------------------------------------------------------

INK_TITLE = (0xFF, 0xFF, 0xFF)
INK_BODY = (0xE6, 0xEA, 0xF2)
INK_MUTED = (0x93, 0x9C, 0xB6)
INK_LINK = (0xF0, 0xA0, 0x70)
INK_CLOSE = (0xC8, 0xB9, 0xA8)


def wide(ch: str) -> bool:
    """A CJK glyph occupies TWO cells. Painting it into one clips it in half,
    which is exactly what happened to the kanji the first time round."""
    v = ord(ch)
    return (
        0x1100 <= v <= 0x115F
        or 0x2E80 <= v <= 0xA4CF
        or 0xAC00 <= v <= 0xD7A3
        or 0xF900 <= v <= 0xFAFF
        or 0xFF00 <= v <= 0xFF60
    )


def clip_left(text: str, limit: int) -> str:
    """The brain path is the one row whose width nobody controls. Keep the
    tail, which is the half that says where you are."""
    return text if len(text) <= limit else "…" + text[-(limit - 1):]


def layout(cols: int, rows: int, args) -> list[tuple[int, int, str, Px, bool]]:
    label = 4
    value = label + 13
    # Type never crosses the tower: the flattening a text cell costs is
    # invisible on sky and obvious over detail. Every line obeys this now, not
    # just the brain path. The licence used to be one sixty-four character
    # sentence that ran straight through the observation deck, which is the
    # single thing that made the page look like it had been dropped rather than
    # composed. It is two lines, and both of them fit the column.
    right = int(cols * TYPE_EDGE)
    room = right - value
    named = f'  "{args.place}"' if args.place else ""
    return [
        (2, label, "凛  Rin", INK_TITLE, True),
        (3, label, "A menu-bar home for Claude Code.", INK_MUTED, False),
        (6, label, "version", INK_MUTED, False),
        (6, value, args.version, INK_TITLE, True),
        (6, value + len(args.version) + 1, f"{named}  (build {args.build})".strip(), INK_MUTED, False),
        (7, label, "engine", INK_MUTED, False),
        (7, value, clip_left(args.engine, room), INK_BODY, False),
        (8, label, "brain", INK_MUTED, False),
        (8, value, clip_left(args.brain, room), INK_BODY, False),
        # No how-to rows. The panel shortcut lived here until 2026-08-09
        # (Peter: the about card is an authenticity plate, "like how limited
        # cars have cool plaques"); instructions belong to the menu row that
        # does the thing and to the shortcuts card, which names both keys.
        (11, label, "Free and open source, MIT licensed.", INK_MUTED, False),
        (12, label, "Bundles SwiftTerm, also MIT.", INK_MUTED, False),
        (13, label, "github.com/exata531/Rin", INK_LINK, False),
        (rows - 2, label, "press return to close this tab", INK_CLOSE, False),
    ]


# Which places have been drawn. scripts/check-version.py reads this to decide
# whether a new release line is allowed to open, so a city named in about.sh
# with nothing drawn for it fails the build rather than shipping a blank page.
PLACES = {"tokyo": build_tokyo}


def render(cols: int, rows: int, args) -> str:
    prows = rows  # one pixel per cell; see the seam note at the top
    grid = PLACES[args.place.lower()](cols, prows)

    # None means "picture here". A tuple is (glyph, ink); False is the second
    # half of a wide glyph, which the cursor has already been advanced over.
    cells: list[list[object]] = [[None] * cols for _ in range(rows)]
    for row, col, text, ink, bold in layout(cols, rows, args):
        if not 0 <= row < rows:
            continue
        x = col
        for ch in text:
            span = 2 if wide(ch) else 1
            if x + span > cols:
                break
            cells[row][x] = (ch, ink, bold)
            if span == 2:
                cells[row][x + 1] = False
            x += span

    out: list[str] = []
    for r in range(rows):
        fg = bg = None
        line: list[str] = []
        for c in range(cols):
            cell = cells[r][c]
            if cell is False:
                continue
            if cell is None:
                # Same colour twice: a full block over a background of its own
                # colour, so a row boundary has nothing to reveal.
                top = bottom = grid[r][c]
                glyph = "█"
            else:
                ch, ink, bold = cell  # type: ignore[misc]
                top = ink
                bottom = grid[r][c]
                glyph = ch
                if bold:
                    line.append("\x1b[1m")
                    fg = None
            if top != fg:
                line.append(f"\x1b[38;2;{top[0]};{top[1]};{top[2]}m")
                fg = top
            if bottom != bg:
                line.append(f"\x1b[48;2;{bottom[0]};{bottom[1]};{bottom[2]}m")
                bg = bottom
            line.append(glyph)
            if cell is not None and cell[2]:  # type: ignore[index]
                line.append("\x1b[22m")
        line.append("\x1b[0m")
        out.append("".join(line))
    # No trailing newline on the last row: one row too many scrolls the top of
    # the page away and the whole thing stops being one page.
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--version", default="?")
    parser.add_argument("--build", default="?")
    parser.add_argument("--place", default="")
    parser.add_argument("--engine", default="not installed")
    parser.add_argument("--brain", default="not chosen yet")
    args = parser.parse_args()

    if args.cols < MIN_COLS or args.rows < MIN_ROWS:
        sys.exit(2)
    if args.place.lower() not in PLACES:
        sys.exit(2)
    sys.stdout.write(render(args.cols, args.rows, args))


if __name__ == "__main__":
    main()

# Drawing a full page in a terminal, with the text inside the picture

How the about card becomes one image instead of a banner with rows under it.
Written 2026-08-04 before building it, so the constraints were on paper rather
than discovered halfway through, and it shipped the same day in
`Resources/card.py`. Everything below held.

## The one constraint everything follows from

**A terminal cell holds either a picture pixel or one letter. Never both.**

A cell showing the letter `R` has spent its foreground on the letter. Its
background is still free, and that is the whole seam.

So the page is composited **per cell**, in two kinds:

    picture cell   ESC[38;2;<c>m ESC[48;2;<c>m █      same colour twice
    text cell      ESC[38;2;<ink>m ESC[48;2;<scene>m <glyph>

A text cell takes its background from what the scene would have been at that
spot. The letters then look painted onto the sky rather than printed on a strip
above it. The cost is one cell's worth of detail per letter, which is invisible
against a gradient and obvious against fine detail.

### Why not half blocks

The obvious move is `▀`, which splits a cell into a foreground half and a
background half and so carries two pixels per cell
([this is how high-end ANSI art gets its resolution](https://en.wikipedia.org/wiki/ANSI_art)).
It was built that way first, and it shipped with **a hairline seam across every
row of the page**.

The cause is not the escape codes. A terminal paints each row's background as
its own rectangle, and when the view's height is not a whole number of device
pixels those rectangles do not quite meet. With half blocks the two halves of a
cell are different colours, so the sliver at the boundary has something to
reveal. Painting a full block whose foreground and background are the SAME
colour cannot show a seam, because there is no second colour behind it.

The cost is real: vertical resolution halves, and a pixel becomes twice as tall
as it is wide. Every horizontal measurement derived from height gets multiplied
by `PIXEL_ASPECT` to keep the drawing from looking stretched, and single-cell
details like stars are drawn two cells wide or they read as tally marks.

The lesson generalises: **a technique that is correct in theory can still be
wrong on the screen it has to survive.** Draw it, install it, look at it.

Consequences worth stating plainly:

- **Type belongs on smooth areas.** Open sky, water, a wall. Never across a
  skyline edge or window lights, where the flattening shows.
- **Contrast is per line, against a gradient.** The sky changes colour down the
  page, so a label that reads at the top can disappear four rows lower. Check
  the ink against the actual scene colour under each line, not against an
  average.
- **Reserve the rows first, then draw.** Decide where type goes, then compose
  the picture so nothing important lives under it.

## Making it one page

- **Generate at the real terminal size.** A fixed `.ans` cannot fill a window
  whose size it does not know. Read `COLUMNS` and `LINES` when the card opens
  and draw to that, which means the scene has to be procedural rather than a
  saved picture. The generator already builds Tokyo from a gradient and a list
  of buildings, so it takes a size.
- **Exactly as many rows as the terminal has, and no trailing newline on the
  last one.** One row too many scrolls the top away and the illusion dies.
- **Every row painted edge to edge.** Any cell left unpainted shows the
  terminal's own background and reads as a hole.
- **Reset at the end of each row** so a colour cannot bleed into the next.
- **Count printable characters only when placing text.** Escape sequences are
  zero width. This is exactly what fastfetch does with its own width counter to
  keep art and text columns aligned
  ([ASCII logo system](https://deepwiki.com/fastfetch-cli/fastfetch/4.1.1-ascii-logo-system)).
- **Redraw on resize** if the tab can change size while open, or accept that
  the card is drawn once at the size it opened with.

## The layout

Sky across the top two thirds, city along the bottom, type floating in the sky:

    ┌──────────────────────────────────────────────┐
    │  凛  Rin                            · · ·    │  title, high, in dark sky
    │  A menu-bar home for Claude Code.            │
    │                                              │
    │  version   1.11.1  "Tokyo"  (build 20)       │  the block, still in sky
    │  engine    Claude Code 2.1.221               │
    │  brain     ~/…/Documents/Peter               │
    │  panel     control + `                       │
    │                                              │
    │  Free and open source, MIT licensed.         │
    │  github.com/exata531/Rin                     │
    │                          ▂                   │
    │              ▄▄         ███        ▄▄        │  skyline rises into the
    │   ▄▄  ████   ███   ████  ▄▄  ████  ███       │  bottom of the type block
    │  press return to close this tab   ████       │  last line over dark ground
    └──────────────────────────────────────────────┘

The rules and separators go away. A framed table inside a picture is two
designs arguing; the picture is the frame now.

## What breaks it

- A brain path longer than the window. It is the one variable-width row, and it
  is why the card never had a box around it in the first place. Truncate from
  the left with a leading ellipsis so the tail, which is the useful half,
  survives.
- A very short window. Below a floor the type does not fit over the sky, and
  the honest answer is to fall back to the current banner-plus-rows card rather
  than draw something cramped.
- Light terminal themes. The card paints its own background everywhere, so it
  is dark regardless, which is fine and deliberate.

## Sources

- [ANSI art, and why half blocks](https://en.wikipedia.org/wiki/ANSI_art)
- [fastfetch's ASCII logo system, on width counting and alignment](https://deepwiki.com/fastfetch-cli/fastfetch/4.1.1-ascii-logo-system)
- [Moebius, a half-block ANSI editor, for what the medium can do](https://blocktronics.github.io/moebius/)

# Version numbers, and the places they are named after

Rebuilt 2026-08-04 to follow [Semantic Versioning](https://semver.org/) after
Peter sent the sources and said to follow them rather than the scheme he had
given the same morning.

## The number

    MAJOR . MINOR . PATCH [ -N ]
    │       │       │       └── pre-release, sorts BEFORE the patch it names
    │       │       └────────── a bug fix, backwards compatible
    │       └────────────────── a feature, backwards compatible
    └────────────────────────── a break, or a milestone. Named after a city.

**Rin is 0.x, and 0.x means unfinished.** Semver reserves major version zero
for initial development, where anything may change: private repo, zero
releases, handed around as a zip. **1.0.0 is the public release**, and it is
Tokyo (Peter, 2026-08-04). That is what the leading zero is buying, a number
left for the day it actually ships.

It used to say 1.11.3, which told a stranger the app was eleven feature
releases into a stable life. It was not. The renumber to 0.11.3 on 2026-08-04
is the only time this version will ever go backwards.

A fourth component (`major.minor.build.revision`) is a real scheme, Microsoft's,
and [Wikipedia lists it beside
semver](https://en.wikipedia.org/wiki/Software_versioning#Schemes). It is not
semver, and semver is what the other two sources point at, so a step smaller
than a patch is a **pre-release**: `0.11.4-1` sorts before `0.11.4` and lands as
`0.11.4` when it is done.

## Nobody types a number

    python3 scripts/release.py                      a fix      0.11.3 -> 0.11.4
    python3 scripts/release.py --feature            a feature  0.11.4 -> 0.12.0
    python3 scripts/release.py --pre                under a fix          -> 0.11.5-1
    python3 scripts/release.py --era --place Kyoto  a new era            -> 1.0.0

A fix is the DEFAULT and takes no argument, because it is what most sessions
are doing. The script writes both numbers into `project.yml` and regenerates
the Xcode project, which is a step that is easy to forget and ships the old
version when you do.

The build number is the commit count, plus the commits squashed away when the
repo went public (a constant in `scripts/release.py`), so it never re-treads a
number that already shipped. It is never typed, never reused, and
[must only ever increase, which is the one hard rule every store
enforces](https://developer.apple.com/library/archive/qa/qa1827/_index.html).

**An era has to be asked for by name and is refused unless its city has already
been drawn.** Reaching 1.0.0 therefore means drawing a city on purpose first.
That is the point: this is the shape every release tool arrives at, which is to
take the number out of the hands of whoever is feeling good about the day's
work ([semantic-release puts it as removing the connection between human
emotions and version
numbers](https://semantic-release.gitbook.io/semantic-release/support/faq)).

**Not every change earns a number.** A cosmetic fix too small to name can ship
on the version already installed, with `./install.sh --force`. Peter, on the
star fix: "this doesnt deserve a version number."

## The build enforces it

`scripts/check-version.py` runs as a pre-build phase, so a bad version cannot
become an app even if nobody knew the rule existed. It fails the build, with
the reason, when either of these is true:

- The version opens an era with no city named for it, or names a city whose
  drawing does not exist.
- The version moved and the build number did not, which means somebody typed it
  by hand instead of running the script.

Run it yourself with `python3 scripts/check-version.py --work`.

Deliberately NOT a git hook: hooks are the vault assistant's territory, and this
is the app's rule, so it lives in the app's build.

## Installing is the second gate

The build check catches a number that is *wrong*. It cannot catch a number that
simply never moved, because a session that changes code and bumps nothing
produces a perfectly valid build carrying the old version.

So `install.sh` refuses a build whose version and build number already match
what is in `/Applications`, and tells you to bump. Installing is the moment a
number starts mattering: everything before it is an experiment, and this is the
step that puts a build in front of a person. `./install.sh --force` overrides
it, for reinstalling and for changes too small to name.

While wiring that up, 2026-08-04: `install.sh` had been reading only the repo's
own `build/` directory, and `xcodebuild` with no `-derivedDataPath` writes to
DerivedData instead. A build made the documented way was invisible to the
installer, which quietly installed whatever was last built in-repo, over a week
stale by the time anyone looked. It now takes the newest build of the two and
says which one it took.

## The places

**Every era is a place in Japan, and the about card draws it.** The name hangs
off the MAJOR version, so every fix and feature inside an era keeps the same
city.

| Era | Place | |
|---|---|---|
| 0.x | Tokyo | the run-up |
| 1.x | Tokyo | the public release (Peter, 2026-08-04) |
| 2.x | not chosen | |

0.x and 1.x share Tokyo on purpose: 0.x is the same app on its way to shipping,
so the card wears the city it is heading for rather than going blank until
launch day. **An unnamed era draws nothing** and the card falls back to its
plain header, with no place on the version row either. Shipping must never be
blocked on choosing a city, and a placeholder drawing would be worse than none.

## How the drawing works

`Resources/card.py` draws the whole card: the city, and the text sitting inside
it, generated at the size of the window it is being shown in. Each place is a
function in its `PLACES` registry, which is also what the version check reads to
decide whether an era is allowed to open. Full technique, and the rules for
drawing a new place, in [full-page-art.md](full-page-art.md).

- **One colour per cell, foreground and background both.** Half blocks would
  double the vertical resolution and they seam: a row's background is painted as
  its own rectangle, and those rectangles do not quite meet. A full block over
  its own colour has nothing to reveal at the boundary. The pixel is therefore
  twice as tall as it is wide, and horizontal measurements get scaled to match.
- **24-bit colour, not the 256 palette.** `ESC[38;2;r;g;b` and
  `ESC[48;2;r;g;b`. Truecolor is what buys the gradient sky; the 256-colour
  palette cannot hold one without banding.
- **Nothing is random.** Window lights and stars are written-out lists. A
  picture that comes out different every run is a picture nobody can review.

Draw a new one by adding a function to `PLACES` in `Resources/card.py` and
naming the era in `Resources/about.sh`. The build check will not let an era open
until both are true.

**Tokyo took three passes to become unmistakable.** A skyline with a spike on it
reads as a rocket; what makes it Tokyo Tower is the wide observatory shelf
partway up, the smaller one above it, and legs that curve outward with open sky
between them. Whatever gets drawn next needs the same test: cover the caption and
ask whether anybody could name the place.

## Release notes

Every version that ships gets an entry in `CHANGELOG.md` naming what changed.
[Not "bug fixes and stability
improvements"](https://uxcam.com/blog/app-versioning-best-practices/), say
which bug and what it did.

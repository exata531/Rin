#!/usr/bin/env python3
# stops me hand typing a version number
# the build fails instead of shipping something that lies about which release it is

"""Refuse a version change that broke the rule. Runs as a build phase.

A rule written in a document is a rule somebody has to go and read. This is
the same rule as a wall: it runs whether or not anybody knew it existed, and
it says what it wants in the failure message rather than pointing at a file.
It lives in the BUILD, so a bad version cannot become an app.

Two things it will not let through:

1. **A new era with no city drawn.** Every major version is named after a place
   the about card draws, so opening 2.x means 2.x has a city and the art for it
   exists. This is what stops an afternoon's work from being called an era.
2. **A hand-edited version.** The build number is the commit count, written by
   scripts/release.py. If the version moved and the build did not, the number
   was typed rather than bumped, and the next thing to go wrong is a build
   number that repeats.

    python3 scripts/check-version.py --work   what the build runs
    python3 scripts/check-version.py          checks the staged change instead
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_RE = re.compile(r'CFBundleShortVersionString:\s*"([^"]+)"')
BUILD_RE = re.compile(r'CFBundleVersion:\s*"([^"]+)"')


def git(*args: str) -> str:
    out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return out.stdout


def field(text: str, pattern: re.Pattern[str]) -> str | None:
    match = pattern.search(text)
    return match.group(1) if match else None


def era(version: str) -> str:
    return version.partition("-")[0].split(".")[0]


def main() -> None:
    staged = "--work" not in sys.argv
    before = git("show", "HEAD:project.yml")
    after = git("show", ":project.yml") if staged else (ROOT / "project.yml").read_text()
    if not after:
        return  # project.yml is not part of this commit

    old, new = field(before, VERSION_RE), field(after, VERSION_RE)
    if not new or old == new:
        return

    problems = []

    if era(old or "") != era(new):
        major = era(new)
        about = (ROOT / "Resources" / "about.sh").read_text()
        place = re.search(
            rf'^\s*(?:[\d|]*\|)?{re.escape(major)}(?:\|[\d|]*)?\)\s*place="([^"]+)"',
            about,
            flags=re.M,
        )
        if not place:
            problems.append(
                f"{new} opens era {major}.x, and no city is named for it.\n"
                "  Every major version is named after a place the about card draws, and a\n"
                "  major bump means a break or a milestone, not a good afternoon. If this\n"
                "  really is a new era, draw the city and use\n"
                "  scripts/release.py --era --place <Name>. Otherwise you wanted\n"
                "  scripts/release.py (a fix) or --feature."
            )
        elif f'"{place.group(1).lower()}"' not in (ROOT / "Resources" / "card.py").read_text():
            problems.append(
                f"{major}.x is named {place.group(1)} but that city has not been drawn.\n"
                "  Add a scene to PLACES in Resources/card.py first. The rules for\n"
                "  drawing one are in docs/full-page-art.md."
            )

    if field(before, BUILD_RE) == field(after, BUILD_RE):
        problems.append(
            f"the version moved to {new} and the build number did not.\n"
            "  Nobody types either one. Run scripts/release.py and let it do both."
        )

    if problems:
        # "error:" is what makes Xcode surface these in the build log rather
        # than swallowing them, so the reason arrives with the failure.
        for problem in problems:
            first, *rest = problem.splitlines()
            print(f"error: {first}")
            for line in rest:
                print(line)
        print("error: the version rule is in docs/versions.md")
        sys.exit(1)


if __name__ == "__main__":
    main()

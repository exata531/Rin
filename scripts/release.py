#!/usr/bin/env python3
# cuts a release
# this is the only thing allowed to move the version numbers

"""Bump Rin's version. Nobody edits project.yml by hand.

The problem this solves is not arithmetic, it is judgement: a hand-typed
version means whoever is at the keyboard decides how big the work felt, and
one afternoon's work becomes a new release line. Release tooling everywhere
answers this by computing the number from declared intent instead of asking
for it. This is that, sized for one repo.

    python3 scripts/release.py                  a fix           0.11.3 -> 0.11.4
    python3 scripts/release.py --feature        a new feature   0.11.4 -> 0.12.0
    python3 scripts/release.py --pre            a step under a fix
                                                                0.11.4 -> 0.11.5-1
    python3 scripts/release.py --era --place Kyoto
                                                a new era       0.11.4 -> 1.0.0

The words are Semantic Versioning's, and the scheme is its MAJOR.MINOR.PATCH
(semver.org): a fix is a patch, a backwards-compatible feature is a minor, and
a break or a milestone is a major. A fix is the DEFAULT and takes no argument,
because it is what most sessions are doing.

**An era needs a city and is refused without one.** Every major version is
named after a place in Japan that the about card draws (docs/versions.md), so
opening one means drawing a city first, which nobody does on the way past.

The build number is never typed either. It is the commit count, which only
goes up and cannot be forgotten.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "project.yml"
ABOUT = ROOT / "Resources" / "about.sh"
CARD = ROOT / "Resources" / "card.py"

VERSION_RE = re.compile(r'(CFBundleShortVersionString:\s*")([^"]+)(")')
BUILD_RE = re.compile(r'(CFBundleVersion:\s*")([^"]+)(")')


def parse(version: str) -> tuple[list[int], int]:
    """MAJOR.MINOR.PATCH with an optional -N pre-release counter."""
    core, _, pre = version.partition("-")
    parts = [int(p) for p in core.split(".")]
    while len(parts) < 3:
        parts.append(0)
    return parts[:3], int(pre) if pre.isdigit() else 0


# The pre-1.0 history was squashed to a single commit when the repo went
# public (2026-08-09). Its 111 commits still count here, so the build number
# keeps climbing instead of re-treading numbers that already shipped.
SQUASHED_COMMITS = 111


def commit_count() -> int:
    out = subprocess.run(
        ["git", "rev-list", "--count", "HEAD"], cwd=ROOT, capture_output=True, text=True
    )
    return SQUASHED_COMMITS + int(out.stdout.strip() or 0)


def named_eras(text: str) -> dict[str, str]:
    """The major versions about.sh already has a city for."""
    return dict(re.findall(r"^\s*(\d+)\)\s*place=\"([^\"]+)\"", text, flags=re.M))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    step = parser.add_mutually_exclusive_group()
    step.add_argument("--pre", action="store_true", help="a pre-release step under a fix")
    step.add_argument("--feature", action="store_true", help="a backwards-compatible feature")
    step.add_argument("--era", action="store_true", help="a new major version; needs --place")
    parser.add_argument("--place", help="the city for a new era, already drawn")
    args = parser.parse_args()

    text = PROJECT.read_text()
    match = VERSION_RE.search(text)
    if not match:
        sys.exit("project.yml has no CFBundleShortVersionString")
    (major, minor, patch), pre = parse(match.group(2))

    if args.era:
        if not args.place:
            sys.exit(
                "a new era needs a city: --era --place <Name>.\n"
                "Every major version is named after a place the about card draws."
            )
        if f'"{args.place.lower()}"' not in CARD.read_text():
            sys.exit(
                f"{args.place} has not been drawn yet, so this era cannot open.\n"
                "Add a scene to PLACES in Resources/card.py first; the rules for drawing\n"
                "one are in docs/full-page-art.md.\n"
                "That is deliberate. A version bump this size should cost more than one command."
            )
        major, minor, patch, pre = major + 1, 0, 0, 0
        about = ABOUT.read_text()
        if str(major) not in named_eras(about):
            entry = f'  {major}) place="{args.place}" ;;\n'
            ABOUT.write_text(
                re.sub(r'^(\s*\*\)\s*place="" ;;)', entry + r"\1", about, count=1, flags=re.M)
            )
            print(f"about.sh now draws {args.place} for {major}.x")
    elif args.feature:
        minor, patch, pre = minor + 1, 0, 0
    elif args.pre:
        # A pre-release sorts BEFORE the version it carries, so it counts up
        # toward the next patch rather than hanging off the last one.
        if pre:
            pre += 1
        else:
            patch, pre = patch + 1, 1
    else:
        if pre:
            pre = 0  # the pre-release lands as the real thing
        else:
            patch += 1

    version = f"{major}.{minor}.{patch}" + (f"-{pre}" if pre else "")
    build = str(commit_count())

    text = VERSION_RE.sub(lambda m: m.group(1) + version + m.group(3), text, count=1)
    text = BUILD_RE.sub(lambda m: m.group(1) + build + m.group(3), text, count=1)
    PROJECT.write_text(text)
    print(f"version {version}, build {build}")

    if subprocess.run(["which", "xcodegen"], capture_output=True).returncode == 0:
        subprocess.run(["xcodegen", "generate"], cwd=ROOT, capture_output=True)
        print("project regenerated")
    else:
        print("xcodegen is missing, so run it before building or the old number ships")


if __name__ == "__main__":
    main()

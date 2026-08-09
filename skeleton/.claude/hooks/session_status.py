#!/usr/bin/env python3
"""session_status.py, SessionStart hook: what a session needs to know before it speaks.

A panel that opens knowing nothing has to ask the person to catch it up, and being asked
to repeat yourself to your own notes is the fastest way to stop using them. So a session
opens already holding the small facts: whether setup finished, whether yesterday ever got
written down, what is sitting unfiled, and whether a note was left for later.

Deliberately short. This is context, not a briefing, and a long one just pushes the
conversation further from the voice. Everything here is read off the folder; nothing is
computed twice and nothing is invented.

Contract: on ANY failure, print nothing and exit 0.
"""

import json
import re
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUEUE = Path.home() / "Library/Application Support/Rin/nudges.json"

# Found only by whoever opens a lot of sessions. One in roughly twenty, stable for a
# whole day so it never flickers mid-afternoon, and never on a line that carries a fact.
ASIDES = [
    "the folder is exactly where you left it. it always is. you're welcome.",
    "no notes were harmed in the making of this session.",
    "everything is fine. suspiciously fine. I'm watching it.",
    "the inbox and I have an understanding. it stays small, I stay calm.",
    "somebody has to keep the books around here, and it is not going to be you.",
]


def setup_done():
    try:
        text = (ROOT / "_meta" / "setup-state.md").read_text(encoding="utf-8").lower()
    except Exception:
        return True  # no state file: assume a working folder rather than nagging
    return "complete" in text and "incomplete" not in text


def last_card():
    folder = ROOT / "_meta" / "memories"
    best = None
    try:
        for f in folder.glob("*.md"):
            m = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", f.stem)
            if not m:
                continue
            d = date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            if best is None or d > best:
                best = d
    except Exception:
        return None
    return best


def warmth():
    try:
        text = (ROOT / "_meta" / "lore.md").read_text(encoding="utf-8")
    except Exception:
        return None
    m = re.search(r"warmth.*?\*\*(\d)\*\*", text, re.I | re.S)
    return m.group(1) if m else None


def inbox_count():
    try:
        return sum(1 for f in (ROOT / "00-inbox").glob("*.md") if f.name.lower() != "readme.md")
    except Exception:
        return 0


def queued_nudge():
    try:
        entries = json.loads(QUEUE.read_text(encoding="utf-8"))
    except Exception:
        return None
    now = datetime.now().astimezone()
    upcoming = []
    for e in entries:
        try:
            when = datetime.fromisoformat(e["fireAt"])
            if when.tzinfo is None:
                when = when.astimezone()
            if when > now:
                upcoming.append((when, e.get("text", "")))
        except Exception:
            continue
    if not upcoming:
        return None
    when, text = sorted(upcoming)[0]
    return f"{when:%a %H:%M}: {text[:60]}"


def main():
    lines = []
    today = date.today()

    if not setup_done():
        lines.append("setup has not finished. Run the setup skill before anything else, "
                     "whatever the first message says.")
    else:
        card = last_card()
        if card is None:
            lines.append("no day cards yet. Nothing has been written down about any day "
                         "together, so there is no history to call back to. Do not invent one.")
        else:
            gap = (today - card).days
            if gap == 0:
                lines.append("today already has a card.")
            elif gap == 1:
                lines.append("yesterday has a card. Today does not yet.")
            else:
                lines.append(f"last day card was {gap} days ago ({card}). "
                             "Quiet stretches are normal and are not a reason to manufacture one.")

        w = warmth()
        if w:
            lines.append(f"warmth sits at {w} of 5. Open in the mood the ledger left, "
                         "softened by the days since.")

        n = inbox_count()
        if n:
            lines.append(f"{n} unfiled note{'s' if n > 1 else ''} in 00-inbox.")

        q = queued_nudge()
        if q:
            lines.append(f"a note is already queued for later ({q}). One at a time: "
                         "a new one replaces it.")

    if not lines:
        sys.exit(0)

    # The aside rides the day, not the session, so it cannot repeat within an afternoon.
    if today.toordinal() % 19 == 0:
        lines.append(ASIDES[today.toordinal() // 19 % len(ASIDES)])

    print("Where things stand (read off the folder by .claude/hooks/session_status.py):")
    for line in lines:
        print(f"- {line}")
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)

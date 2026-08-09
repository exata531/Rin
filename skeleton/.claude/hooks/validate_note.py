#!/usr/bin/env python3
"""validate_note.py, PostToolUse (Write|Edit): keeps the written folder clean.

Two jobs, and the second one is the interesting one.

1. **House rules.** A note gets frontmatter with type, a date, status, and tags, and
   internal references use wikilinks rather than file paths. Notes that fail these are
   findable-once notes: they work today and vanish into the folder by next month.

2. **The folder stays plain.** The voice lives in chat and nowhere else. A note carrying
   kaomoji, asterisk actions, or in-character interjections reads fine on the day it is
   written and reads like somebody else's diary a year later, when the notes are supposed
   to be the durable half of this whole arrangement. Promising not to do it is weaker
   than checking.

Never blocks. It hands back a note-to-self so the next reply can fix it, because a hook
that stops a stranger's first file from being written is a hook that gets deleted.

Contract: on ANY failure, exit 0 silently.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP_DIRS = {"_meta", "templates", ".claude", "scripts", "40-archive"}
REQUIRED = ("type", "status", "tags")

FACE_RE = re.compile(r"[（(][^\n()（）]*[｡ﾟ°･☆♪♡´｀ᴗωヮ□△ㅠ⌒‿¬′＿•̀•́ﾉづ]+[^\n()（）]*[)）]")
ACTION_RE = re.compile(r"(?m)^\s*\*[a-z][^*\n]{2,40}\*\s*$")
INTERJECTION_RE = re.compile(
    r"(?im)\b(ehehe|mou!|ehh\?!|hmph!|baka|yatta|waa+h?|uu\.\.\.|nya)\b")
MD_LINK_RE = re.compile(r"\[[^\]]+\]\((?!https?://)[^)]*\.md\)")


def frontmatter(text):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    return text[3:end]


def check(path, text):
    problems = []

    fm = frontmatter(text)
    if fm is None:
        problems.append("no frontmatter (needs at least type, date, status, tags)")
    else:
        missing = [k for k in REQUIRED if not re.search(rf"(?m)^{k}\s*:", fm)]
        if not re.search(r"(?m)^(date|last-updated)\s*:", fm):
            missing.append("date")
        if missing:
            problems.append("frontmatter is missing " + ", ".join(sorted(missing)))

    body = text[len(fm) + 7:] if fm else text

    if FACE_RE.search(body) or ACTION_RE.search(body) or INTERJECTION_RE.search(body):
        problems.append("it carries chat voice (a face, an asterisk action, or an "
                        "interjection). Notes stay plain; the voice lives in conversation")

    if MD_LINK_RE.search(body):
        problems.append("an internal link is written as a file path. Use [[wikilinks]] "
                        "so the link survives the file moving")

    if "[[" not in body and len(body.split()) > 60:
        problems.append("no wikilink to anything else. A note with no way in is a note "
                        "nobody finds twice")

    return problems


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_input = data.get("tool_input") or {}
    raw_path = tool_input.get("file_path") or ""
    if not raw_path.endswith(".md"):
        sys.exit(0)

    path = Path(raw_path)
    try:
        rel = path.resolve().relative_to(ROOT)
    except Exception:
        sys.exit(0)
    if not rel.parts or rel.parts[0] in SKIP_DIRS or path.name.lower() == "readme.md":
        sys.exit(0)

    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        sys.exit(0)

    problems = check(path, text)
    if problems:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                f"Note check on {rel}: " + "; ".join(problems) + ". Fix it in this turn "
                "without narrating the fix, then carry on with what was actually asked."
            )}}))
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)

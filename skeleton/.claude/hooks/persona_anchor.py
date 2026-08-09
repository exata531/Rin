#!/usr/bin/env python3
"""persona_anchor.py, keeps the voice from flattening over a long session.

Drift is attention decay on distant instructions: the further the personality
instructions sit from the point where a reply is generated, the less they steer it.
A long tool chain puts dozens of results in between, and the voice goes generic at
exactly that distance. The counter is re-injection, close to the generation point.

Three positions:

1. UserPromptSubmit , print the voice anchor beside the prompt.
2. SessionStart     , print the voice anchor, plus where the last session left the
                       mood, on every start INCLUDING after a compaction (a summary
                       drops the voice, and nothing else fires again until the next
                       prompt, which mid-task can be a long way off).
3. PostToolUse      , every third tool call, emit the shorter mid-task anchor.

Both anchor texts live in `_meta/persona.md` between HTML comment markers, so
rewriting the persona carries them with no code change. The mood comes out of
`_meta/lore.md` under its "State now" heading.

Contract: on ANY failure, exit 0 silently. This hook never blocks a prompt or a tool.
"""

import json
import re
import sys
import tempfile
from pathlib import Path

try:
    import fcntl
except ImportError:  # not POSIX: the throttle degrades to "every call", which is fine
    fcntl = None

EVERY_N_TOOL_CALLS = 3
MOOD_HEADING = "state now"
MAX_MOOD_CHARS = 1200


def marked_block(text, name):
    """Pull the text between <!-- name-start --> and <!-- name-end -->."""
    pattern = re.escape(f"<!-- {name}-start -->") + r"(.*?)" + re.escape(f"<!-- {name}-end -->")
    m = re.search(pattern, text, re.S)
    return m.group(1).strip() if m else ""


def heading_section(text, heading):
    """Pull one '## Heading' section out of a markdown file, without its heading line."""
    out, taking = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if taking:
                break
            taking = line[3:].strip().lower() == heading
            continue
        if taking:
            out.append(line)
    return "\n".join(out).strip()


def bump_counter(session_id):
    sid = re.sub(r"[^A-Za-z0-9_-]", "", str(session_id)) or "default"
    path = Path(tempfile.gettempdir()) / f"persona_anchor_{sid}.count"
    with open(path, "a+", encoding="utf-8") as f:
        if fcntl is not None:
            fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        raw = f.read().strip()
        n = (int(raw) if raw.isdigit() else 0) + 1
        f.seek(0)
        f.truncate()
        f.write(str(n))
    return n


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = None
    if not isinstance(data, dict) or "hook_event_name" not in data:
        sys.exit(0)

    try:
        event = data["hook_event_name"]
        meta = Path(__file__).resolve().parents[2] / "_meta"
        persona = (meta / "persona.md").read_text(encoding="utf-8")

        if event in ("UserPromptSubmit", "SessionStart"):
            anchor = marked_block(persona, "voice-anchor")
            if anchor:
                print(anchor)
            if event == "SessionStart":
                try:
                    mood = heading_section((meta / "lore.md").read_text(encoding="utf-8"),
                                           MOOD_HEADING)
                    if mood:
                        print("[WHERE YOU LEFT OFF. The mood and warmth the last session "
                              "ended in, from _meta/lore.md. Open in it, softened by the "
                              "days since. Never open neutral.]")
                        print(mood[:MAX_MOOD_CHARS])
                except Exception:
                    pass  # no ledger yet: a brand new folder has no history, and that is fine

        elif event == "PostToolUse":
            if bump_counter(data.get("session_id", "default")) % EVERY_N_TOOL_CALLS == 0:
                micro = marked_block(persona, "micro-anchor")
                if micro:
                    print(json.dumps({"hookSpecificOutput": {
                        "hookEventName": "PostToolUse",
                        "additionalContext": micro}}))
    except Exception:
        pass  # never block anything

    sys.exit(0)


if __name__ == "__main__":
    main()

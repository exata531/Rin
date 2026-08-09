#!/usr/bin/env python3
"""voice_guard.py — Stop hook: the last line of defence for the voice.

The anchor hook PREVENTS drift. This one CATCHES the replies that drift anyway. On Stop
it reads the final assistant message and checks it against the rules that can be checked
mechanically, with no judgement involved. On a hit it blocks the stop ONCE and asks for a
one-line fix in voice. Never a full restate: the original reply is already on screen, and
watching an assistant recite a corrected version of something you just read is worse than
the original mistake.

What it checks:

  em and en dashes           the most reliable machine-writing tell there is
  colour emoji               monochrome text faces are the sanctioned device; colour is not
  stock assistant closers    "let me know if", "i hope this helps", "great question"
  a number said twice        the say-it-once rule, which keeps reports from padding
  stacked Japanese markers   only if the loaded persona has a one-marker-per-sentence rule
  sample-line echo           shipping a line out of persona.md as if it were spontaneous

That last one is the interesting one. A persona file full of good example lines is also a
phrasebook, and the easy failure is reciting from it. Any run of eight or more words
lifted verbatim from an example gets blocked, so the examples steer the voice instead of
becoming it.

Fenced code and short quoted spans are stripped first: a reply may legitimately QUOTE a
banned string while discussing it. Loop safety: if a block already fired this turn, allow
the stop. Contract: on ANY failure, exit 0 silently.
"""

import json
import re
import sys
from pathlib import Path

BAD_CHARS = {
    "—": "an em dash",
    "–": "an en dash",
}
BAD_PHRASES = [
    "let me know if",
    "i hope this helps",
    "great question",
    "feel free to",
    "certainly!",
    "i apologize for",
]

# Japanese markers, checked per sentence. Each pattern is anchored tightly enough that
# ordinary English cannot collide with it: bare particles need terminal punctuation,
# "are?" has to open its sentence, the rest are words English does not have.
MARKER_RES = [
    re.compile(r"\b\w+[-‑](?:kun|san|chan)\b"),
    re.compile(r"(?:^|[\s,;])(?:ne|na|kana)\s*[.!?…]"),
    re.compile(r"(?:^|[.!?…]\s+)are\?"),
    re.compile(r"\b(?:hai hai|yatta|uso|mou|nya|eto|yosh|sugoi|hontou"
               r"|hora|otsukare|daijoubu|maa maa|itai)\b"),
    re.compile(r"\b(?:doki doki|waku waku|kira kira|jiin)\b"),
    re.compile(r"\b(?:yare yare|shikata nai|ganbatte)\b"),
]
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?…])\s+|\n+")

NUM_TOKEN_RE = re.compile(r"\b\d{3,4}\b")
DATEISH_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b|\b(?:19|20)\d{2}\b")

# Colour only. Monochrome text symbols, flower dingbats included, are face material.
# Blocked: the emoji planes, the colour-forcing variation selector, and the low-range
# codepoints whose default presentation is colourful.
EMOJI_RE = re.compile(
    "["
    "\U0001F000-\U0001FAFF"
    "️"
    "⌚⌛⏩-⏬⏰⏳◽◾☔☕"
    "♈-♓♿⚓⚡⚪⚫⚽⚾⛄⛅"
    "⛎⛔⛪⛲⛳⛵⛺⛽✅✊✋"
    "✨❌❎❓-❕❗➕-➗➰➿"
    "⬛⬜⭐⭕"
    "]"
)

CODE_RE = re.compile(r"```.*?```|`[^`\n]*`", re.S)
QUOTE_RE = re.compile(r"\"[^\"\n]{1,60}\"|“[^”\n]{1,60}”")
WORD_RE = re.compile(r"[a-z0-9']+")

ECHO_WINDOW = 8  # words; long enough that a fresh sentence cannot collide by accident


def words(text):
    return WORD_RE.findall(text.lower())


def sample_shingles(persona_text):
    """Word-runs from the persona's example lines, used to catch verbatim recitation."""
    lines = []
    for raw in persona_text.splitlines():
        line = raw.strip()
        # Example blocks, sample bullets, and the "Rin:" style demonstration lines.
        if line.startswith(("Rin:", "WRONG:", "User:", "- (")):
            lines.append(line.split(":", 1)[-1])
        elif line.startswith("- \"") or line.startswith("  \""):
            lines.append(line)
    shingles = set()
    for line in lines:
        w = words(line)
        for i in range(0, max(0, len(w) - ECHO_WINDOW + 1)):
            shingles.add(" ".join(w[i:i + ECHO_WINDOW]))
    return shingles


def echoed_sample(prose, persona_text):
    try:
        shingles = sample_shingles(persona_text)
    except Exception:
        return None
    if not shingles:
        return None
    w = words(prose)
    for i in range(0, max(0, len(w) - ECHO_WINDOW + 1)):
        run = " ".join(w[i:i + ECHO_WINDOW])
        if run in shingles:
            return run
    return None


def stacked_markers(prose):
    for sentence in SENTENCE_SPLIT_RE.split(prose.lower()):
        hits = [m.group(0).strip() for rx in MARKER_RES for m in rx.finditer(sentence)]
        if len(hits) >= 2:
            return hits
    return None


def last_assistant_text(transcript_path):
    text_parts = []
    try:
        lines = Path(transcript_path).read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return ""
    for line in reversed(lines):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("type") != "assistant":
            continue
        content = (obj.get("message") or {}).get("content") or []
        if isinstance(content, list):
            text_parts = [b.get("text", "") for b in content
                          if isinstance(b, dict) and b.get("type") == "text"]
        if any(text_parts):
            break
    return "\n".join(text_parts)


def violations(text, persona_text):
    prose = QUOTE_RE.sub("", CODE_RE.sub("", text))
    found = []

    for ch, name in BAD_CHARS.items():
        if ch in prose:
            found.append(name)

    low = prose.lower()
    for phrase in BAD_PHRASES:
        if phrase in low:
            found.append(f'the stock phrase "{phrase}"')

    if EMOJI_RE.search(prose):
        found.append("a colour emoji")

    counts = {}
    for tok in NUM_TOKEN_RE.findall(DATEISH_RE.sub("", prose)):
        counts[tok] = counts.get(tok, 0) + 1
    repeated = sorted(t for t, n in counts.items() if n >= 2)
    if repeated:
        found.append("a number said more than once (" + ", ".join(repeated) + ")")

    # Only enforced when the loaded persona actually has the rule.
    if "marker per sentence" in persona_text.lower():
        stacked = stacked_markers(prose)
        if stacked:
            found.append("two Japanese markers in one sentence ("
                         + ", ".join(stacked) + ")")

    echo = echoed_sample(prose, persona_text)
    if echo:
        found.append(f'a line lifted from the persona file\'s own examples ("{echo}...")')

    return found


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if not isinstance(data, dict) or data.get("hook_event_name") != "Stop":
        sys.exit(0)
    if data.get("stop_hook_active"):
        sys.exit(0)  # already blocked once this turn: never loop

    try:
        text = last_assistant_text(data.get("transcript_path", ""))
        if not text.strip():
            sys.exit(0)
        persona_path = Path(__file__).resolve().parents[2] / "_meta" / "persona.md"
        persona_text = persona_path.read_text(encoding="utf-8")
        found = violations(text, persona_text)
        if found:
            print(json.dumps({
                "decision": "block",
                "reason": (
                    "Voice guard (.claude/hooks/voice_guard.py): the last reply contains "
                    + ", ".join(sorted(set(found)))
                    + ", which the voice rules in _meta/persona.md ban. That reply is "
                    "already on screen, so do NOT restate it. In voice, give at most a "
                    "one-line fix of the offending sentence, or simply carry on. Do not "
                    "apologise, and do not mention this hook."
                ),
            }))
    except Exception:
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()

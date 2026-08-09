#!/usr/bin/env python3
"""Schedule a nudge for Rin.app to deliver after this session is gone.

The queue is the handoff: any session writes an entry here and can die; the
app watches the file and fires what is due the moment it is due. Policy, phrasing,
and whether the nudge was worth the user's attention belong to the session that
writes it, the app is only the clock.

Usage:
  nudge.py add --at "YYYY-MM-DDT22:12" --ladder panel --prompt "..." [--expires 180]
  nudge.py add --at "YYYY-MM-DD 11:52" --ladder tap [--react "(o_o)" "(>_<)"]
  nudge.py add --at "YYYY-MM-DDT15:40" --ladder bubble --text "..." [--prompt "..."]
  nudge.py list
  nudge.py remove <id>
  nudge.py face "(￣ヮ￣)" "(¬‿¬)" ...   # the menu-bar face pool for the CURRENT mood
  nudge.py face "(o^▽^o)" --morning "( ᴗ_ᴗ)" --late "(￣o￣) zzz"   # time bands
  nudge.py face --clear
  nudge.py faces-worn [--days 30]        # what the bench is currently blocking

--react on a nudge: faces the bar flashes for a few seconds the moment that nudge
fires, then the mood pool resumes. The session that queues the nudge decides what the
moment feels like; the app never composes an expression.

Bands, matched to the persona's own clock: --morning 5:00-9:00, the plain list 9:00-18:00,
--evening 18:00-23:00, --night 23:00-1:00, --late 1:00-5:00. An omitted band falls back
(--night to --late, everything else to the day pool), so older pools stay valid. Builds
before 1.5 know only morning/late and ignore the rest harmlessly.

ORDER CARRIES MEANING (wave five). The app WALKS each pool in written order instead of
shuffling it, so write the arc: the day pool loudest first and quietest last, --morning
sleepiest first waking up across the band, the evening bands most awake first and most
drooped last. A mood written at noon cools by dinner on its own.

THE BENCH. Every face written here is recorded with its date, and a pool containing a face
worn in the last 30 days is REJECTED (--allow-repeat overrides, and using it is an
admission). Patterns are the failure mode: compose fresh faces from the parts bin in
_meta/face-wardrobe.md rather than reshuffling a pool that worked.

REACTION POOLS (app 1.5.1+), all optional and all under the bench:
  --working    worn while any tab has claude mid-task; walks its own arc over ~20 minutes,
               so write it freshest first and let the tail get bored
  --attention  worn while a tab is asking for him; calmest first
  --greet      flashed for a few seconds when the panel drops open
  --blink FACE FRAME [FRAME...]   repeatable. Gives one written face its blink frames: the
               bar swaps to a frame for a breath every few minutes, jittered, then swaps
               back. Frames are the SAME expression mid-motion so they are exempt from the
               bench, and Reduce Motion turns blinking off entirely. Keep a frame a
               near-twin of its face (eyes closed, mouth changed) or it reads as a glitch.

Ladder rungs (how loud the delivery is; pick from the mood, not a quota):
  dot    the glyph's attention dot only
  tap    dot + the come-look haptic
  bubble haptic + a small speech bubble under the glyph showing --text (a
         pre-written line, the writer composes it like everything else).
         Tapping it always opens a conversation: on --prompt if one was
         written, otherwise on a tap-prompt this script fills from the
         bubble's own text. The app shows it even over an open panel (the
         post-it lands on top) and falls back to the dot when the screen
         is locked or nobody is at the Mac. Needs app 1.2+ (older builds
         treat it as a dot). Keep --text short (a post-it, not a letter;
         hard cap below) and --expires tight, since a spontaneous line
         goes stale fast.
  panel  dot + haptic + the panel drops with a fresh claude tab that opens on
         --prompt. Reserve it for nudges that genuinely open a conversation;
         a one-liner belongs on the bubble rung. Write the prompt as the
         full instruction to that session (say ONE line in voice, then
         stop). There is no phone path: away or locked means the attention
         dot waits. Never tell a nudge session to use a push-notification
         tool, those skip themselves while a terminal is active, and a
         nudge tab IS an active terminal.

Times are local; --expires (minutes, default 180) drops a nudge that could
not fire in time, because a bedtime line delivered at breakfast is worse than
none.

The face pool: kaomoji only, matched to the assistant's current mood, several
per write so the app can rotate and never wear one expression out. Refresh it whenever the
mood moves and nightly from the day card; the app drops a pool nothing has refreshed for
about a day and a half. Faces wider than 14 characters are skipped by the app.
"""

import argparse
import json
import os
import sys
import tempfile
import uuid
from datetime import datetime, timedelta
from pathlib import Path

QUEUE = Path.home() / "Library/Application Support/Rin/nudges.json"
WORN = QUEUE.parent / "worn-faces.json"

BENCH_DAYS = 30      # how long a worn face stays blocked
BENCH_KEEP_DAYS = 180  # how long the ledger remembers at all


def write_atomic(path: Path, text: str):
    """The app reads on every directory write, so a partial file must never
    be visible: write beside, then rename into place."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".{}.".format(path.name))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def load():
    if not QUEUE.exists():
        return []
    try:
        return json.loads(QUEUE.read_text())
    except json.JSONDecodeError:
        sys.exit(f"queue is not valid JSON, fix by hand: {QUEUE}")


def save(queue):
    write_atomic(QUEUE, json.dumps(queue, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def load_worn():
    """The bench: every face this script has ever put on screen, dated.

    A remembered face is a pattern waiting to happen, so the ledger is the thing
    that makes the wardrobe's no-repeat law mechanical instead of a promise a
    writer keeps half of."""
    if not WORN.exists():
        return []
    try:
        entries = json.loads(WORN.read_text())
    except json.JSONDecodeError:
        return []
    return entries if isinstance(entries, list) else []


def worn_since(days):
    cutoff = datetime.now().astimezone() - timedelta(days=days)
    recent = {}
    for e in load_worn():
        try:
            when = datetime.fromisoformat(e["at"])
        except (KeyError, ValueError):
            continue
        if when >= cutoff:
            # Keep the most recent sighting of each face.
            if e["face"] not in recent or when > recent[e["face"]]:
                recent[e["face"]] = when
    return recent


def record_worn(faces):
    now = datetime.now().astimezone()
    keep = []
    for e in load_worn():
        try:
            if datetime.fromisoformat(e["at"]) >= now - timedelta(days=BENCH_KEEP_DAYS):
                keep.append(e)
        except (KeyError, ValueError):
            continue
    stamp = now.isoformat(timespec="seconds")
    keep.extend({"face": f, "at": stamp} for f in faces)
    write_atomic(WORN, json.dumps(keep, ensure_ascii=False, indent=2) + "\n")


def reject_repeats(faces, allow):
    """Refuse a pool that recycles. Naming the offenders is the whole point:
    the writer has to go back to the parts bin, which is where new faces come
    from."""
    if allow:
        return
    recent = worn_since(BENCH_DAYS)
    hits = [(f, recent[f]) for f in faces if f in recent]
    if not hits:
        return
    lines = [f"  {f}   last worn {when.date()}" for f, when in hits]
    sys.exit(
        "these faces are benched (worn in the last {} days):\n{}\n"
        "compose fresh ones from the parts bin in _meta/face-wardrobe.md, or "
        "--allow-repeat if you really mean it.".format(BENCH_DAYS, "\n".join(lines))
    )


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        epilog="a nudge that fires at the same time every day is an alarm clock, "
               "and they already own one of those.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    add = sub.add_parser("add")
    add.add_argument("--at", required=True, help="local time, ISO-ish: YYYY-MM-DDTHH:MM")
    add.add_argument("--ladder", required=True, choices=["dot", "tap", "bubble", "panel"])
    add.add_argument("--prompt", help="claude prompt for a panel nudge, or a bubble's tap-to-talk opener")
    add.add_argument("--text", help="the line a bubble shows, pre-written")
    add.add_argument("--expires", type=int, default=180, help="minutes past --at before it dies unfired")
    add.add_argument("--react", nargs="*", help="kaomoji the bar flashes when this nudge fires")

    sub.add_parser("list")

    rm = sub.add_parser("remove")
    rm.add_argument("id")

    face = sub.add_parser("face")
    face.add_argument("faces", nargs="*", help="the day pool, loudest first, quietest last")
    face.add_argument("--morning", nargs="*", help="5:00-9:00, sleepiest first")
    face.add_argument("--evening", nargs="*", help="18:00-23:00, most awake first")
    face.add_argument("--night", nargs="*", help="23:00-1:00, most awake first")
    face.add_argument("--late", nargs="*", help="1:00-5:00, most awake first")
    face.add_argument("--working", nargs="*", help="worn while a session is mid-task, freshest first")
    face.add_argument("--attention", nargs="*", help="worn while a tab wants him, calmest first")
    face.add_argument("--greet", nargs="*", help="flashed when the panel drops open")
    face.add_argument(
        "--blink", nargs="+", action="append", metavar="FACE FRAME",
        help="a worn face followed by its blink frames; repeatable",
    )
    face.add_argument("--clear", action="store_true")
    face.add_argument("--allow-repeat", action="store_true", help="write a benched face anyway")

    worn = sub.add_parser("faces-worn")
    worn.add_argument("--days", type=int, default=BENCH_DAYS)

    args = ap.parse_args()

    if args.cmd == "faces-worn":
        recent = worn_since(args.days)
        if not recent:
            print(f"nothing worn in the last {args.days} days")
            return
        for f, when in sorted(recent.items(), key=lambda kv: kv[1], reverse=True):
            print(f"{when.date()}  {f}")
        return

    if args.cmd == "face":
        path = QUEUE.parent / "face.json"
        if args.clear:
            path.unlink(missing_ok=True)
            print("face cleared")
            return
        bands = {
            "morning": args.morning,
            "evening": args.evening,
            "night": args.night,
            "late": args.late,
            "working": args.working,
            "attention": args.attention,
            "greet": args.greet,
        }
        # Adding a reaction pool should not force a rewrite of a day pool that
        # is still true, and rewriting it would restart the drift on a mood
        # nothing moved. No positional faces plus at least one pool flag means
        # MERGE into what is already written, updatedAt and all.
        existing = {}
        if not args.faces:
            if not any(bands.values()):
                sys.exit("give at least one kaomoji, or --clear")
            try:
                existing = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                sys.exit("nothing to merge into: write a day pool first")
        every = list(args.faces) + [f for pool in bands.values() if pool for f in pool]
        dupes = {f for f in every if every.count(f) > 1}
        if dupes:
            sys.exit("the same face twice in one write: " + " ".join(sorted(dupes)))
        reject_repeats(every, args.allow_repeat)
        # Blink frames are the SAME expression mid-motion, not another face,
        # so they are exempt from the bench: a blink only reads as a blink
        # when the frame is a near-twin of the face it belongs to.
        frames = {}
        for group in args.blink or []:
            if len(group) < 2:
                sys.exit("--blink needs a face and at least one frame")
            face_key, alts = group[0], group[1:]
            written = set(every)
            for pool in existing.values():
                if isinstance(pool, list):
                    written.update(pool)
            if face_key not in written:
                sys.exit(f"--blink face is not in any pool: {face_key}")
            frames[face_key] = alts
        if existing:
            payload = dict(existing)
        else:
            payload = {
                "faces": args.faces,
                "updatedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
            }
        for name, pool in bands.items():
            if pool:
                payload[name] = pool
        if frames:
            payload["frames"] = {**payload.get("frames", {}), **frames}
        write_atomic(path, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
        record_worn(every)
        print("face pool set: " + " ".join(args.faces or ["(merged, day pool kept)"]))
        return

    queue = load()

    if args.cmd == "add":
        when = datetime.fromisoformat(args.at.replace(" ", "T"))
        if when.tzinfo is None:
            when = when.astimezone()  # attach local offset; the app decodes ISO8601
        if args.ladder == "panel" and not args.prompt:
            sys.exit("a panel nudge needs --prompt (the app never composes a word)")
        if args.ladder == "bubble" and not args.text:
            sys.exit("a bubble needs --text (the app never composes a word)")
        if args.ladder == "bubble" and not args.prompt:
            # Every bubble must be tappable into a conversation: a tap that
            # only opens the panel reads as broken. The prompt renders ON
            # SCREEN as the tab's opening message, so it carries a bare cue
            # and nothing else: stage directions in view wreck the moment.
            # How to answer a "(nudge)" cue lives in the persona, where the
            # audience cannot see it.
            args.prompt = '(nudge) he tapped the bubble: "' + args.text + '"'
        if args.text and len(args.text) > 200:
            sys.exit("bubble text over 200 characters, it is a post-it, not a letter")
        entry = {
            "id": uuid.uuid4().hex[:12],
            "fireAt": when.isoformat(timespec="seconds"),
            "ladder": args.ladder,
            "prompt": args.prompt,
            "expiresMinutes": args.expires,
        }
        if args.text:
            entry["text"] = args.text
        if args.react:
            # A flash face is a face he sees, so it lives under the same law.
            reject_repeats(args.react, False)
            entry["react"] = args.react
        queue.append(entry)
        save(queue)
        if args.react:
            record_worn(args.react)
        print(f"queued {entry['id']} at {entry['fireAt']} ({entry['ladder']})")
    elif args.cmd == "list":
        if not queue:
            print("queue empty")
        for n in queue:
            print(f"{n['id']}  {n['fireAt']}  {n['ladder']}  {(n.get('prompt') or '')[:60]}")
    elif args.cmd == "remove":
        before = len(queue)
        queue = [n for n in queue if n["id"] != args.id]
        if len(queue) == before:
            sys.exit(f"no nudge {args.id}")
        save(queue)
        print(f"removed {args.id}")


if __name__ == "__main__":
    main()

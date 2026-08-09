#!/usr/bin/env python3
"""The line along the bottom of the terminal: which model is answering, how
hard it is thinking, how full the context is, how much of the five-hour
window is left and when it comes back, then the clock.

The clock is the point of the clock. Repaints stop when the turn stops, so
the time frozen there is the moment the reply finished, which is the one
number a terminal never tells you otherwise.

Some repaints arrive without the usage numbers (a fresh tab, an idle
session), and a bar that blanks every few seconds reads as broken. The last
real values are cached and reused so it stays still. Context is cached per
session id, never shared between tabs: one tab showing another tab's fill
would be worse than showing nothing.
"""
import datetime
import json
import sys

CACHE = "/tmp/rin-statusline-cache.json"

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

cached = {}
try:
    with open(CACHE) as f:
        cached = json.load(f)
except Exception:
    pass

effort = (data.get("effort") or {}).get("level") or cached.get("effort")
rate_limits = data.get("rate_limits") or cached.get("rate_limits") or {}
# Context is per session and every tab shares this one cache file, so it is
# kept as a map rather than a single slot. A single slot meant the last tab
# to repaint owned it, and every other tab either borrowed a fill that was
# not its own or lost its own: the exact flicker the cache exists to stop.
# A repaint that does not name its session gets no context at all: there is
# no way to know whose it is, and briefly absent beats confidently wrong.
by_session = cached.get("ctx_by_session")
if not isinstance(by_session, dict):
    by_session = {}
sid = data.get("session_id")
ctx = (data.get("context_window") or {}).get("used_percentage")
if ctx is None and sid is not None:
    ctx = by_session.get(sid)
if sid is not None and ctx is not None:
    by_session[sid] = ctx
    # Tabs come and go; the map must not grow for the life of the machine.
    if len(by_session) > 32:
        by_session = dict(list(by_session.items())[-32:])

try:
    with open(CACHE, "w") as f:
        json.dump(
            {"effort": effort, "rate_limits": rate_limits, "ctx_by_session": by_session}, f
        )
except Exception:
    pass

parts = []

model = (data.get("model") or {}).get("display_name")
if model:
    parts.append(model)

if effort:
    parts.append(effort)

if ctx is not None:
    parts.append(f"ctx {int(ctx)}%")

five_hour = rate_limits.get("five_hour") or {}
resets_at = five_hour.get("resets_at")
if resets_at and int(resets_at) < datetime.datetime.now().timestamp():
    # The window already rolled over, so the cached numbers from before the
    # roll would be confidently wrong. Briefly absent beats quietly false.
    five_hour = {}
used = five_hour.get("used_percentage")
if used is not None:
    parts.append(f"{100 - int(used)}% left")
resets = five_hour.get("resets_at")
if resets:
    when = datetime.datetime.fromtimestamp(int(resets))
    parts.append("reset " + when.strftime("%H:%M"))

parts.append(datetime.datetime.now().strftime("凛 %H:%M:%S"))
print(" · ".join(parts))

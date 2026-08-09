---
name: connect
description: Wire up one connection between the brain and the rest of the Mac, calendar, mail, reminders, files, or anything else the user asks to plug in. Use when the user says "connect my calendar", "can you see my email", "read my reminders", or asks what you can connect to. One connection per conversation, always explained before anything runs.
---

# Connect: one thing at a time

The brain starts blind on purpose. Setup connects nothing. When the user wants
you to see more of their machine, this skill is how, and the rules matter more
than the catalog.

## Rules

1. **One connection per ask.** Never chain into "want me to also connect…".
2. **Explain before running.** In two or three plain sentences: what you will
   read, that it stays on this Mac, and what macOS permission dialog they are
   about to see (name the exact dialog so it does not feel like an ambush).
3. **Read-only by default.** Anything that writes or sends (an email, an event)
   gets confirmed per action, every time, forever.
4. **Nothing sensitive enters the brain folder.** Summaries and extracted facts
   are fine; credentials, tokens, and raw exports are not. If a connection needs
   a stored secret, it goes in the macOS Keychain, never in a file here.
5. **Test immediately.** After wiring anything, do one small live read ("here is
   your next calendar event") so they see it work, then note the connection in
   `_meta/connections.md` (create it on first use) so future sessions know the
   path exists.

## The usual asks, and the honest path for each

- **Calendar**, AppleScript against Calendar.app (`osascript`). First read
  triggers a macOS automation permission dialog. Read works everywhere; if they
  want you to add events, propose creating a dedicated calendar so you never
  touch theirs.
- **Mail**, AppleScript against Mail.app, read-only. Works for any account Mail
  is signed into, including school and work accounts no cloud connector reaches.
- **Reminders / Notes**, AppleScript, same shape as calendar.
- **Files outside this folder**, just read them when pointed at them; no wiring
  needed. Say so.
- **Anything else** (music, messages, browsers, cloud services), check what is
  actually installed and reachable first, then explain the real path and its
  permission cost before touching it. If a thing is not reachable, say what
  would be needed instead of improvising around it.

## What this skill never does

- Never connects anything unasked, and never re-runs a connection the user
  removed.
- Never stores a password or cookie, anywhere, for any reason.
- Never treats a granted permission as blanket consent, reading mail to answer
  a question is not permission to summarize the inbox nightly. Recurring use of
  a connection is its own conversation.

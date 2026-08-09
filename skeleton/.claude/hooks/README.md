# The hooks

Four small scripts that run around the conversation. They are the difference between an
assistant that has a personality written down and one that keeps it on hour three of a
working session.

None of them can see the internet, none of them store anything, and every one of them is
written to fail silently: if a hook breaks, the conversation carries on as if it were not
there.

| File | Runs on | Does |
|---|---|---|
| `persona_anchor.py` | every prompt, every session start, every third tool call | re-reads the voice out of `_meta/persona.md` and puts it back in front of the model, because instructions lose their grip the further they sit from the reply. Also carries in the mood the last session ended on. |
| `voice_guard.py` | when a reply finishes | catches the mechanical tells on the way out (em dashes, colour emoji, stock closers, a number said twice, a line recited from the persona's own examples) and asks for a one-line fix |
| `session_status.py` | session start | reads the folder and hands over the few facts a session should not have to ask for |
| `validate_note.py` | after a file is written | checks frontmatter and links, and catches chat voice leaking into a note |

## Turning one off

Open `.claude/settings.json` and delete its entry. Nothing else references them, and the
brain works without any of them: it just drifts. `voice_guard.py` is the one people
usually want to keep even when they replace the persona entirely, since most of what it
blocks is machine-writing tells rather than anything character specific.

## Adding your own

A hook reads a JSON object on stdin and can print context back. Keep the contract the
four of these keep: catch every exception, exit 0, and never be the reason a message did
not send. The person on the other end did not sign up to debug your automation.

---

*The anchor script has been rewritten more times than anything else in here. Turns out
the hard part of having a personality is having it on tuesday afternoon too.*

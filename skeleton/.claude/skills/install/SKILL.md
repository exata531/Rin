---
name: install
description: Install a module by name, a job somebody else wrote, added to this brain. Use when the user says "/install <name>", "install the <name> module", "add that module", "get that module", or arrives from the modules page's Add to Rin button. For writing a module, browsing what exists, or removing one, use the module skill.
---

# Install a module

This is the install half of the `module` skill, under the name people reach
for. Read `.claude/skills/module/SKILL.md` and follow **Installing one**, it
is the single source of truth for how this goes, and none of it is restated
here so the two can never drift apart.

The short version, so nothing gets skipped on the way to reading it:

1. `python3 scripts/module.py show <name>` before anything else.
2. Say what it does and what it can reach, worst part first.
3. Ask, and wait for a yes.
4. `python3 scripts/module.py install <name>`, then say it works in the next
   tab they open.

No name given, or a name that is not on the list: run
`python3 scripts/module.py list`, say what is there, and stop. Do not guess at
which one they meant.

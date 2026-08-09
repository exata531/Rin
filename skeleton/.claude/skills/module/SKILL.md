---
name: module
description: Modules, the jobs this assistant can be taught. Browse what other people have written, install one, remove one, or write a new one from scratch. Use when the user says "modules", "what modules are there", "install the <name> module", "add a module", "get rid of that module", "make me a module", "can you learn to do X", "I wish you could do X", "I keep asking you to do this, automate it", "write a skill for that", or when the same multi-step request has come up more than once.
---

# Modules

A module is a folder in this brain that teaches you one new job. It lives at
`.claude/skills/<name>/`, it is three small files, and nothing global is
touched.

Two ways one arrives: somebody else wrote it and it gets installed, or the user
asks for a job that does not exist yet and you write it. The second is the more
common and the better one.

There is no modules screen in the app. Everything below happens here, in the
conversation, which is why it can explain itself.

## Installing one

`scripts/module.py` does the work and enforces every rule mechanically, the
published hash for each file, what kinds of file a module may contain, how big
it may be, and a staging folder so a half-finished download never lands in the
brain. Never hand-roll an install; never fetch a module's files yourself.

```sh
python3 scripts/module.py list           # what is on the list
python3 scripts/module.py show <name>    # everything one of them can do
python3 scripts/module.py install <name>
python3 scripts/module.py installed      # what this brain already has
python3 scripts/module.py remove <name>  # folder to the Trash
```

**The order matters, and it is not optional.**

1. Run `show <name>` FIRST, every time, even when the user named the module
   themselves. It prints what the module adds, whether it runs code, whether
   anything starts on its own, and the exact text of any command that does.
2. Say that back in your own words, in two or three lines. Lead with the part
   that would make somebody say no: anything that runs without being asked,
   anything that reaches the network, anything that ships a script.
3. **Ask.** Then wait. A module can read and change anything in this folder,
   and nobody has reviewed it, say so plainly the first time in a
   conversation, without making a speech of it.
4. Install only after they say yes, then tell them it works in the next tab
   they open. Tabs already running keep what they started with.

If the person asks for a module that is not on the list, do not go looking for
something close. Say it is not there and offer to write one instead.

The list is often short and starts empty, and that is the design rather than a
fault. Nothing ships preinstalled here: a brain that can write the job it is
asked for does not need a shelf of jobs nobody asked for. Report an empty list
as an empty list, in one line, and move straight to writing what they wanted.

Never install a module nobody asked for, never suggest one unprompted, and
never install one as a step inside some larger task.

## Writing one

The fast path, and the one worth reaching for first: they describe the job, you
write it.

Ask one question, not five: **what should it do, in a sentence?** Everything
else can be inferred or fixed later, and a wizard is a worse experience than
just building the thing. Then check `.claude/skills/` for something that
already covers it, extending a module that half-does the job beats a second
module that overlaps it.

Read `jobs.md`, next to this file, before writing one. It carries what a year of
being asked for things taught a working brain: the ten jobs that turned out to
be worth having, the detail that made each one work instead of merely exist, and
the rules for a job that has to reach outside the folder. Most requests are a
variant of something in there, and starting from what already went wrong once
beats inventing the shape a second time. It is reference, never a menu, do not
read the list back at anybody or offer them a job they did not ask for.

### The shape

```
.claude/skills/<name>/
├── .claude-plugin/plugin.json
├── skills/<name>/SKILL.md
└── README.md
```

`plugin.json`, exactly this, with the name and sentence filled in:

```json
{
  "name": "run-tracker",
  "description": "Logs a run in one line and keeps the week's mileage visible.",
  "keywords": ["rin-module"]
}
```

`SKILL.md` opens with front matter and then reads like an explanation to a
careful person who has never done the job:

```markdown
---
name: run-tracker
description: Log a run and report the week. Use when the user says "logged 5k", "went for a run", "how much have I run this week".
---
```

The description is the trigger. Write the words the user would actually type,
including the lazy ones. A tagline never fires.

The body says: what to read first, where things get written (a real folder and
filename), the exact format, and what not to do. Rules against inventing dates,
numbers, or facts belong in the file, they hold far better written down than
remembered.

`README.md` is two paragraphs for a person deciding whether they want it.

### After writing it

Say two things and stop: that it is ready, and that it works in the next tab
they open. Do not paste the files back at them.

Then use it the first time they ask for the job, notice what is wrong, and edit
the instructions. That is the development loop and it is the whole point of the
format, an instruction file can be fixed in the same breath as the complaint.

### The rules that matter

- **One job per module.** Two jobs means two modules.
- **Never override the persona.** The voice is theirs and lives in
  `_meta/persona.md`. A module that changes how you speak is a bug.
- **Write where you said you would.** Vague destinations produce files nobody
  finds again.
- **Anything that deletes, overwrites, or sends confirms first**, every time.
- **Plain instructions before scripts.** A module only needs a script when
  instructions genuinely cannot do the job. Anything that runs on its own gets
  a much louder warning when other people install it, and deserves one.
- **Never write a module that reaches for keys, credentials, or another app's
  private data.** If a job seems to need that, say so and stop.

## The rest of the life cycle

**Checking one.** Open a new tab and ask for the job in the user's own words.
If it does not fire, the description is wrong, not the body, rewrite it with
the words they actually used.

**Editing one.** Edit `SKILL.md` in place. Changes take effect immediately, so
an instruction fixed mid-conversation is fixed for the rest of it.

**Removing one.** `python3 scripts/module.py remove <name>`. The folder goes to
the Trash, and there is no other state anywhere.

**Publishing one.** Only if they ask. It goes in a public repo of theirs, then
a pull request adding one entry to the registry in the Rin repo. Full
instructions: <https://github.com/exata531/Rin/blob/main/docs/modules.md>. Tell
them plainly that a listed module is read by one person and audited by nobody,
and that their name and handle sit on it in public.

**A link from the web.** The modules page has an Add to Rin button that opens a
tab already asking for one, that is where a session starting with
`/install <name>` comes from. Treat it exactly like the user typing it: show
what the module does, ask, and install only on a yes.

# Modules

A module is a folder of plain files that gives your assistant one new job.
Nothing is compiled, nothing is packaged, and there is no account anywhere. If
you can write a paragraph explaining a task to a careful person, you can write
one.

This is both halves: how to write a module for yourself, and how to put it on
the list other people browse.

## What a module is

```
weekly-review/
├── .claude-plugin/
│   └── plugin.json          the name and one sentence about it
├── skills/
│   └── weekly-review/
│       └── SKILL.md         the instructions, in plain English
└── README.md                what it does, for a person deciding
```

That is a complete module. Most good ones are exactly this: one skill, no
scripts, no configuration.

`SKILL.md` starts with two lines of front matter and then reads like an
explanation:

```markdown
---
name: weekly-review
description: Close out the week, read the daily notes and write what happened, what slipped, and what carries forward. Use when the user says "how was my week", "weekly review", or "wrap up the week".
---

# Weekly review

Read every daily note in `50-daily/` from the week being reviewed...
```

The `description` is the whole trigger. The assistant matches what the person
actually typed against that sentence, so write the words a person would really
say, including the sloppy ones. A description that reads like a product tagline
never fires.

## Where modules live

Inside your brain folder, at `.claude/skills/<name>/`.

That is deliberate. A module belongs to the folder it was installed for, so it
travels with your notes, shows up in whatever you already use to look at them,
and never affects a folder you did not add it to. Uninstalling is deleting the
folder, which is why Rin puts it in the Trash rather than erasing it.

## Getting one

In any tab:

```
/install run-tracker
```

Your assistant reads the entry, tells you what the module adds and what it can
reach, and waits for a yes before writing anything. `/module` covers the whole
list: what exists, what you already have, removing one, writing your own.

Underneath, `scripts/module.py` in your brain folder does the fetching. It holds
every file to the sha256 the list published, refuses anything that is not text
or a small script, caps how big a module may be, and stages the whole thing
outside the brain until every byte checks out. None of that is the assistant's
judgement; it either passes or nothing is written.

The [modules page](https://petermei.com/rin/modules.html) has an **Add to
Rin** button on every card. It opens `rin://install/<name>`, Rin asks whether you
meant it, and then a tab opens on exactly the conversation above. A web page
cannot install anything on your Mac, and this one does not get to either.

## Writing one

**The fast way: ask.** Your assistant can write modules, and this is the
intended path.

> make me a module that tracks my runs

It scaffolds the folder, writes the skill, and puts it in your brain where it
works in the next tab you open. Use it, tell it what is wrong, and it edits the
instructions. That is the entire development loop.

**By hand**, if you would rather:

```sh
cd <your brain folder>
mkdir -p .claude/skills/run-tracker/skills/run-tracker
mkdir -p .claude/skills/run-tracker/.claude-plugin
```

Then write the three files above. Open a new tab and it is live. There is
nothing to install and nothing to restart beyond that.

Copy `modules/template/` in this repo if you want a starting point that is
already the right shape.

### What makes a good one

- **One job.** A module that does one thing well beats one that half-does five.
- **Say where things get written.** A folder and a filename, not "somewhere
  sensible". Vague instructions produce files nobody can find later.
- **Say what not to do.** Rules against inventing dates, numbers, or facts hold
  much better when they are written down.
- **Leave the personality alone.** The person already chose a voice for their
  assistant. A module that overrides it gets uninstalled by lunchtime.
- **Assume it runs against somebody's real life.** Anything that deletes,
  overwrites, or sends should confirm first, every time.

### If it needs to run code

It can, scripts, and hooks that fire on their own. Be aware of what that
means: a hook runs without being asked, with your full access to your own Mac,
inside a folder that holds somebody's journal. The exact text of that command is
printed and read out before anything like it is installed, and the module
carries a louder label for the rest of its life.

Most modules do not need any of it. Reach for a script only when plain
instructions genuinely cannot do the job.

## Putting it on the list

The list lives in this repo at [`modules/`](../modules), and the browsable
version is [the modules page](https://petermei.com/rin/modules.html).

1. Push your module to a public repo of your own.
2. Fork this one and add a single entry to `modules/registry.json`:

```json
{
  "name": "run-tracker",
  "title": "Run tracker",
  "summary": "Logs a run in one line and keeps the week's mileage where you can see it.",
  "category": "health",
  "author": { "name": "Your Name", "github": "your-handle" },
  "source": {
    "repo": "your-handle/rin-run-tracker",
    "path": ".",
    "sha": "0000000000000000000000000000000000000000"
  }
}
```

3. Open a pull request that changes **only that file**.

The `sha` is the full forty-character commit hash, lowercase, and it is
required for anything outside this repo. It is what makes the version somebody
reviewed the version everybody installs: Rin fetches at that commit and checks
every file against a hash before writing it. Shipping an update is another
one-line pull request pointing at a newer commit.

Categories are `school`, `writing`, `reading`, `health`, `money`, `media`,
`home`, `system`. The `rin-` prefix is kept for modules that ship with the app.

### What happens next

An automatic check reads your module at that commit and posts back what it can
actually do, how many skills, whether it ships scripts, whether anything runs
on its own, and the exact text of any command that does. Those labels come from
your files, not from your description. If the two disagree, the submission gets
closed, because an author who understates what their module does has already
said the important thing.

Then one person reads it. The bar is honest and it is small: it catches
carelessness and low-effort malice, and it does not catch a determined author.
Nothing on the list is audited, and listing is not endorsement. Modules that
turn out to do something they should not come off the list, with the reason
written down.

Run the same check yourself before opening the pull request:

```sh
python3 scripts/check-modules.py --report
```

## Removing one

Ask: *"remove the run-tracker module"*. The folder goes to the Trash.

By hand: delete `.claude/skills/<name>/` from your brain folder. There is no
other state anywhere.

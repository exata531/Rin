# First run: spec

The site promises: "You answer three questions and it builds itself." This is how
that actually happens, for a user who has a Claude subscription and has never
opened a terminal.

## Principle

The app only does what must happen **before an AI exists**: get Claude Code
installed, get it logged in, pick a folder. Everything after that, the AI does,
the setup wizard is a Claude conversation driven by `skeleton/.claude/skills/setup`,
not a Swift UI. Setup is the product's first demo of "you talk, it does."

## Stage 0: native (Swift), in order

1. **Detect Claude Code.** Look for the `claude` binary the way a login shell
   would (run `$SHELL -l -c "command -v claude"`, since the app's own PATH is
   bare). Found → skip to step 3.
2. **Install it, visibly.** One line of copy in the panel ("Rin is the window
   Claude Code runs in. Install it?") and on yes, run Anthropic's official
   installer **in the terminal pane itself** so the user watches every line. No
   hidden shells. On failure, show the output and stop; never retry silently.
3. **Log in.** Run `claude` in the pane. The user picks "log in with Claude
   account", the browser opens, they sign into the subscription they already
   have. The app just waits; login is Anthropic's flow, not ours.
4. **Pick the folder.** Standard open panel, default suggestion
   `~/Documents/Brain`. Refuse nothing, but warn on obviously bad homes
   (Downloads, a Desktop root, inside another app's container).
5. **Seed and launch.** Copy the bundled `skeleton/` into the chosen folder
   (fail if the folder is non-empty, never merge into existing files), set it
   as the app's working directory, open the first tab running `claude` with an
   initial prompt of: `Run the setup skill.`

## Stage 1: the conversation

Owned entirely by `skeleton/.claude/skills/setup/SKILL.md`. Three questions
(where confirmed, who you are, who it should be), each file shown before it is
written, ends by capturing one real item from the user's life. Resumable via
`_meta/setup-state.md` if the window closes mid-way.

## Stage 2: connections, later, never during setup

No integration, account, or macOS permission dialog appears during first run.
The `connect` skill (in the skeleton) adds them one at a time, on ask, with the
permission dialog explained before it fires.

## Packaging notes

- The skeleton ships **inside the app bundle** (add `skeleton/` as a folder
  reference in project.yml resources) so first run works offline and never
  depends on a network fetch.
- The skeleton is the only thing the app ever writes into the user's folder,
  and only once, into an empty target.
- Re-running setup later ("start over") is the skill's job, not the app's; the
  app's only reset is choosing a different folder.

## The demo script (what "show someone" looks like)

1. Download, double click, then System Settings, Privacy & Security, Open
   Anyway (the site documents the unsigned warning; right-click-Open only works
   on macOS 14 and earlier).
2. Control + backtick. The panel notices Claude Code is missing and installs it
   in front of them.
3. Browser opens; they log in with the claude.ai account they already pay for.
4. "no brain found in this folder yet. want me to build one?" Three questions.
5. They say "I have an essay due friday" and watch it get filed. That sentence
   is the product; the demo is not over until it lands.

# Security

Rin is a terminal in the menu bar that writes into a folder holding somebody's
notes, plans, and journal. Reports about either half are taken seriously.

## Reporting

**A vulnerability in the app itself:** use GitHub's private reporting (the
Security tab of this repo, then **Report a vulnerability**) rather than a
public issue, so a fix can ship before the details do.

**A module on the list doing something it should not:** the opposite. Report it
in the open with the
[Report a module](https://github.com/exata531/Rin/issues/new?template=report-a-module.yml)
template, because there speed beats discretion: a credible report gets the
module taken off the list first and discussed after. If you think it is being
actively used to harm people, say so in the first line and do not wait to fill
in the rest.

## What counts

The app makes no network requests of its own; everything on the wire belongs
to Claude Code, plus the module list and a module's files when one is asked
for by name. So any of these is a report worth making:

- Network traffic from Rin itself that is not Claude Code's or a module fetch.
- A module install writing anywhere outside its staging area and
  `.claude/skills/<name>/` in the chosen brain folder.
- The checker labelling a module as less than its files actually do.
- The app reading anything beyond `~/.claude` and the brain folder it was
  pointed at.
- Any way a web page can make `rin://install/<name>` do more than open a
  confirmation.

## Scope

The latest release is the supported one. Rin is unsigned by choice and the
install steps route through Gatekeeper's Open Anyway; that is documented
behaviour, not a finding.

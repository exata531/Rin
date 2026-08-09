# The module registry

`registry.json` is the list. `index.json` is generated from it and is what the
app and the website read, do not edit that one by hand.

Writing a module, and submitting one, are both covered in
[docs/modules.md](../docs/modules.md). This file is the part that matters after
a submission arrives.

## What gets merged

Automatic, before anybody reads anything:

- the pull request touches `modules/` and nothing else
- `registry.json` parses, every field is present, the name is lowercase and
  unique, the category is one of the eight
- entries outside this repo carry a full forty-character lowercase `sha`, and
  that commit is readable
- every file is text of a kind a module may ship, under the size limits, with
  no encoded blobs, no minified lines, and nothing reaching for keys,
  credentials, message stores, or other people's databases
- the module has a skill and a README

Then one person reads it, and the reading is bounded on purpose:

1. Look at the diff. One file, one added entry, and the repo belongs to the
   person submitting it. Anything else is closed rather than negotiated.
2. Read what the check posted. A text-only module with a clean report can be
   merged there.
3. Anything that runs code or reaches the network: open the source at that
   exact commit and read every command and every script, end to end. **If it
   cannot be read in three minutes it is too big to merge**, ask for it to be
   split.
4. Skim each skill for instructions aimed at the assistant rather than at the
   job: send, upload, post, push, delete, token, key.
5. Compare the README against the computed labels. A mismatch is a close, with
   no discussion.

## Removing one

Delisting is reversible and a compromised folder is not, so a credible report
gets the entry removed first and discussed after.

1. Delete the entry from `registry.json`.
2. Add a line to `removed.json` saying what came off, when, and why, in plain
   language.
3. Regenerate and commit:
   `python3 scripts/check-modules.py && python3 scripts/build-modules.py`

Removal takes it off the list and out of the app. It does not reach into
folders where somebody already installed it, which is worth saying out loud in
the issue.

## Running the check locally

```sh
python3 scripts/check-modules.py --report   # what a submission would post
python3 scripts/check-modules.py            # rewrite index.json
python3 scripts/build-modules.py            # rewrite site/modules.html
```

`--offline` skips modules hosted elsewhere, for when there is no network.

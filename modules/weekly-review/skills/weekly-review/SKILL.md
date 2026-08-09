---
name: weekly-review
description: Close out the week, read the week's daily notes and write a review of what happened, what slipped, and what carries into next week. Use when the user says "how was my week", "weekly review", "wrap up the week", "plan next week", or when a week ends and nothing has been written down.
---

# Weekly review

A week only teaches you something if somebody reads it back. This writes that
read-back from the notes that already exist, so the user does not have to
remember Monday on a Sunday evening.

## Before writing anything

1. Run `date "+%A %Y-%m-%d"` and work out which week is being reviewed. The
   current week unless the user names another one.
2. Read every daily note in `50-daily/` that falls inside it. Missing days are
   part of the story; note them, do not invent them.
3. Read `_meta/orient.md` for what the user said mattered this week, so the
   review can say whether the week went where it was pointed.

Never write a review from memory of the conversation. The notes are the record.

## The review

Write to `50-daily/reviews/YYYY-Www.md`, creating the folder if it is not
there. If a review for that week already exists, open it and extend it rather
than overwriting what is already written.

Frontmatter first: `type: weekly-review`, `date`, `week`, `status: complete`,
`tags: [review]`.

Then five short sections, in this order, in the user's own register:

- **What happened.** Six lines at most, drawn from the dailies. Concrete
  things, not adjectives.
- **What moved.** The work that actually advanced, named by project.
- **What slipped.** What was planned and did not happen. No softening, no
  scolding. A pattern across weeks gets named as a pattern.
- **Worth keeping.** One thing that went well enough to repeat on purpose.
- **Next week.** Two or three things, no more. A list of ten is a wish, not a
  plan.

## Then, out loud

Give the user the short version in conversation: the one thing that moved, the
one thing that slipped, and the top item for next week. Three sentences. The
file holds the detail; the reply does not need to repeat it.

If the week has an obvious open question the notes cannot answer, ask it, one
question, at most.

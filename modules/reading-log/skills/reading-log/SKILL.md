---
name: reading-log
description: Track books, articles, and papers, start one, finish one, or record what you thought. Use when the user says "I started reading X", "I finished X", "add this to my reading list", "what am I reading", "what did I read this year", or hands over a link they want to read later.
---

# Reading log

One file, one row per thing read. The point is not the list; the point is that
a book someone liked in March is still findable in November, in their own
words.

## Where it lives

`30-resources/reading-log.md`. Create it on first use with this frontmatter and
a table:

```
---
type: log
last-updated: YYYY-MM-DD
status: living-document
tags: [reading]
---
```

Columns: Title, Author, Kind, Started, Finished, Rating, Note. Kind is book,
article, paper, or long-form. Rating is one to five, and it stays empty until
the user gives one. Never rate anything for them.

## The four things people ask for

**Starting something.** Add a row with today's date in Started and nothing in
Finished. Ask for the author only if the title alone would be ambiguous later.

**Finishing something.** Fill Finished with today's date, then ask what they
thought, one open question, not a form. Their answer goes in Note in their own
words, trimmed but not rewritten. If the thought runs past a sentence or two,
give it a note of its own in `30-resources/reading/` and link it from the row.

**Adding something for later.** A link or a title with no dates. It sits at the
bottom under a "Not started" heading, and it is the first place to look when
they ask what to read next.

**Asking about the log.** Answer from the file, never from memory. Counts,
patterns, what has been sitting unstarted the longest, say the number once and
make sure it matches the table.

## Rules

- Run `date "+%Y-%m-%d"` before writing any date. Never infer today.
- One row per thing, extended over duplicated. A book started twice keeps its
  original Started date and gains a note.
- If the user is clearly mid-thought about a book, let them talk before writing
  anything down. The log can wait; the thought cannot.

---
name: flashcards
description: Make recall questions from a note and quiz the user on them. Use when the user says "quiz me", "test me on this", "make flashcards", "help me review X", or has a test coming and wants to practise rather than reread.
---

# Flashcards

Rereading a note feels like studying and mostly is not. This turns a note the
user already wrote into questions they have to answer from memory, then keeps
score of the ones that keep going wrong.

## Making the cards

Ask which note, unless they just pointed at one. Read it, then write questions
that force recall rather than recognition: "why does X happen" beats "what is
X", and anything answerable with yes or no is a bad card.

Cards live beside the note they came from, in `<note-folder>/<note>-cards.md`:

```
## Question
Answer, one or two lines.
Missed: 0
```

Between eight and fifteen cards from an ordinary note. More than that and the
user will never finish a round; fewer and it is not worth the file.

## Running a round

One question at a time, in conversation. Wait for an answer. Never show the
answer in the same message as the question, and never ask two at once.

When they answer:

- **Right**, say so in a word, then the next question. No praise paragraphs.
- **Close**, name the exact part that was missing, then move on.
- **Wrong or blank**, give the answer plainly, add one to that card's Missed
  count, and put the card back into the round two questions later.

Cards missed twice in a round come back at the end. Cards missed three times
across rounds get a line in the file saying so, because a card that keeps
failing usually means the note behind it is unclear, and that is worth fixing
rather than drilling.

## Ending a round

Say how many were answered without help, out of how many. One number, once,
and it has to match what actually happened. Then name the one topic worth
looking at again before the next round. No score history, no streaks, no
encouragement that was not earned.

## Rules

- Questions come from the note. Never invent material the note does not
  contain, and never quiz on something the user has not studied.
- If the note is too thin to make good questions from, say so and offer to
  study it together first instead of faking a round.

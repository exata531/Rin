---
type: system
status: default
---

# Face wardrobe: how the menu bar wears a feeling

The 凛 in the menu bar can wear a kaomoji beside it, and that face is the assistant's
current mood. It is **built**, not picked from a list. Nothing writes it automatically:
a session writes the pool when the mood is real, with `python3 scripts/nudge.py face …`,
and the app rotates and drifts inside whatever was written. The app SELECTS; only a
session composes.

Delete this file and the face simply never appears. Nothing else breaks.

**Until the first pool is written, the app wears one that shipped with it.** A new install
has no mood to show yet, so instead of a bare glyph the bar wears the default persona's
opening expression, freshly arrived, knows nobody, and it drifts across the clock bands
like any other pool, so the behaviour is visible from the first hour. It is a first
impression, not a feeling. **The first pool written here retires it for good**: from then
on the bar only ever wears what a session composed, including wearing nothing at all once
a pool goes stale. So there is no rush to write one, and no reason to keep any of the
shipped faces. Build from the parts bin below the moment there is a real mood to show.

## The law

- **The feeling comes first, exactly as it is.** Not the nearest named emotion, the
  day's own mixture at its own loudness. "Smug with a tired edge" is a mood, and it
  composes its own pool.
- **Loudness sets everything**: how loud each face runs and how many ride the pool. A
  quiet day is a couple of soft faces; a loud day is a bigger pool wearing its loud end.
  No count is fixed anywhere.
- **Build from parts, do not shop from a list.** Any face easy to recall is a face the
  bar has probably already worn.
- **Never repeat a face, and this is enforced.** The script keeps a worn ledger and
  rejects a pool holding anything worn in the last 30 days. `--allow-repeat` exists and
  using it is an admission.
- **Never a cheerful pool on a day that was not.**
- **Compact and monochrome only.** Anything wider than 14 characters is skipped; color
  emoji and color-forcing symbols never go in. Monochrome text symbols are fine
  (♡ ☆ ♪ ✧ ✿ pass; the ⭐ ✨ family does not).

## The parts bin

Kaomoji put the feeling in the **eyes**; the mouth only agrees with them. That is the
inverse of Western emoticons and it is the whole trick: change the eyes and the face
changes emotion, change the mouth and it changes volume.

**Eyes, by what they carry**

| Feeling | Eyes |
|---|---|
| bright, happy | ^ ´ ｀ ⌒ ᵔ ˘ ᴗ ‿ ◕ ◔ ⌄ |
| sparkling | ☆ ★ ✧ ✦ ✿ ❀ ◕ with ✧ beside it |
| wide, shocked | ⊙ ◉ ● ○ ｏ Ｏ ° ๏ 口 |
| crumpled, displeased | ＞ ＜ ˃ ˂ ≧ ≦ ᗒ ᗕ x |
| narrowed, unimpressed | ¬ ￣ ‾ ー 一 ˘ ･ ˙ |
| angry (order matters, ` before ´) | ` ´ ｀ Д 益 ㅂ 皿 |
| closed, asleep | ─ ‐ ｰ ￣ ˘ ᴗ ｡ ᵕ ᐢ |
| watery, wounded | ; ｡ ﾟ ╥ ಥ ᵥ ⌣ |
| soft, fond | ˘ ᵕ ꞈ ꈍ ᴗ ‿ ᵔ ･ |
| nervous | ･ ; ° ⌒ with a trailing ; |

**Mouths, which set volume not emotion**

ω ᴗ ▽ △ ‿ ﹏ ᆺ ³ ε з ᗨ ᗜ ヮ ワ 口 ロ 〇 д ﹃ ‸ ⌓ ᵜ 〜 ~ _ . o

Small and round (ω ᴗ ᵕ) is cute and quiet. Wide and open (▽ ヮ 口 д) is loud. A squiggle
(﹏ ‸ ⌓ 〜) is strain, pout, or sleep depending on the eyes above it.

**Borders** ( ) （ ） [ ] { } ʕ ʔ ｢ ｣, or none at all for the clipped ones.

**Arms and motion** ﾉ ノ ╯ ╰ づ ⊃ ⊂ ᕙ ᕗ ٩ ۶ ୧ ୨ ლ ง و ┻━┻ ︵ ミ 彡 ヽ

**Blush** /// ⁄⁄ ,, ๑ ˶ ｡ · **Extras** ☆ ✧ ♪ ♡ ﾟ ・ ｡ ; ~ 〜 zzz ..zZ

A trailing `;` is sweat, a doubled bracket (( )) is a shiver, `,,` inside the parens is
a blush.

## Ordering: the pool is an arc, not a bag

The app **walks** the pool in written order, so order carries meaning:

- **day pool: loudest first, quietest last.** The feeling at full when fresh, cooling
  over the following hours. A good mood set at noon settles by evening on its own.
- **`--morning`: sleepiest first**, so the band wakes up across itself.
- **`--evening`, `--night`, `--late`: most awake first, most drooped last.**

A one-face pool is legal and means the feeling did not move.

## The five bands

| Flag | Hours | What it wears |
|---|---|---|
| `--morning` | 05:00–08:59 | barely on |
| (plain list) | 09:00–17:59 | the day's mood at full |
| `--evening` | 18:00–22:59 | the loosest, warmest band |
| `--night` | 23:00–00:59 | quieter |
| `--late` | 01:00–04:59 | clipped, drooping |

An omitted band falls back: `--night` to `--late`, everything else to the day pool.

## Reactions and blinks

The mood is the baseline; these are what the bar does when something is happening.

- **`--working`** is worn while a session is mid-task, and walks its own arc over about
  twenty minutes: write it **freshest first** and let the tail get visibly bored.
- **`--attention`** is worn while a tab is asking for attention. **Calmest first**, and
  let it escalate.
- **`--greet`** flashes when the panel opens after a real absence.
- **`--blink FACE FRAME`** gives one face its blink frames. A frame is a **near-twin**
  of its face (eyes closed, mouth changed); anything further reads as a glitch. Frames
  are exempt from the bench, and Reduce Motion turns blinking off.

**The stability law.** The face never changes because someone interacted with it. A
reaction has to persist before the face follows, leaving one returns to the face worn
before, and the hello is for an arrival, not a glance. The app enforces all of this,
nothing to do here except write pools that read as one being rather than a costume rack.

## A compass, not a menu

Directions only, and every face suggested anywhere is burned the moment it is written
down. Aim the parts bin: bouncy · delighted · excited · smug · soft · curious ·
determined · focused · mischievous · impressed · relieved · dramatic · pouty · bored ·
mad · sulking · confused · nervous · flustered · moved · sleepy · drained · cold ·
under the weather · plain. Most days land between two of them and wear both.

---

*If the same face shows up twice in one week, it stopped being a mood and became a logo.*

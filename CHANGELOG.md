# Changelog

What changed, in words that say which thing. Not "bug fixes and stability
improvements", that phrase tells a user nothing and is
[specifically what the guidance warns
against](https://uxcam.com/blog/app-versioning-best-practices/).

Versions follow [Semantic Versioning](https://semver.org/); the scheme and the
city each era is named after are in [docs/versions.md](docs/versions.md).
**0.x is initial development. 1.0.0 is the public release.**

## 1.0.1: 2026-08-16

**The working light learned the new engine's rhythm.** The light — the
chip's glow and the menu-bar glyph's breath alike — keyed on "the
conversation file was written in the last few seconds", and the engine
that arrived on 2026-08-14 thinks and runs tools for minutes between
writes, so the light sat dark through exactly the work most worth
showing. When the file goes quiet the app now reads the conversation's
tail and asks whether the turn is actually open (a model still running
tools, or a prompt it owes an answer) and lights accordingly. A file
quiet past ten minutes reads as a crash and the light lets go, which
also keeps a restart's wait-for-quiet from being held hostage.

## 1.0.0: 2026-08-09

**Tokyo. The public release.** The same app that was running yesterday as
0.14.3, wearing the number it was saving for the day the repo opened up.
Everything below shipped in the run-up.

**The click pass: every button pops back.** A press already sank each
control a hair; now the release is a real spring, so every button in the
bar (chips, pin, plus, session starter, the find bar's three icons)
snaps back past rest and settles, the down-stroke still glued to the
finger (Peter, 2026-08-09: chunky, clicky, physics). The held menu rows
(Restart, Quit, Uninstall) grew their own hand-rolled physics: the row
sinks under the finger on a spring that overshoots on release, the hover
wash fades in and out instead of snapping, the charge wears a brighter
lip on its leading edge so it reads as a level rising, an early click's
teaching flash charges up instead of blinking on, and an aborted hold
eases off fast-then-gentle in the same rewind window every hold shares.
The charge itself stays linear on purpose: it is a countdown to something
irreversible, and a countdown that eases lies about how much time is
left. Presses stay felt-silent per the grammar (the haptic words still
belong to actions) and Reduce Motion stills every scale while keeping
the fades. Tuned the same morning after first hands-on: the first cut
wobbled ("a little too much jiggle"), so both springs now settle after
one soft overshoot.

**The about card becomes a plaque.** The panel row was the one line on the
card that was not identity: a how-to sitting on what is otherwise a
nameplate (Peter, 2026-08-09, "the about should be like a authenticity
plate like how limited cars have cool placks"). It also told half the
truth, naming one of the panel's two keys. The row is gone from the drawn
card and the plain fallback both, and the shortcut now lives where a Mac
advertises keys: a Show Panel / Hide Panel row in the status-item menu
with ⌃` printed beside it, next to the shortcuts card that already lists
both. What the card keeps is what a plaque keeps: name, era, version,
build, engine, brain, license.

**The felt pass: an Apple-eye sweep over the feature wave, haptics first.**
The felt grammar is now enforced end to end instead of merely written down.
The bell no longer drums the trackpad under a hand that is already looking
at the ringing tab; a summons is for somebody elsewhere, and hidden tabs and
a tucked panel still get the full pattern. Every close speaks its gone-now
knock from one place, whichever gesture asked, where before only the held x
did and a plain click on an ended tab closed in silence. The midnight
curfew reap went quiet on purpose: the alert is the only word the app may
say unprompted, and a reap is housekeeping. And the summons pattern itself
stopped ending on the deny sensation, so the two words can no longer be
confused by touch. Around the haptics, the details an Apple pass exists
for: the plus bounces for tabs that land, not tabs that leave; Escape
mid-rename now cancels the way Finder's does instead of being caught by the
click-away commit, and a double-click on a chip opens the rename; the
switcher's rows are real buttons VoiceOver can press, ⌘K toggles it away,
Return over nothing keeps the query, and picking a tab any other way
dismisses it; the find bar reads and writes the Mac's shared find
pasteboard, so a search follows you between apps and survives the bar
closing, and its icon buttons carry words for a screen reader; a reorder
released between chips still commits with its knock instead of leaving the
gesture unanswered; the away notification clears from Notification Center
the moment the panel opens, and arrives honest: the switch follows a
"Don't Allow", and an old system-level block gets explained with a door to
System Settings rather than a checkmark that lies. The filed-note line
re-shows when the same refusal happens twice, Actual Size greys out at
actual size, the tour stamps itself shown only when it actually shows and
now teaches the chip's right-click menu, the least discoverable thing the
wave shipped, and the pin's eye-tuned resting strengths moved into the
design file, closing the last open row from the HIG audit.

**The ring purge, and the drag ratchet.** The press states shipped with a
regression Peter's screenshot caught the same night: the style carrying them
stopped suppressing the system's grey focus rectangle, so every click grew a
box inside the capsule, on chips, the pin, the plus, and the find bar's
field. The app draws its own focus ring, in the accent, on the keyboard
walk; the system's is now switched off everywhere ours goes, which restores
the one-control-one-ring rule the 08-04 pass established. And reordering
got its feel: every swap mid-drag ticks, the same ratchet the hold-to-close
ring counts in, with the drop keeping its knock. Smaller polish rode along:
⌘F with the bar already open hands the field back, the find bar's chevrons
dim when there is nothing to step and wash on hover, the switcher settles in
rather than appearing and its highlight follows the pointer as well as the
arrows, a tab rename survives a click-away the way Finder's does, and the
filed-note line rises into place instead of blinking on.

**Find (⌘F).** The one table-stakes terminal feature the panel lacked:
finding something said earlier in a long session meant scrolling and
squinting. A find bar drops in under the tabs now. It searches as you type,
Return and Shift-Return step through the matches (⌘G and ⇧⌘G as well), a
miss says "no matches" in words, and Escape hands the keyboard back to the
terminal. The searching itself is the terminal library's own.

**Jump to a tab by typing its name (⌘K).** A small overlay over the
terminal: a few letters, Return, and you are there. Arrow keys move the
highlight, Escape leaves everything untouched. Starts earning its keep at
five or more tabs, which the tab restore actively encourages.

**Tabs answer to their own names, in their own order.** Right-click a chip
to rename it: the name you type outranks whatever the session last called
itself, survives restarts with the tab list, and emptying it hands the title
back. And chips finally drag to reorder. Cmd-1 through 9 follow the new
positions, because the number is an address on the bar, not a name, and
renumbering a tab used to mean closing and reopening it.

**A conversation can be filed into the brain.** Right-click a chip, File
into Brain, and that tab's conversation lands in 00-inbox as a Markdown
note, frontmatter and all: just the words said, no tool noise, no machinery.
The transcript was already on disk and the brain was already the working
folder, so this was a parse and a write. No competitor has a reason to build
it, which is exactly why it exists.

**The new-session button carries starters.** Right-click the plus and it
offers prepared openings read from the brain's own `_meta/starters.json`:
the app selects, writers compose, and a brain with no starters keeps a plain
plus. The shipped skeleton seeds three so the feature is visible on day one.

**The red chip explains itself.** A tab that failed to launch twice wore the
loudest colour on the bar and said nothing. Clicking the red bead, or the
chip's right-click menu, now opens a card that says what was refused and
what to try, in order, in words a stranger can use.

**A welcome tour.** The field test watched strangers find the glyph, the
pin, the held closes and the face slowly or not at all. A third card names
all of them in one screen. It lands on the bar exactly once, right after
first run, without stealing the setup tab, and lives in the Help menu and
the glyph's menu forever after.

**The bell can follow you away, if you ask it to.** At the Mac the bell is a
dot and a trackpad tap, which is exactly right there and invisible from
anywhere else. An opt-in switch in Settings routes bells that fire while you
are away through Notification Center, and tapping the alert lands in the
panel. Off by default: silent-in-class stays the bell's whole personality.

**The panel presses back.** Chips, the pin, the plus and the empty room's
button settle a hair on mouse-down and spring back on release. Visual only,
on purpose: the felt beat belongs to the action firing, not the touch.
Scrolling taps once on first contact with either wall of the scrollback, so
the finger learns the edge the eye already knows. And the four felt words
the app has always spoken (tap aligned, thunk committed, deny refused, alert
summons) are written down beside Motion and Ink in the design file, so a
missing beat is now visible by inspection the way a wrong colour already
was.

**A dormant tab holds its seat.** A restored tab that was never opened used to
close on a bare click, and one stray click silently cost a saved conversation
its place on the bar, felt by nothing and undone by a trip through Reopen
Conversation that most people would never find. Dormant tabs now take the same
held ring as a live session, ticks and all. Ended tabs and the cards still
close on a click, because nothing sits behind either.

**The menu went on a diet.** The right-click menu had grown past what a glance
takes in, so everything a person sets moved behind one Settings door: both
switches, the alert sound, and the engine's updater, which also answers which
Claude Code is loaded and when it last checked. The top level keeps identity,
the cheat sheet, the rows a person acts on, and the destructive block, in that
order.

**The app lists its own keyboard shortcuts.** Nine bindings had accumulated
and not one of them was written down anywhere a person could read. Cmd-1
through Cmd-9 jump straight to a tab, and Control-comma opens the panel for
keyboards that make the backtick awkward; both existed only in the source, so
in practice nobody had them. There is a card now, on Cmd-slash, in the Help
menu and in the menu bar's own menu, and it opens as a tab the way the about
card does.

**Restart, Quit and Uninstall have to be held down.** They end every session at
once, or the app, and they were three ordinary rows that a slipped pointer
could land on. The tab bar settled this argument a while ago: a live session
does not close on a click, you hold the x and a ring fills. These rows borrow
it, ticks and all. Uninstall is last, under its own rule, holds longest, and is
the only row that wears red, it tints red under the pointer and fills red as
it charges. Cmd-Q is untouched, because a Mac where the standard quit key does
nothing is a broken Mac. Three edges the first cut missed are in too. A plain
CLICK on one of these rows now answers: the charge flashes part way and runs
back down with the felt no, so the row teaches its own hold instead of playing
dead. Escape pressed mid-hold now genuinely calls the hold off, before, the
charge kept counting after the menu closed, and a person who backed out at
nine tenths could still watch the app quit under them. And assistive tech gets
a straight press: VoiceOver has no pointer to slip, so for it the hold does
not exist and the rows answer like buttons, with the destructive ones still
guarded by their own dialogs behind the press.

**The about card stopped colliding with itself.** The licence line was one long
sentence that ran clean through the tower's observation deck, three of the
stars were painted on top of the title, and one of the near buildings punched a
dark rectangle through the tower's lower right leg. Type now stops well short
of the tower, stars keep off the type, and the tower is drawn last so nothing
stands in front of it.

**Fixed: the menu bar's own menu opened in the wrong place.** Right-clicking
the glyph put the menu a long way to its right, floating in the middle of the
bar under nothing in particular. The app handed the menu to the status item and
sent its button a synthetic click, which is the recipe everybody uses and which
misplaces the menu when the click is sent from inside the handler for the click
still being delivered. The menu is anchored to the button itself now, on the
button's own coordinate grid, which runs top-down, a detail the first cut of
this fix had upside down, so the menu would have leaned on the screen edge to
land anywhere sensible. Control-click opens the same menu now too, because
control-click has been the Mac's one-button right-click since before two
buttons were normal, and a status item wired by hand has to keep that promise
itself.

**The shortcuts card reads like a cheat sheet.** Two columns when the panel is
wide enough and one when it is not, keys in a single accent colour against grey
descriptions, a rule running off each group heading, and real Mac glyphs, so it
says ⌘T rather than spelling out the word command.

**Both cards follow the window now.** The about card and the shortcuts card
were drawn once, at whatever size the panel happened to open at, and went deaf:
resize the panel and the picture scrolled its own top away, or the cheat sheet
sat in one squeezed column with half the window empty beside it. Each card now
notices the window changing shape and redraws itself for the new one. The two
column choice is made fresh every time, and the size is read off the terminal
device itself, because the shell's own idea of it is frozen at launch and the
usual tools just repeat that back.

**A card closes like a page, not like a session.** Cmd-W on the about or
shortcuts card used to bounce off, and the x demanded the full held ring, the
guard built for a tab with a live claude behind it, standing in front of a
static page holding nothing. A card closes on a plain click and a plain Cmd-W
now; return still works from inside it.

**The pin stopped hiding.** It used to fade in when the pointer reached the tab
bar, which is a fair trade for a secondary control in a bar that small and a
bad one for anybody who does not already know the control is there. It sits on
the bar at all times now, dim until it is on, and it leans fifteen degrees, so
it reads as a pin stuck into something rather than as a picture of a pin.

**A new install wears a face on day one.** Pools are written by sessions, so a
fresh Mac had none and the menu bar sat there as a bare glyph until the
assistant got round to composing one, somebody could use Rin for an afternoon
and never find out the feature existed. The default persona now ships with an
opening pool, filled across all five clock bands so it drifts through the day
the way a written one does. It is a first impression, not a feeling: the first
pool a session writes retires it permanently, and a pool that later goes stale
still clears the bar rather than falling back to it.

**Fixed: one repeated face in a pool froze the whole app.** Rotating the menu
bar expression picked its next face by re-rolling until the roll differed from
the one already worn. A pool holding the same face twice makes that
unsatisfiable, more than one candidate, every one of them identical to the
current, so the loop ran forever on the main thread and the menu bar stopped
answering. It now picks from the faces that differ, which cannot spin. The
writing script already refused a duplicate, but the pool is plain json in
somebody's own folder and that script was never the only thing able to write
one.

**Fixed: the app shipped whatever was lying around at build time.** The blank
brain is bundled as a folder reference, so it carried python bytecode and
Finder droppings straight out of the working copy, none of it committed,
which is why nobody caught it, and two builds on the same Mac shipped two
different piles. All of it was then copied into a new user's brain folder on
first run, into the one place the product asks people to open and read. The
build prunes it now.

**Removed: a debug line that logged on every bell.**

**The symbols move now, in three places and nowhere else.** The pin flipped
between outline and filled with no transition at all, so it teleported; it
swaps properly now. The plus answers when a tab actually lands, whichever way
it was opened. And a Cmd-W refused by a working tab makes the close control
itself react, rather than only nudging the chip around it. Apple's own
guidance is to keep motion off things people do constantly, so this is three
places rather than a coat of polish, and every one goes still under Reduce
Motion.

**Fixed: a tab nobody was looking at was still being drawn.** Any tab that is
not the front one, and the front one whenever the panel is back in the menu
bar, kept running the whole display pass on every arriving byte, moving the
caret, rebuilding its glyph, telling accessibility the value changed, marking
a region stale, sixty times a second, into a view AppKit was never going to
paint. The throttle was on the frame rather than on whether the frame was
worth drawing. The parse is untouched, so a hidden tab still updates its title
and still rings its bell; only the painting is skipped, and it is repaid in
full the moment the tab comes forward or the panel returns.

**One session is a chip again, not a bar.** A lone tab used to stretch the
full width of the panel with an eleven point label centred in it, which read
as a title bar. Safari, Finder and Terminal all answer this by hiding the tab
bar entirely at one tab, and they can because their bar holds tabs and nothing
else. This one also holds the pin, the new-session button and the working
light, so the bar stays and the chip sizes to its own label.

**Fixed: the site printed badly, in four separate ways.** Addresses printed
after every single link, which squeezed each button into a column five
characters wide and, on the two icon-only links at the foot, broke out of
their section and landed on top of the footer a page later; they print once
now, in the footer list. The shadow reset named four selectors on a page with
more than four, so the black button laid a filled rectangle over the text
beside it, and a solid button is now an outlined label rather than a slab of
ink. The FAQ printed as questions with no answers, because nothing unfolds a
closed disclosure on paper. And the modules page never had the black-on-white
rule the landing page had, so it printed in whatever colours the screen
happened to be using.

**The brain a stranger gets grew a memory and a spine.** It shipped as a voice
with nothing behind it: a persona file, an empty ledger, and no machinery to
keep either alive past the first long session. The folder now carries four
hooks (the voice re-anchored at the point replies are written, a stop-check for
machine-writing tells, the folder's state handed to each session, and a note
lint that keeps chat voice out of files), plus `_meta/becoming.md`, which
teaches the assistant how a described character turns into someone over weeks:
the dials, the first week, calls scored honestly, and the research reason a
companion that only ever agrees gets switched off.

**One new job, `save`.** Nothing outside a conversation ever demands that the
day be written down, so it is the job that gets skipped, and skipping it is why
an assistant wakes up as a stranger every morning. It sweeps the session,
writes the day card, moves the dials on evidence, and proposes profile changes
rather than making them.

**Jokes, where they will be found.** Small dry notes at the bottom of the
folder readmes, the wardrobe, the job list, and one in a script's help text.
None of them near a verdict, a number, or anything anyone acts on.

**No dates and no owner anywhere in the shipped folder.** Frontmatter stamps
and example timestamps both: a file that ships with a real date says when it
was written and who was using it at the time.

## 0.11.3: 2026-08-04

Renumbered from 1.11.3. The old number claimed eleven feature releases of a
stable app; this one is honest about being pre-release, and it leaves 1.0.0 for
the day Rin actually ships.

**The about card is one full-page picture.** Tokyo Tower over a dusk skyline,
drawn at the size of the window it opens in, with the version block sitting
inside the sky instead of on a strip underneath it. Opens as a tab and closes
like one.

**Fixed: every row of that card carried a hairline seam.** The art was built
from half blocks, which split a cell into two pixels of different colours; a
terminal paints each row's background as its own rectangle, and those do not
quite meet when the view height is not a whole number of device pixels. Now one
colour per cell, which has nothing to reveal at the boundary.

**Fixed: the kanji in the title was cut in half.** A CJK glyph occupies two
cells and was being painted into one.

**Fixed: the stars were debris.** Two cells wide and nearly white, so on a
narrow window one landed in the middle of the version block. Now one cell, dim,
top rows only, and fewer of them on a small window.

**Fixed: `install.sh` had been installing a nine-day-old app.** It read the
repo's own `build/` directory while the documented build command writes to
DerivedData, so a fresh build was invisible to it and the last in-repo build got
copied instead, silently and with no error. It now takes the newest of the two
and names which one it used.

**The status menu lost two rows and two dividers.** Bell Chime folded into Alert
Sound, which is now one question, Silent, or which chime, instead of a
checkbox and a picker that could disagree. Picking a chime turns sound on and
plays it.

**Version numbers stopped being typed.** `scripts/release.py` owns the bump, the
build number is the commit count, and a pre-build check fails the build on a
hand-typed version or an era with no city drawn for it. Installing refuses a
build whose number already matches what is running.

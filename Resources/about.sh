#!/bin/zsh
# the about card
# opens as a tab because a screen that needs room should be a tab not a window

# The about card. Opens as a TAB rather than a window or a panel screen
# (Peter's standing call, 2026-08-04: "if there ever are gonna be more settings
# have it open in a tab like how claude code opens a tab"). The terminal is
# this app's material, so a screen that needs room becomes a tab in the bar and
# closes like one.
#
# The card itself is ONE full-page picture with the text inside it, drawn by
# card.py at the size of the window it is being shown in (Peter, 2026-08-04:
# "make the drawing the whole page"). Everything below is just gathering what
# the picture needs to say. The technique is in docs/full-page-art.md.
#
# Every ERA is named after a place in Japan and the card draws it. The place
# belongs to the MAJOR version, so every fix and feature inside an era keeps
# the same city. **1.x is Tokyo** (Peter, 2026-08-04), and 0.x is the run-up to
# it, so the card wears Tokyo now and keeps wearing it when the app actually
# ships. An era nobody has named draws the plain card, because shipping must
# never be blocked on choosing a city. Rule in docs/versions.md, enforced by
# scripts/check-version.py.
set -u

accent=$'\e[38;5;215m'
dim=$'\e[38;5;246m'
bold=$'\e[1m'
reset=$'\e[0m'

version="${RIN_VERSION:-?}"
build="${RIN_BUILD:-?}"

era="${${version%%.*}%%-*}"
case "$era" in
  0|1) place="Tokyo" ;;
  1) place="Tokyo" ;;
  *)   place="" ;;
esac

# The engine's version off its own symlink, the same place the menu reads it:
# the link never lies, and asking the binary costs a quarter-gig launch.
engine="not installed"
link="$HOME/.local/bin/claude"
if [ -L "$link" ]; then
  target="$(readlink "$link")"
  name="${target##*/}"
  case "$name" in
    [0-9]*) engine="Claude Code $name" ;;
    *) engine="Claude Code" ;;
  esac
elif command -v claude >/dev/null 2>&1; then
  engine="Claude Code"
fi

brain="${RIN_BRAIN:-not chosen yet}"
brain="${brain/#$HOME/~}"

# Where this script lives, resolved at TOP LEVEL and nowhere else: inside a
# zsh function $0 names the function, so asking there answers "draw" instead
# of the script and the tower silently gives way to the plain card. That is
# exactly how the art vanished from the 0.14.0 build (2026-08-08).
here="${0:A:h}"

# The whole card, drawn fresh at the CURRENT size. In a function because the
# panel resizes under it: the picture is composed for one exact window, so a
# card drawn once and left behind scrolls its own top away the first time the
# window changes shape: the one page whose whole job is fitting the window.
# card.py exits 2 when the window is too small, which is the signal to fall
# through to the plain card rather than draw something cramped.
draw() {
  # The size this draw is FOR, recorded whole: the poll below compares the
  # live size against it, so a draw that raced the window settling (launch is
  # exactly such a race) heals on the next tick instead of sticking. stty,
  # and neither $COLUMNS nor tput: a script's zsh reads the size once at
  # launch and never updates it, and tput repeats that stale $COLUMNS back
  # rather than asking the terminal (both measured in a pty, 2026-08-08).
  size="$(stty size 2>/dev/null || true)"
  rows="${size%% *}"
  cols="${size##* }"
  [[ "$rows" == <-> ]] || rows=24
  [[ "$cols" == <-> ]] || cols=80
  clear
  drawn=0
  if [ -n "$place" ] && command -v python3 >/dev/null 2>&1; then
    for candidate in "$here/card.py" "$here/../card.py"; do
      [ -f "$candidate" ] || continue
      if python3 "$candidate" \
          --cols "$cols" --rows "$rows" \
          --version "$version" --build "$build" --place "$place" \
          --engine "$engine" --brain "$brain" 2>/dev/null; then
        drawn=1
      fi
      break
    done
  fi

  # The plain card: the fallback for a window too small, a release line with no
  # city, or a Mac with no python3. Alignment is rules rather than a box, because
  # the brain path is whatever length it is and a framed card with a
  # variable-width row inside it breaks the moment somebody keeps their notes
  # somewhere with a long name.
  if [ "$drawn" -eq 0 ]; then
    rule="   ${dim}────────────────────────────────────────${reset}"
    print ""
    print "   ${bold}凛${reset}  ${bold}Rin${reset}"
    print "   ${dim}A menu-bar home for Claude Code.${reset}"
    print ""
    print -- "$rule"
    print "   ${dim}version${reset}      ${version}  ${dim}(build ${build})${reset}"
    print "   ${dim}engine${reset}       ${engine}"
    print "   ${dim}brain${reset}        ${brain}"
    print -- "$rule"
    print ""
    print "   ${dim}Free and open source, MIT licensed.${reset}"
    print "   ${dim}Bundles SwiftTerm, also MIT.${reset}"
    print "   ${accent}github.com/exata531/Rin${reset}"
    print ""
    print ""
    print "   ${dim}press return to close this tab${reset}"
  fi
}

draw

# Wait for return, redrawing when the window changes shape. A poll rather
# than a WINCH trap, because zsh queues a script's traps until the enclosing
# loop finishes (measured in a pty, 2026-08-08): the trap route redraws only
# after the keypress that closes the card, which is a redraw for nobody. One
# half-second tick, one stty per tick, only while this card is on screen.
while true; do
  read -t 0.5 -r _ && break
  # The tty going away is the tab going away; do not spin on a dead stdin.
  [[ -t 0 ]] || break
  now="$(stty size 2>/dev/null || true)"
  [[ "$now" != "$size" ]] && draw
done

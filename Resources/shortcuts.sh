#!/bin/zsh
# the keyboard shortcuts card
# opens as a tab because a screen that needs room should be a tab not a window

# Every key this app answers to, in one place (2026-08-08, Peter's ask). Nine
# bindings had accumulated and none of them were written down anywhere a person
# could read: Cmd-1 through Cmd-9 existed only in the source, and Control-comma
# as a second way to the panel was known to nobody at all. A shortcut nobody
# can discover is a shortcut nobody presses.
#
# It is a TAB, per the standing call (2026-08-04: "if there ever are gonna be
# more settings have it open in a tab like how claude code opens a tab"), which
# is the same shape the about card takes.
#
# The LAYOUT is borrowed on purpose (Peter, 2026-08-08: "take insperation from
# other terminal ui apps then design it like them"). Every cheat sheet worth
# copying: k9s, lazygit, tig, helix: does the same four things, and this does
# all four:
#
#   1. Key caps in ONE accent colour, description in grey. The eye scans one
#      column, not a paragraph.
#   2. Groups under a heading with a rule running off the end of the title, so
#      the eye finds a section before it reads a word.
#   3. TWO columns when the window is wide enough, one when it is not. A cheat
#      sheet you have to scroll is not a cheat sheet, and lazygit's is two
#      columns for exactly that reason.
#   4. Real Mac glyphs. This is where a Mac app should beat every one of them:
#      "command  T" is a description of a key, and ⌘T is the key.
#
# Padding is computed from the PLAIN strings and the colour wrapped around the
# result afterwards, because an escape sequence counts as characters to printf
# and would knock every column out by exactly the width of the colour codes.
set -u

accent=$'\e[38;5;215m'
dim=$'\e[38;5;246m'
hair=$'\e[38;5;239m'
bold=$'\e[1m'
reset=$'\e[0m'

KEYW=6
DESCW=30
INDENT=3
COLW=$(( INDENT + KEYW + 1 + DESCW ))
blank=""

# One key and what it does, padded to a fixed cell.
cell() {
  local k="$1" d="$2"
  local kp=$(( KEYW - ${#k} )); (( kp < 0 )) && kp=0
  local dp=$(( DESCW - ${#d} )); (( dp < 0 )) && dp=0
  print -n -- "${(l:$INDENT:)blank}${accent}${k}${reset}${(l:$kp:)blank} ${dim}${d}${reset}${(l:$dp:)blank}"
}

# A note under a key, in the description column, with no key beside it.
under() {
  local d="$1"
  local dp=$(( DESCW - ${#d} )); (( dp < 0 )) && dp=0
  print -n -- "${(l:$(( INDENT + KEYW + 1 )):)blank}${dim}${d}${reset}${(l:$dp:)blank}"
}

# A group heading with the rule running out to the end of the column.
group() {
  local t="$1"
  local w=$(( COLW - INDENT - ${#t} - 1 )); (( w < 0 )) && w=0
  print -n -- "${(l:$INDENT:)blank}${bold}${t}${reset} ${hair}${(l:$w::─:)blank}${reset}"
}

gap() { print -n -- "${(l:$COLW:)blank}"; }

left=()
left+=("$(group 'Panel')")
left+=("$(cell '⌃ `' 'show or hide, from any app')")
left+=("$(cell '⌃ ,' 'the same, easier to reach')")
left+=("$(gap)")
left+=("$(group 'Text')")
left+=("$(cell '⌘ +' 'bigger')")
left+=("$(cell '⌘ -' 'smaller')")
left+=("$(cell '⌘ 0' 'back to normal')")
left+=("$(gap)")
left+=("$(group 'This app')")
left+=("$(cell '⌘ /' 'this card')")
left+=("$(cell '⌘ Q' 'quit Rin')")

right=()
right+=("$(group 'Tabs')")
right+=("$(cell '⌘ T' 'new session')")
right+=("$(cell '⌘ 1-9' 'jump straight to that tab')")
right+=("$(cell '⌘ K' 'find a tab by typing its name')")
right+=("$(cell '⌘ W' "close it, if it isn't working")")
right+=("$(under 'hold its x to close it anyway')")
right+=("$(gap)")
right+=("$(group 'Editing')")
right+=("$(cell '⌘ C' 'copy')")
right+=("$(cell '⌘ V' 'paste')")
right+=("$(cell '⌘ A' 'select all')")
right+=("$(cell '⌘ F' "find in this tab's scrollback")")
right+=("$(under 'then ⌘G and ⇧⌘G step matches')")

# The whole page, drawn fresh at the CURRENT width. In a function because the
# panel resizes and a cheat sheet frozen at its opening width answers a
# question nobody is asking any more: two columns squeezed into a narrowed
# window wrap into hash, one column in a widened window wastes the room the
# resize just bought. stty, and neither $COLUMNS nor tput: a script's zsh
# reads the size once at launch and never updates it, and tput repeats that
# stale $COLUMNS back rather than asking the terminal (both measured in a
# pty, 2026-08-08). stty asks the device itself and is right after every
# resize.
draw() {
  # The size this draw is FOR, recorded whole: the poll below compares the
  # live size against it, so a draw that raced the window settling (launch is
  # exactly such a race) heals on the next tick instead of sticking.
  size="$(stty size 2>/dev/null || true)"
  cols="${size##* }"
  [[ "$cols" == <-> ]] || cols=80
  clear
  print ""
  print "${(l:$INDENT:)blank}${bold}凛${reset}  ${bold}Keyboard${reset}"
  print ""

  if (( cols >= COLW * 2 + 2 )); then
    # Two columns, the shape every cheat sheet in a terminal takes. The shorter
    # side is padded with empty cells rather than left ragged, so the last rows
    # of the tall column keep their own left edge.
    n=$(( ${#left} > ${#right} ? ${#left} : ${#right} ))
    for (( i = 1; i <= n; i++ )); do
      l="${left[$i]:-}"
      r="${right[$i]:-}"
      [ -z "$l" ] && l="$(gap)"
      print -- "${l}  ${r}"
    done
  else
    # One column: the same cells, stacked. A narrow panel gets a list it can
    # actually read instead of two columns fighting over the width.
    for l in "${left[@]}"; do print -- "$l"; done
    print -- "$(gap)"
    for r in "${right[@]}"; do print -- "$r"; done
  fi

  print ""
  print "${(l:$INDENT:)blank}${dim}Everything else belongs to Claude Code, and its keys work${reset}"
  print "${(l:$INDENT:)blank}${dim}in here exactly as they do in any terminal.${reset}"
  print ""
  print "${(l:$INDENT:)blank}${hair}press return to close this tab${reset}"
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

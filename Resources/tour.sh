#!/bin/zsh
# the welcome tour one screen naming the things a stranger finds slowly
# the field test showed people discovering all of this by accident or not at all

# The lay of the land in one screen (2026-08-08). The field test's lesson was
# that the glyph, the pin, the held closes and the face are all invisible
# until stumbled on: each one works the first time it is tried, but nothing
# says it exists. This card says so once, right after first run (without
# stealing the setup tab), and lives in the menus after that.
#
# A TAB, per the standing call. Same skeleton as the shortcuts card, one
# column, prose-width lines.
set -u

accent=$'\e[38;5;215m'
dim=$'\e[38;5;246m'
hair=$'\e[38;5;239m'
bold=$'\e[1m'
reset=$'\e[0m'

clear
print ""
print "   ${bold}凛${reset}  ${bold}The lay of the land${reset}"
print ""
print "   ${accent}The glyph${reset}  ${dim}凛 lives in your menu bar. Click it and the panel${reset}"
print "   ${dim}drops; click again and it tucks away. It is also on ${reset}⌃\`${dim} from${reset}"
print "   ${dim}inside any app, and right-clicking it opens the menu.${reset}"
print ""
print "   ${accent}The face${reset}  ${dim}The little expression beside the glyph is your${reset}"
print "   ${dim}assistant's mood, written by your own sessions. A bare glyph${reset}"
print "   ${dim}just means nothing has moved it yet.${reset}"
print ""
print "   ${accent}The pin${reset}  ${dim}The panel closes when you click into another app.${reset}"
print "   ${dim}The pin on the tab bar keeps it open instead.${reset}"
print ""
print "   ${accent}Closing tabs${reset}  ${dim}A live session will not close on a stray click:${reset}"
print "   ${dim}hold its ${reset}x${dim} while the ring fills. Ended tabs close on a click.${reset}"
print ""
print "   ${accent}The beads${reset}  ${dim}A coloured dot on a chip is that tab saying${reset}"
print "   ${dim}something: hover it for the words. Grey is ordinary life.${reset}"
print ""
print "   ${accent}The chip's menu${reset}  ${dim}Right-click a tab to rename it, or to file${reset}"
print "   ${dim}the whole conversation into your brain as a note.${reset}"
print ""
print "   ${dim}Every key the app answers to is on the cheat sheet:${reset} ⌘/"
print ""
print "   ${hair}press return to close this tab${reset}"

while true; do
  read -t 0.5 -r _ && break
  [[ -t 0 ]] || break
done

#!/bin/zsh
# the card behind the red bead
# a tab that failed to launch twice used to show the loudest colour and explain nothing

# What a red chip means and what to try, in words a stranger can use
# (2026-08-08). The red bead is the one state the bar cannot talk its way
# out of: the launch itself was refused, twice, once with each resume flag,
# so waiting will not fix it and the tooltip's three words were all anyone
# got. A click on the bead, or the chip's right-click menu, opens this.
#
# A TAB, per the standing call: a screen needing room is a tab, never a
# window. Same skeleton as the shortcuts card, minus the columns: prose
# reads in one column at any width.
set -u

accent=$'\e[38;5;215m'
red=$'\e[38;5;203m'
dim=$'\e[38;5;246m'
hair=$'\e[38;5;239m'
bold=$'\e[1m'
reset=$'\e[0m'

clear
print ""
print "   ${bold}凛${reset}  ${bold}This tab could not start${reset}"
print ""
print "   ${red}●${reset} ${dim}A red bead means the launch itself was refused, twice.${reset}"
print "   ${dim}That is a different problem from a session that ran and ended:${reset}"
print "   ${dim}the conversation is still on disk, but claude would not open it.${reset}"
print ""
print "   ${bold}Things to try, in order${reset}"
print ""
print "   ${accent}1${reset}  ${dim}Right-click the red chip and pick${reset} Restart Session${dim}.${reset}"
print "      ${dim}A restart by hand gets a fresh try, and the hiccup that${reset}"
print "      ${dim}refused it is often already gone.${reset}"
print ""
print "   ${accent}2${reset}  ${dim}Check Claude Code itself: open a new tab (⌘T). If that tab${reset}"
print "      ${dim}works, claude is fine and the problem is this conversation.${reset}"
print ""
print "   ${accent}3${reset}  ${dim}Check the brain folder still exists where Rin left it.${reset}"
print "      ${dim}The about card (right-click the menu bar icon) says where.${reset}"
print ""
print "   ${accent}4${reset}  ${dim}If nothing helps, close the tab. The conversation stays on${reset}"
print "      ${dim}disk either way:${reset} Reopen Conversation ${dim}in the icon's menu can${reset}"
print "      ${dim}bring it back later.${reset}"
print ""
print "   ${hair}press return to close this tab${reset}"

while true; do
  read -t 0.5 -r _ && break
  [[ -t 0 ]] || break
done

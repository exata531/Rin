#!/bin/zsh
# the first run walkthrough you actually see in the terminal pane
# it installs claude picks the folder and seeds the blank brain then hands over to the conversation

# Rin first run: a TUI in the terminal, in Claude Code's own visual register.
# The app runs this in the first tab whenever no brain folder is configured.
#
# ORDER MATTERS HERE, and it changed on 2026-08-04. This used to install Claude
# Code before asking anything, on the reasoning that the app cannot run without
# it so an Enter meaning "yes obviously" was a speed bump. True on its own, and
# wrong in sequence: stacked behind macOS's own "this app was blocked" warning,
# a stranger's first two minutes were an override, then a script downloaded and
# run without a word, then an assistant that could already write files. Every
# step had a good local reason and the stack taught them that this app decides
# for them.
#
# So there is ONE grant, and it is the folder press. It states what the yes
# covers: scope, where the words go, the engine being installed, the login
# item: and after it, nothing asks again. Everything below the press is a
# consequence they already agreed to, out loud, where they can watch it.
set -u

accent=$'\e[38;5;215m'
dim=$'\e[38;5;246m'
green=$'\e[38;5;114m'
bold=$'\e[1m'
reset=$'\e[0m'

clear
print ""
print ""
print "      ${dim}｡ ﾟ ✻ ･${reset}  ${bold}凛${reset}"
print "   ${accent}██████╗ ██╗███╗   ██╗${reset}"
print "   ${accent}██╔══██╗██║████╗  ██║${reset}"
print "   ${accent}██████╔╝██║██╔██╗ ██║${reset}"
print "   ${accent}██╔══██╗██║██║╚██╗██║${reset}"
print "   ${accent}██║  ██║██║██║ ╚████║${reset}"
print "   ${accent}╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝${reset}"
print "      ${dim}･ ✻ ﾟ ｡${reset}"
print ""
print "  ${dim}A terminal that lives in your menu bar,${reset}"
print "  ${dim}and a brain for the assistant inside it.${reset}"
print ""

find_claude() {
  command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]
}

# ── The one grant ────────────────────────────────────────────────────────────
# Said before the press, in plain words, in the order a person would want to
# know it. Four lines, each one a thing that is about to become true.
print "  Everything it learns about you lives in one folder, on your Mac."
print ""
print "  ${bold}One press says yes to all of this, and nothing asks again:${reset}"
print ""
print "  ${accent}·${reset} Your assistant can read and change anything ${bold}inside that folder${reset},"
print "    ${dim}and nothing outside it. Your notes never leave this Mac.${reset}"
print "  ${accent}·${reset} What you ${bold}type to it${reset} goes to Anthropic, under the Claude account"
print "    ${dim}you sign into in a moment. Rin has no server and no account of its own.${reset}"
if ! find_claude; then
print "  ${accent}·${reset} ${bold}Claude Code${reset} is the engine underneath, and it isn't on this Mac yet."
print "    ${dim}It gets installed from Anthropic right here, where you can watch it.${reset}"
fi
print "  ${accent}·${reset} Rin starts when you log in, so ${bold}control + \`${reset} always brings it back."
print "    ${dim}You can turn that off in the menu bar whenever you like.${reset}"
print ""

# One Enter is the whole decision. The rules (empty folder, existing brain,
# odd homes) only speak up when someone actually walks into their case.
default="$HOME/Documents/Brain"
print -n "  ${accent}Press Enter${reset} to put it in ${bold}Documents ▸ Brain${reset}, or type another spot: "
while :; do
  read -r answer
  print ""
  folder="${answer:-$default}"
  folder="${folder/#\~/$HOME}"

  if [ -f "$folder/CLAUDE.md" ]; then
    print "  ${green}✔${reset} That folder already holds a brain, so it picks up where it left off."
    break
  fi
  if [ -e "$folder" ] && [ ! -d "$folder" ]; then
    print -n "  That's a file, not a folder. Try another spot: "
    continue
  fi
  if [ -d "$folder" ] && [ -n "$(ls -A "$folder" 2>/dev/null | grep -v '^\.DS_Store$')" ]; then
    print -n "  That folder already has things in it, and the brain wants one of its own. Another spot: "
    continue
  fi

  # Obviously bad homes get a warning, never a refusal.
  warn=""
  case "$folder" in
    "$HOME") warn="That would make your whole home folder the brain." ;;
    "$HOME/Desktop") warn="The Desktop fills up fast; Documents keeps it findable." ;;
    "$HOME/Downloads"*) warn="Downloads gets cleaned out, and the brain would go with it." ;;
    *"/Library/Containers/"*) warn="That spot belongs to another app and can vanish with it." ;;
    *"/Library/Group Containers/"*) warn="That spot belongs to another app and can vanish with it." ;;
  esac
  if [ -n "$warn" ]; then
    print -n "  ${accent}!${reset} ${warn} Type y to use it anyway, or press Enter to pick again: "
    read -r yn
    print ""
    case "$yn" in
      y|Y|yes) ;;
      *) print -n "  Another spot: "; continue ;;
    esac
  fi

  mkdir -p "$folder" 2>/dev/null || { print -n "  That folder couldn't be created. Another spot: "; continue; }
  # Contents including dotfiles: .claude/ is where the setup skill lives.
  cp -R "${RIN_SKELETON:?}/." "$folder/" || { print -n "  Something blocked that folder. Another spot: "; continue; }
  break
done
pretty="${folder/#$HOME/~}"
print "  ${green}✔${reset} Your brain lives at ${bold}${pretty}${reset}."

# ── Consequences of the press ────────────────────────────────────────────────
# The engine, installed out loud. No gate: they already said yes, and a second
# question here would be the app doubting a decision it just took.
if ! find_claude; then
  print ""
  print "  Installing ${bold}Claude Code${reset} now, every line of it, right here."
  print "  ${dim}This takes a minute on a fresh Mac. Nothing to press.${reset}"
  print ""
  curl -fsSL https://claude.ai/install.sh | bash
  print ""
  export PATH="$HOME/.local/bin:$PATH"
  if ! find_claude; then
    print "  The install didn't finish. The output above is the whole story."
    print "  ${dim}Quit and reopen Rin to try again, or install Claude Code by hand first.${reset}"
    print "  ${dim}Your brain folder is already made, so it picks up where this left off.${reset}"
    print ""
    exec /bin/zsh -l
  fi
  print "  ${green}✔${reset} Claude Code is installed."
fi
export PATH="$HOME/.local/bin:$PATH"

# A brand-new claude walks its own onboarding before anything else. Pre-set
# the theme to match the panel so one wizard screen never appears; sign-in
# and the trust prompt stay claude's, as they should.
if [ ! -f "$HOME/.claude.json" ]; then
  claude config set -g theme dark >/dev/null 2>&1 || true
fi

# Hand the chosen folder back to the app, then become the first conversation.
# The app reads this and turns on the login item, which the grant promised.
mkdir -p "$HOME/.config/rin"
print -r -- "$folder" > "$HOME/.config/rin/chosen-brain"
cd "$folder"
print ""
print "  ${bold}What happens next${reset}"
print "  ${dim}1. Claude Code signs you in: a browser window opens, use the${reset}"
print "     ${dim}Claude account you already have.${reset}"
print "  ${dim}2. Your assistant introduces itself and builds the brain with${reset}"
print "     ${dim}you: three questions, nothing written without your okay.${reset}"
print ""
print "  ${accent}If it sits quiet after sign-in, just say hi.${reset}"
print ""
# The one thing a person needs to carry out of this screen, said last so it is
# the last thing on it. Before 2026-08-04 the key was never taught anywhere in
# the app, so closing the panel could strand somebody in front of a menu bar
# icon they had no reason to click.
print "  ${dim}And whenever you close this panel:${reset} ${bold}control + \`${reset} ${dim}brings it back.${reset}"
print ""
# zsh does not word-split unquoted expansions, so the flags are built as a
# real array: the glued-together "--permission-mode auto" single argument
# was rejected by claude outright.
flags=()
[ -n "${RIN_PERMISSION_MODE:-}" ] && flags+=(--permission-mode "$RIN_PERMISSION_MODE")
[ -n "${RIN_SESSION_ID:-}" ] && flags+=(--session-id "$RIN_SESSION_ID")

# The opening prompt only rides along when claude is actually signed in,
# fired at a logged-out claude it just bounces off in red ("Not logged in")
# and the message is spent. Only claude's own word counts here: its config
# can carry account crumbs from an aborted sign-in, so the file is not
# evidence (learned live, 2026-08-03). Anyone not signed in gets a bare
# claude, whose sign-in flow is the real one, and the brain starts the
# walkthrough off their first word instead.
if claude auth status 2>/dev/null | grep -q '"loggedIn":[[:space:]]*true'; then
  exec claude "${flags[@]}" 'Run the setup skill.'
fi
exec claude "${flags[@]}"

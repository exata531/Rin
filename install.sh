#!/bin/bash
# Swap the freshly built Rin into /Applications and relaunch it.
# Detaches first, so it survives the session it was started from.
#
# Installing is the moment a version number starts mattering, so it is also
# where the number is checked (2026-08-04). Everything before this is an
# experiment; this is the step that puts a build in front of a person. A build
# carrying the same number as the one already installed gets refused, because
# two different apps answering to one version is how you end up debugging a
# thing that is not running.
set -e

# Where the build actually IS, rather than where it is assumed to be
# (2026-08-04). `xcodebuild` with no -derivedDataPath writes to DerivedData,
# and this script used to read only the repo's own build/, so a build made
# the documented way was invisible here and the last one made in-repo got
# installed instead. It had been stale for over a week without anyone noticing,
# which is exactly the silent-wrong-app failure the version check downstream
# exists to catch. Newest wins, and it says which one it took.
newest=""
for candidate in \
  "$HOME/Projects/Rin/build/Build/Products/Release/Rin.app" \
  "$HOME"/Library/Developer/Xcode/DerivedData/Rin-*/Build/Products/Release/Rin.app
do
  [ -d "$candidate" ] || continue
  if [ -z "$newest" ] || [ "$candidate/Contents/MacOS/Rin" -nt "$newest/Contents/MacOS/Rin" ]; then
    newest="$candidate"
  fi
done
NEW="$newest"
[ -n "$NEW" ] || { echo "no build found; run xcodebuild first"; exit 1; }

stamp() {
  plist="$1/Contents/Info.plist"
  [ -f "$plist" ] || return 1
  printf '%s (%s)' \
    "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist" 2>/dev/null)" \
    "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist" 2>/dev/null)"
}

if [ "${1:-}" != "--force" ]; then
  fresh="$(stamp "$NEW")"
  current="$(stamp /Applications/Rin.app || true)"
  if [ -n "$current" ] && [ "$fresh" = "$current" ]; then
    echo "refusing: $fresh is already what's installed."
    echo
    echo "  python3 scripts/release.py    bump the iteration, then rebuild"
    echo "  ./install.sh --force          install it anyway"
    exit 1
  fi
fi
nohup bash -c '
  osascript -e "quit app \"Rin\"" 2>/dev/null || true
  sleep 2
  pkill -f "/Applications/Rin.app/Contents/MacOS/Rin" 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Rin.app
  cp -R "'"$NEW"'" /Applications/Rin.app
  open /Applications/Rin.app
' >/dev/null 2>&1 &
echo "installing; Rin will reappear in a few seconds"

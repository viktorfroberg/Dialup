#!/bin/sh
# Installs the latest Dialup into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/viktorfroberg/Dialup/main/install.sh | sh
#
# Downloaded with curl, the app isn't marked as quarantined, so macOS doesn't show the
# "can't be opened" warning that a browser download of an un-notarized app gets. After this,
# Dialup updates itself (Help → Check for Updates…). Read it before you run it: it's short.
set -eu

REPO="viktorfroberg/Dialup"
BASE="https://github.com/$REPO/releases/latest/download"
DEST="/Applications/Dialup.app"

say() { printf '%s\n' "$*"; }
fail() { say "Dialup installer: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Dialup runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
minor=$(sw_vers -productVersion | cut -d. -f2)
if [ "$major" -lt 15 ] || { [ "$major" -eq 15 ] && [ "$minor" -lt 4 ]; }; then
  fail "Dialup needs macOS 15.4 or later (this Mac has $(sw_vers -productVersion))."
fi

if [ -e "$DEST" ]; then
  say "Dialup is already installed. Open it and choose Check for Updates… to get the newest version."
  say "(To reinstall, move ${DEST} to the Trash first.)"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Downloading Dialup…"
curl -fsSL -o "$tmp/Dialup.zip" "$BASE/Dialup.zip" || fail "couldn't download $BASE/Dialup.zip"
curl -fsSL -o "$tmp/Dialup.zip.sha256" "$BASE/Dialup.zip.sha256" || fail "couldn't download the checksum"

expected=$(awk '{print $1}' "$tmp/Dialup.zip.sha256")
actual=$(shasum -a 256 "$tmp/Dialup.zip" | awk '{print $1}')
[ "$expected" = "$actual" ] || fail "the download is damaged (checksum mismatch). Try again."

ditto -x -k "$tmp/Dialup.zip" "$tmp/unzipped"
[ -d "$tmp/unzipped/Dialup.app" ] || fail "the download doesn't contain Dialup.app"
codesign --verify --deep --strict "$tmp/unzipped/Dialup.app" 2>/dev/null || fail "Dialup.app's signature doesn't check out"

say "Installing to ${DEST}…"
ditto "$tmp/unzipped/Dialup.app" "$DEST" || fail "couldn't copy to /Applications (is it writable for you?)"

say "Done! Opening Dialup."
open "$DEST"

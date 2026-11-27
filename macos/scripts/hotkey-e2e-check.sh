#!/bin/bash
# End-to-end check of the running app: starts a debug build of Baddel, brings
# a throwaway TextEdit document to the front, posts the real shortcut
# (Option-Shift-Space, the default) and checks the document afterwards.
# Corrections switch the active keyboard layout; the layout that was active
# before the run is selected again at the end.
#
# Needs Accessibility access for the terminal running it (Baddel started from
# here inherits it). It never requests or grants access. It takes over the
# keyboard focus for a few seconds, and refuses to run if TextEdit or Baddel
# is already open.
set -u
cd "$(dirname "$0")/.."
swift build >/dev/null || exit 1
CHECK=.build/debug/baddel-axcheck

if pgrep -x TextEdit >/dev/null || pgrep -x Baddel >/dev/null; then
  echo "TextEdit or Baddel is already running; close them first. Skipping."
  exit 2
fi

WORK=$(mktemp -d)
PREVIOUS=$("$CHECK" --frontmost)
source_id() { "$CHECK" --sources | sed -n 's/^currentSource=//p'; }
ORIGINAL_SOURCE=$(source_id)
.build/debug/Baddel &
BADDEL=$!
cleanup() {
  pkill -x TextEdit 2>/dev/null
  kill "$BADDEL" 2>/dev/null
  rm -rf "$WORK"
  "$CHECK" --restore-source "$ORIGINAL_SOURCE" >/dev/null
  [ "$PREVIOUS" != "-" ] && open -b "$PREVIOUS" 2>/dev/null
}
trap cleanup EXIT
sleep 1
failures=0
echo "layout before: $ORIGINAL_SOURCE"

run_case() {  # name initial expected caret presses gap-ms [undo-range]
  printf '%s' "$2" > "$WORK/initial.txt"
  printf '%s' "$3" > "$WORK/expected.txt"
  cp "$WORK/initial.txt" "$WORK/doc.txt"
  open -F -a TextEdit "$WORK/doc.txt"
  local pid=""
  for _ in $(seq 1 50); do pid=$(pgrep -x TextEdit) && break; sleep 0.1; done
  sleep 1.5
  echo "== $1"
  "$CHECK" --pid "$pid" --initial "$WORK/initial.txt" --select-only --caret "$4" || { failures=$((failures + 1)); pkill -x TextEdit; return; }
  "$CHECK" --press "$5" --gap-ms "$6"
  sleep 1
  "$CHECK" --pid "$pid" --expected "$WORK/expected.txt" --compare-only || failures=$((failures + 1))
  echo "layout after correction: $(source_id)"
  if [ -n "${7:-}" ]; then
    # Click the Undo panel with the mouse; the original text must come back
    # and TextEdit must stay the frontmost app.
    "$CHECK" --click-undo --pid "$pid" --near-range "$7" || failures=$((failures + 1))
    sleep 0.5
    echo "after undo:"
    "$CHECK" --pid "$pid" --expected "$WORK/initial.txt" --compare-only || failures=$((failures + 1))
    echo "layout after undo: $(source_id)"
  fi
  pkill -x TextEdit
  for _ in $(seq 1 50); do pgrep -x TextEdit >/dev/null || break; sleep 0.1; done
}

run_case "one press fixes only the last word" 'hgsghl ugd;l' 'hgsghl عليكم' 12 1 0
run_case "two presses 120 ms apart fix the whole field once" 'hgsghl ugd;l' 'السلام عليكم' 12 2 120

run_case "one press, then a mouse click on Undo restores the text" 'hgsghl ugd;l' 'hgsghl عليكم' 12 1 0 7,5
run_case "Arabic typed instead of English: layout switches, Undo switches it back" 'اثممخ' 'hello' 5 1 0 0,5

# Manual Arabic layout selection: restart the app with the Arabic layout
# setting overridden to Arabic - PC for this run only (your saved settings are
# not changed). `v` is `ر` on Arabic - PC and `د` on the macOS Arabic layout.
kill "$BADDEL" 2>/dev/null; wait "$BADDEL" 2>/dev/null
.build/debug/Baddel -arabicLayoutID arabic-pc &
BADDEL=$!
sleep 1
run_case "Arabic layout set to Arabic - PC in Settings" 'lvpfh' 'مرحبا' 5 1 0
kill "$BADDEL" 2>/dev/null; wait "$BADDEL" 2>/dev/null
.build/debug/Baddel -arabicLayoutID arabic-mac &
BADDEL=$!
sleep 1
run_case "Arabic layout set to Arabic (macOS) in Settings" 'lvpfh' 'مدحبا' 5 1 0

# Manual English layout selection, overridden for this run only. Shift-3 is a
# pound sign on the British layout and is not on the US layout at all, so the
# US table leaves it alone and the British table converts it by its key.
kill "$BADDEL" 2>/dev/null; wait "$BADDEL" 2>/dev/null
.build/debug/Baddel -englishLayoutID uk-english-mac -arabicLayoutID arabic-mac &
BADDEL=$!
sleep 1
run_case "English layout set to British in Settings" 'ugd;l£' 'عليكم#' 6 1 0
kill "$BADDEL" 2>/dev/null; wait "$BADDEL" 2>/dev/null
.build/debug/Baddel -englishLayoutID us-english -arabicLayoutID arabic-mac &
BADDEL=$!
sleep 1
run_case "English layout set to US in Settings" 'ugd;l£' 'عليكم£' 6 1 0

echo
if [ "$failures" -eq 0 ]; then echo "All hot key checks passed."; else echo "$failures check(s) failed."; exit 1; fi

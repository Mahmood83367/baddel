#!/bin/bash
# Checks that a correction leaves exactly the expected text in real desktop
# text fields: every byte, nothing added, and that Undo restores the original
# byte for byte. Fields: GTK 3 and GTK 4 entry and text view, Qt 5 line edit,
# plain text edit and rich text edit, all driven through the accessibility bus (AT-SPI)
# the way the running app does it.
#
#   linux/scripts/text-fidelity-check.sh <path to the baddel binary>
#
# Run it in an X11 session with a session D-Bus, or:
#   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" linux/scripts/text-fidelity-check.sh <baddel>
# With BADDEL_FIDELITY_SESSION=wayland it expects to be started inside a Wayland
# session and only uses the trigger command, never a key grab.
# Only fixture text is used; a mismatch is printed as code points.
set -u
BADDEL=$(realpath "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
LOG="$WORK/baddel.log"
RESULTS="${RESULTS_FILE:-$WORK/results.txt}"
SESSION="${BADDEL_FIDELITY_SESSION:-x11}"
failures=0
: > "$RESULTS"
say() { echo "$1" | tee -a "$RESULTS"; }

if [ "$SESSION" = "x11" ]; then
  openbox >/dev/null 2>&1 &
  sleep 1
  setxkbmap -layout us,ara
fi
export GTK_MODULES=gail:atk-bridge NO_AT_BRIDGE=0 GTK_A11Y=atspi QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 QT_ACCESSIBILITY=1
gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null || true
export BADDEL_SETTINGS_DIR="$WORK/settings"
mkdir -p "$BADDEL_SETTINGS_DIR"
# The layout is left alone, so every case starts from the same state.
printf '{ "SwitchLayout": false }' > "$BADDEL_SETTINGS_DIR/settings.json"

"$BADDEL" >> "$LOG" 2>&1 &
BADDEL_PID=$!
for _ in $(seq 1 50); do grep -q "status=" "$LOG" && break; sleep 0.1; done
say "session=$SESSION $(head -1 "$LOG" | cut -d' ' -f1-4)"
cleanup() { "$BADDEL" --quit 2>/dev/null; kill "$BADDEL_PID" 2>/dev/null; pkill -f fixture_field.py 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# Compares two files byte for byte; on a difference says where and with what, as code points.
compare() {  # label actual expected
  python3 - "$1" "$2" "$3" <<'PY'
import sys
label, actual_path, expected_path = sys.argv[1:4]
try:
    actual = open(actual_path, "rb").read()
except OSError:
    print(f"FAIL {label} [the field reported no text]"); sys.exit(1)
expected = open(expected_path, "rb").read()
if actual == expected:
    print(f"PASS {label} [{len(expected)} bytes]"); sys.exit(0)
a, e = actual.decode("utf-8", "replace"), expected.decode("utf-8", "replace")
same = 0
while same < min(len(a), len(e)) and a[same] == e[same]:
    same += 1
points = lambda s: " ".join(f"U+{ord(c):04X}" for c in s[:10]) + (" …" if len(s) > 10 else "")
print(f"FAIL {label} [expected {len(expected)} bytes, field has {len(actual)}; first {same} characters match; "
      f"field then has: {points(a[same:]) or 'nothing'}; expected then: {points(e[same:]) or 'nothing'}; "
      f"replacement characters in field: {a.count(chr(0xFFFD))}]")
sys.exit(1)
PY
}

run_case() {  # name toolkit widget input presses
  local name=$1 toolkit=$2 widget=$3 input=$4 presses=$5 mode=line
  [ "$presses" = "1" ] && mode=word
  pkill -f fixture_field.py 2>/dev/null; sleep 0.3
  printf '%s' "$input" > "$WORK/in.txt"; rm -f "$WORK/out.txt"
  # What the correction engine itself says the result is; the field must hold exactly that.
  "$BADDEL" --fix-text --mode "$mode" --hint none < "$WORK/in.txt" > "$WORK/answer.txt"
  if ! head -1 "$WORK/answer.txt" | grep -q '^ok '; then say "FAIL $toolkit $widget: $name [no expected text: $(head -1 "$WORK/answer.txt")]"; failures=$((failures + 1)); return; fi
  tail -n +2 "$WORK/answer.txt" > "$WORK/expected.txt"
  python3 "$HERE/fixture_field.py" "$toolkit" "$widget" "$WORK/in.txt" "$WORK/out.txt" >/dev/null 2>&1 &
  for _ in $(seq 1 100); do [ -f "$WORK/out.txt" ] && break; sleep 0.1; done
  sleep 0.6
  if ! cmp -s "$WORK/out.txt" "$WORK/in.txt"; then
    say "$(compare "$toolkit $widget: $name: the field holds the fixture before the correction" "$WORK/out.txt" "$WORK/in.txt")"; failures=$((failures + 1)); return
  fi
  local before; before=$(wc -l < "$LOG")
  for i in $(seq 1 "$presses"); do [ "$i" -gt 1 ] && sleep 0.12; "$BADDEL" --trigger; done
  sleep 1.4
  local event; event=$(tail -n +$((before + 1)) "$LOG" | tail -1 | cut -d' ' -f1-4)
  local line; line=$(compare "$toolkit $widget: $name" "$WORK/out.txt" "$WORK/expected.txt") || failures=$((failures + 1))
  say "$line {$event}"
  # On a refusal, record once per kind of field what the accessibility bus shows.
  if echo "$event" | grep -q Rejected && [ ! -f "$WORK/reported-$toolkit-$widget" ]; then
    touch "$WORK/reported-$toolkit-$widget"
    say "  log: $(tail -n +$((before + 1)) "$LOG" | tail -1 | cut -c1-300)"
    "$BADDEL" --focus-report | sed 's/^/  report: /' | tee -a "$RESULTS"
  fi
  "$BADDEL" --undo; sleep 0.9
  line=$(compare "$toolkit $widget: $name: Undo restores every byte" "$WORK/out.txt" "$WORK/in.txt") || failures=$((failures + 1))
  say "$line"
}

RLM=$(printf '\xe2\x80\x8f')
ACUTE=$(printf '\xcc\x81')
available() {  # toolkit
  case "$1" in
    gtk3) python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" 2>/dev/null ;;
    gtk4) python3 -c "import gi; gi.require_version('Gtk', '4.0'); from gi.repository import Gtk" 2>/dev/null ;;
    *) python3 -c "import PyQt5.QtWidgets" 2>/dev/null ;;
  esac
}
# Whether an application of this kind shows up on the accessibility bus here at all.
visible() {  # toolkit widget
  pkill -f fixture_field.py 2>/dev/null; sleep 0.3
  printf 'x' > "$WORK/in.txt"; rm -f "$WORK/out.txt"
  python3 "$HERE/fixture_field.py" "$1" "$2" "$WORK/in.txt" "$WORK/out.txt" >/dev/null 2>&1 &
  for _ in $(seq 1 100); do [ -f "$WORK/out.txt" ] && break; sleep 0.1; done
  sleep 1
  "$BADDEL" --focus-report > "$WORK/report.txt"
  grep -q "focused role=" "$WORK/report.txt"
}
for target in "gtk3 entry" "gtk3 textview" "gtk4 entry" "gtk4 textview" "qt5 lineedit" "qt5 plaintextedit" "qt5 textedit"; do
  set -- $target
  available "$1" || { say "SKIP $target: toolkit bindings not installed"; continue; }
  if ! visible "$1" "$2"; then
    say "SKIP $target: the application does not appear on the accessibility bus in this session [$(tr '\n' ' ' < "$WORK/report.txt" | cut -c1-200)]"
    continue
  fi
  say "== $target: $(grep 'focused role=' "$WORK/report.txt" | head -1 | sed 's/^ *//')"
  run_case "the reported phrase, whole field" "$1" "$2" 'hndv hnmp' 2
  run_case "the reported phrase, last word" "$1" "$2" 'hndv hnmp' 1
  run_case "a second phrase, whole field" "$1" "$2" 'hgsghl ugd;l' 2
  run_case "Arabic typed for English, with Arabic punctuation and digits" "$1" "$2" 'اثممخ، صخقمي؟ ١٢٣' 2
  run_case "a right-to-left mark inside the text" "$1" "$2" "ugd;l${RLM} hgsghl" 2
  run_case "emoji and a skin-tone sequence around the text" "$1" "$2" '😀 ugd;l 👍🏽' 2
  run_case "last word after an emoji" "$1" "$2" '😀👍🏽 ugd;l' 1
  run_case "a combining mark" "$1" "$2" "cafe${ACUTE} ugd;l" 2
  case "$2" in textview|plaintextedit|textedit)
    run_case "three lines, whole field" "$1" "$2" "$(printf 'ugd;l\nhgsghl\nhndv hnmp')" 2
    run_case "last word on the last of three lines" "$1" "$2" "$(printf 'ugd;l\nhgsghl\nhndv hnmp')" 1 ;;
  esac
done

# Failed writes. "dropping": the application deletes and then refuses the
# insertion; the deleted text must be back, byte for byte. "concurrent": new text
# lands while the correction is being verified; the correction must be reported
# as failed and the field left exactly as it then is, the new text included.
failing_case() {  # kind presses expected-file reason label
  pkill -f fixture_field.py 2>/dev/null; sleep 0.3
  printf 'hndv hnmp' > "$WORK/in.txt"; rm -f "$WORK/out.txt"
  python3 "$HERE/fixture_field.py" gtk3 "$1" "$WORK/in.txt" "$WORK/out.txt" >/dev/null 2>&1 &
  for _ in $(seq 1 100); do [ -f "$WORK/out.txt" ] && break; sleep 0.1; done
  sleep 0.6
  local before; before=$(wc -l < "$LOG")
  for i in $(seq 1 "$2"); do [ "$i" -gt 1 ] && sleep 0.12; "$BADDEL" --trigger; done
  sleep 2.5
  local event; event=$(tail -n +$((before + 1)) "$LOG" | tail -1 | cut -d' ' -f1-3)
  local line; line=$(compare "$5 ($2 press)" "$WORK/out.txt" "$3") || failures=$((failures + 1))
  say "$line {$event}"
  if echo "$event" | grep -q "event=Rejected .*reason=$4"; then say "PASS $1 ($2 press): reported as $4"
  else say "FAIL $1 ($2 press): reported as $4 {$event}"; failures=$((failures + 1)); fi
}
if available gtk3; then
  for presses in 2 1; do
    mode=line; [ "$presses" = 1 ] && mode=word
    printf 'hndv hnmp' > "$WORK/original.txt"
    printf 'hndv hnmp' | "$BADDEL" --fix-text --mode "$mode" --hint none | tail -n +2 > "$WORK/corrected.txt"
    { cat "$WORK/corrected.txt"; printf ' new'; } > "$WORK/corrected-and-new.txt"
    failing_case dropping-entry "$presses" "$WORK/original.txt" WriteFailed "an insertion that never arrives: the deleted text is put back"
    failing_case concurrent-entry "$presses" "$WORK/corrected-and-new.txt" VerificationFailed "an edit during verification: nothing is deleted, the new text stays"
  done
fi

say "RESULT $([ "$failures" -eq 0 ] && echo pass || echo "fail ($failures)")"
exit "$failures"

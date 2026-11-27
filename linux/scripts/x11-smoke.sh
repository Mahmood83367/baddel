#!/bin/bash
# Smoke test of the Linux prototype in an X11 session: starts Baddel, opens a
# throwaway GTK window with fixture text, presses the real shortcut (through
# XTEST) or sends the trigger, and compares the field's text afterwards.
#
#   linux/scripts/x11-smoke.sh <path to the baddel binary>
#
# It needs an X11 session with a session D-Bus and AT-SPI. Without one, run:
#   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" linux/scripts/x11-smoke.sh <baddel>
# in which case it also starts a window manager and configures two XKB groups.
# It writes only outcome codes; fixture text is never printed.
set -u
BADDEL=$(realpath "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
LOG="$WORK/baddel.log"
RESULTS="${RESULTS_FILE:-$WORK/results.txt}"
failures=0
: > "$RESULTS"

say() { echo "$1" | tee -a "$RESULTS"; }
check() { if [ "$2" = "true" ]; then say "PASS $1${3:+ [$3]}"; else say "FAIL $1${3:+ [$3]}"; failures=$((failures + 1)); fi; }

if [ "${BADDEL_SMOKE_SETUP:-1}" = "1" ]; then
  # A window manager, so the fixture window becomes active and focused.
  openbox >/dev/null 2>&1 &
  sleep 1
  setxkbmap -layout us,ara
  export GTK_MODULES=gail:atk-bridge NO_AT_BRIDGE=0 GTK_A11Y=atspi
  gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null || true
fi
export BADDEL_SETTINGS_DIR="$WORK/settings"
mkdir -p "$BADDEL_SETTINGS_DIR"

say "session=${XDG_SESSION_TYPE:-x11-or-unset} display=${DISPLAY:-none} xkb=$(setxkbmap -query | awk '/layout/{print $2}')"
"$BADDEL" --self-check | sed 's/^/selfcheck /' | tee -a "$RESULTS"

BADDEL_PID=""
FALLBACK_DIR="/tmp/baddel-$(id -u)"
stop_app() {  # optional env prefix words
  [ -n "$BADDEL_PID" ] || return 0
  "$@" "$BADDEL" --quit 2>/dev/null; sleep 0.3
  kill "$BADDEL_PID" 2>/dev/null; wait "$BADDEL_PID" 2>/dev/null; BADDEL_PID=""
}
start_app() {  # optional env prefix words, e.g. env -u XDG_RUNTIME_DIR
  : > "$LOG"
  "$@" "$BADDEL" >> "$LOG" 2>&1 &
  BADDEL_PID=$!
  for _ in $(seq 1 50); do grep -q "status=" "$LOG" && break; sleep 0.1; done
  say "$(head -1 "$LOG")"
}
cleanup() { stop_app; pkill -f fixture_entry.py 2>/dev/null; rm -rf "$WORK"; [ -L "$FALLBACK_DIR" ] && rm -f "$FALLBACK_DIR"; rm -rf "$FALLBACK_DIR" 2>/dev/null; }
trap cleanup EXIT
start_app
check "app is running with an X11 key grab" "$(grep -q 'status=ready session=x11 shortcut=x11-grab' "$LOG" && echo true || echo false)"

group() { "$BADDEL" --xkb-group; }
log_lines() { wc -l < "$LOG"; }
matches() { [ "$(cat "$WORK/out.txt" 2>/dev/null)" = "$1" ] && echo true || echo false; }

start_fixture() {  # kind initial caret [selection]
  pkill -f fixture_entry.py 2>/dev/null; sleep 0.3
  printf '%s' "$2" > "$WORK/in.txt"; rm -f "$WORK/out.txt"
  python3 "$HERE/fixture_entry.py" "$1" "$WORK/in.txt" "$WORK/out.txt" "$3" ${4:+"$4"} >/dev/null 2>&1 &
  for _ in $(seq 1 80); do [ -f "$WORK/out.txt" ] && break; sleep 0.1; done
  sleep 0.6
}

press() {  # how count
  for i in $(seq 1 "$2"); do
    [ "$i" -gt 1 ] && sleep 0.12
    if [ "$1" = "key" ]; then xdotool key ctrl+alt+space; else "$BADDEL" --trigger; fi
  done
  sleep 1.3
}

# name kind initial expected caret how count [selection]
case_fix() {
  start_fixture "$2" "$3" "$5" "${8:-}"
  local before; before=$(log_lines)
  press "$6" "$7"
  local event; event=$(tail -n +$((before + 1)) "$LOG" | tail -1 | cut -d' ' -f1-3)
  check "$1" "$(matches "$4")" "$event"
}

case_fix "one press fixes only the last word (key grab)" plain 'hgsghl ugd;l' 'hgsghl عليكم' 12 key 1
case_fix "two presses 120 ms apart fix the whole field once (key grab)" plain 'hgsghl ugd;l' 'السلام عليكم' 12 key 2
case_fix "exact selection only" plain 'say ugd;l now' 'say عليكم now' 0 key 1 4,9
case_fix "character offsets after an emoji" plain '😀 ugd;l' '😀 عليكم' 7 key 1
case_fix "one trigger fixes the last word (desktop-bound shortcut path)" plain 'hgsghl ugd;l' 'hgsghl عليكم' 12 trigger 1
case_fix "two triggers fix the whole field (desktop-bound shortcut path)" plain 'hgsghl ugd;l' 'السلام عليكم' 12 trigger 2
case_fix "password field is left untouched" password 'ugd;l' 'ugd;l' 5 key 2
check "password field was refused as secure" "$(tail -1 "$LOG" | grep -q 'reason=SecureField' && echo true || echo false)"
case_fix "read-only field is left untouched" readonly 'ugd;l' 'ugd;l' 5 key 2
check "read-only field was refused as unsupported" "$(tail -1 "$LOG" | grep -q 'reason=UnsupportedField' && echo true || echo false)"
case_fix "nothing before the caret: nothing changes" plain '   ' '   ' 3 key 1

# Layout switching and Undo by clicking the popup.
"$BADDEL" --xkb-group 1 >/dev/null
start_fixture plain 'اثممخ' 5
press key 1
check "Arabic typed as English is fixed" "$(matches 'hello')" "$(tail -1 "$LOG" | cut -d' ' -f1,4)"
check "layout switched from Arabic to English" "$([ "$(group)" = "0" ] && echo true || echo false)" "group=$(group)"
POPUP=$(xdotool search --name '^Baddel Undo$' 2>/dev/null | head -1)
if [ -n "$POPUP" ] && xdotool getwindowgeometry --shell "$POPUP" > "$WORK/geometry" 2>/dev/null; then
  . "$WORK/geometry"
  check "Undo popup is on screen" true "x=$X y=$Y"
  xdotool mousemove $((X + 20)) $((Y + 12)) click 1
  sleep 1
  check "clicking Undo restores the text" "$(matches 'اثممخ')" "$(tail -1 "$LOG" | cut -d' ' -f1)"
  check "clicking Undo restores the Arabic layout" "$([ "$(group)" = "1" ] && echo true || echo false)" "group=$(group)"
  check "the field keeps keyboard focus after the click" "$([ "$(xdotool getwindowfocus getwindowname 2>/dev/null)" = "Baddel Check Host" ] && echo true || echo false)"
else
  check "Undo popup is on screen" false "popup-not-found"
fi

# The other direction, undone with the command instead of the popup.
"$BADDEL" --xkb-group 0 >/dev/null
start_fixture plain 'ugd;l' 5
press key 1
check "English typed as Arabic is fixed" "$(matches 'عليكم')"
check "layout switched from English to Arabic" "$([ "$(group)" = "1" ] && echo true || echo false)" "group=$(group)"
"$BADDEL" --undo; sleep 1
check "baddel --undo restores the text" "$(matches 'ugd;l')"
check "baddel --undo restores the English layout" "$([ "$(group)" = "0" ] && echo true || echo false)" "group=$(group)"

# Undo is refused once the text has changed.
start_fixture plain 'ugd;l' 5
press key 1
xdotool type --delay 30 'x'; sleep 0.5
"$BADDEL" --undo; sleep 0.8
check "Undo is refused after the text was edited" "$(tail -1 "$LOG" | grep -q 'event=UndoRejected' && echo true || echo false)" "$(tail -1 "$LOG")"

# ---- Manual variants, and switching to the exact variant --------------------
say "-- layout variants --"
stop_app
BASIC=$("$BADDEL" --dump-layout ara | grep '^Digit1|' | cut -d'|' -f2)
DIGITS=$("$BADDEL" --dump-layout ara digits | grep '^Digit1|' | cut -d'|' -f2)
check "ara and ara(digits) are read as separate tables" "$("$BADDEL" --dump-layout ara digits | head -1 | grep -q 'xkb-ara-digits' && echo true || echo false)" "digit1Differs=$([ "$BASIC" != "$DIGITS" ] && echo true || echo false)"

# Two Arabic groups in the session; the settings ask for the second one's variant.
setxkbmap -layout us,ara,ara -variant ,,digits
printf '{ "ArabicXkbVariant": "digits" }' > "$BADDEL_SETTINGS_DIR/settings.json"
start_app
check "configured Arabic variant is loaded" "$(grep -q 'layouts=xkb-us,xkb-ara-digits .*xkbGroups=us|ara|ara(digits)' "$LOG" && echo true || echo false)"
"$BADDEL" --xkb-group 0 >/dev/null
case_fix "conversion uses the configured variant's table" plain 'ugd;l 1' "عليكم $DIGITS" 7 key 2
check "layout switches to the exact variant's group, not the first Arabic group" "$([ "$(group)" = "2" ] && echo true || echo false)" "group=$(group)"
"$BADDEL" --undo; sleep 0.8
check "Undo returns to the English group" "$([ "$(group)" = "0" ] && echo true || echo false)" "group=$(group)"

# A configured variant that is not one of the session's groups: text is fixed, layout is left alone.
stop_app
setxkbmap -layout us,ara
start_app
"$BADDEL" --xkb-group 0 >/dev/null
case_fix "variant missing from the session: text is still fixed" plain 'ugd;l' 'عليكم' 5 key 1
check "variant missing from the session: layout is not switched to another Arabic group" "$([ "$(group)" = "0" ] && tail -1 "$LOG" | grep -q 'layoutSwitched=False' && echo true || echo false)" "group=$(group)"

# No variant configured: the session's own variant is used.
stop_app
rm -f "$BADDEL_SETTINGS_DIR/settings.json"
setxkbmap -layout us,ara -variant ,digits
start_app
check "unset variant follows the session (ara(digits))" "$(grep -q 'layouts=xkb-us,xkb-ara-digits ' "$LOG" && echo true || echo false)"
stop_app

# Manual Latin variant.
printf '{ "LatinXkbVariant": "dvorak", "ArabicXkbVariant": "" }' > "$BADDEL_SETTINGS_DIR/settings.json"
check "configured Latin variant is loaded" "$("$BADDEL" --self-check | grep -q 'latinLayout=xkb-us-dvorak arabicLayout=xkb-ara$' && echo true || echo false)"
rm -f "$BADDEL_SETTINGS_DIR/settings.json"
setxkbmap -layout us,ara

# ---- Trigger socket location -------------------------------------------------
say "-- trigger socket --"
NORMAL=$("$BADDEL" --socket-path --create)
check "socket is in the private runtime directory when there is one" "$([ -n "${XDG_RUNTIME_DIR:-}" ] && [ "$NORMAL" = "$XDG_RUNTIME_DIR/baddel.sock" ] && echo true || echo false)" "runtimeDirSet=$([ -n "${XDG_RUNTIME_DIR:-}" ] && echo true || echo false)"

rm -rf "$FALLBACK_DIR"
FALLBACK=$(env -u XDG_RUNTIME_DIR "$BADDEL" --socket-path --create)
check "without a runtime directory the per-user fallback is used" "$([ "$FALLBACK" = "$FALLBACK_DIR/baddel.sock" ] && echo true || echo false)"
check "the fallback directory is a real directory with mode 700" "$([ -d "$FALLBACK_DIR" ] && [ ! -L "$FALLBACK_DIR" ] && [ "$(stat -c %a "$FALLBACK_DIR")" = "700" ] && echo true || echo false)" "mode=$(stat -c %a "$FALLBACK_DIR" 2>/dev/null)"

start_app env -u XDG_RUNTIME_DIR
start_fixture plain 'hgsghl ugd;l' 12
env -u XDG_RUNTIME_DIR "$BADDEL" --trigger; sleep 1.3
check "trigger works through the fallback socket" "$(matches 'hgsghl عليكم')" "socketMode=$(stat -c %a "$FALLBACK_DIR/baddel.sock" 2>/dev/null)"
stop_app env -u XDG_RUNTIME_DIR

# A runtime directory that others can enter is not trusted.
mkdir -p "$WORK/open-runtime"; chmod 755 "$WORK/open-runtime"
check "a non-private XDG_RUNTIME_DIR is not used" "$([ "$(XDG_RUNTIME_DIR="$WORK/open-runtime" "$BADDEL" --socket-path --create)" = "$FALLBACK_DIR/baddel.sock" ] && echo true || echo false)"

# The fallback path occupied by a world-writable directory: refused.
rm -rf "$FALLBACK_DIR"; mkdir "$FALLBACK_DIR"; chmod 777 "$FALLBACK_DIR"
check "a world-writable fallback directory is refused" "$(env -u XDG_RUNTIME_DIR "$BADDEL" --socket-path --create >/dev/null && echo false || echo true)"
: > "$LOG"; env -u XDG_RUNTIME_DIR "$BADDEL" >> "$LOG" 2>&1; CODE=$?
check "the app refuses to start a channel there" "$([ "$CODE" = "3" ] && grep -q 'reason=no-private-directory-for-the-trigger-socket' "$LOG" && echo true || echo false)" "exit=$CODE"
check "no socket was created in the refused directory" "$([ ! -e "$FALLBACK_DIR/baddel.sock" ] && echo true || echo false)"

# The fallback path replaced by a symbolic link to a private directory: refused.
rm -rf "$FALLBACK_DIR"; mkdir -m 700 "$WORK/elsewhere"; ln -s "$WORK/elsewhere" "$FALLBACK_DIR"
check "a symbolic link at the fallback path is refused" "$(env -u XDG_RUNTIME_DIR "$BADDEL" --socket-path --create >/dev/null && echo false || echo true)"
check "a client refuses to send through it" "$(env -u XDG_RUNTIME_DIR "$BADDEL" --trigger && echo false || echo true)"
check "nothing was created behind the link" "$([ -z "$(ls -A "$WORK/elsewhere")" ] && echo true || echo false)"
rm -f "$FALLBACK_DIR"

echo "--- app log (codes only) ---"; cat "$LOG"
if [ "$failures" -eq 0 ]; then say "RESULT all checks passed"; else say "RESULT $failures check(s) failed"; fi
[ "$failures" -eq 0 ]

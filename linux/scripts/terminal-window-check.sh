#!/bin/bash
# Checks Baddel's one shortcut in real terminal windows on X11: the running
# Baddel app holds the shortcut as a key grab, releases it while a terminal
# window has the focus, and the Bash integration in that window corrects the
# command line. Keys are pressed through XTEST with an English and an Arabic
# XKB layout active.
#
#   linux/scripts/terminal-window-check.sh <path to the unpacked package folder> [terminal ...]
#
# Terminals default to: xterm xfce4-terminal gnome-terminal. xterm is started with
# metaSendsEscape, which it needs to send Alt combinations as Escape sequences;
# what stock xterm does instead is recorded as a note. Needs an X11 session with a session
# D-Bus, xdotool, openbox and the terminals. Without a session, run:
#   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" linux/scripts/terminal-window-check.sh <folder>
# Everything runs with throwaway settings and start-up files; only fixture text
# is typed, and Enter is never pressed on it.
set -u
PACKAGE=$(realpath "$1"); shift
BADDEL="$PACKAGE/baddel"
SCRIPT="$PACKAGE/shell/baddel.bash"
[ $# -gt 0 ] || set -- xterm xfce4-terminal gnome-terminal
WORK=$(mktemp -d)
RESULTS="${RESULTS_FILE:-$WORK/results.txt}"
failures=0
: > "$RESULTS"
say() { echo "$1" | tee -a "$RESULTS"; }
check() { if [ "$2" = "$3" ]; then say "PASS $1"; else say "FAIL $1 [expected: $3] [actual: $2]"; failures=$((failures + 1)); fi; }

openbox >/dev/null 2>&1 &
sleep 1
setxkbmap -layout us,ara
export BADDEL_SETTINGS_DIR="$WORK/settings"
mkdir -p "$BADDEL_SETTINGS_DIR"

cat > "$WORK/rc" <<RC
PS1='ready> '
unset HISTFILE
bind 'set enable-bracketed-paste off' 2>/dev/null
BADDEL_BIN='$BADDEL'
source '$SCRIPT'
PROMPT_COMMAND='echo p >> "$WORK/prompts"'
_check_dump() { printf '%s' "\$READLINE_LINE" > "$WORK/buffer.tmp"; mv "$WORK/buffer.tmp" "$WORK/buffer"; }
bind -x '"\\C-x\\C-d": _check_dump'
touch "$WORK/shell-ready"
RC

LOG="$WORK/baddel.log"
BADDEL_PID=""
start_app() {
  : > "$LOG"
  "$BADDEL" >> "$LOG" 2>&1 &
  BADDEL_PID=$!
  for _ in $(seq 1 50); do grep -q "status=" "$LOG" && break; sleep 0.1; done
}
stop_app() { [ -n "$BADDEL_PID" ] && { "$BADDEL" --quit 2>/dev/null; sleep 0.3; kill "$BADDEL_PID" 2>/dev/null; wait "$BADDEL_PID" 2>/dev/null; BADDEL_PID=""; }; }
TERMINAL_PID=""
cleanup() { stop_app; [ -n "$TERMINAL_PID" ] && kill "$TERMINAL_PID" 2>/dev/null; pkill -f "rcfile $WORK/rc" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

buffer() {  # prints the command line the shell is holding, read through a test-only key binding
  rm -f "$WORK/buffer"
  xdotool key --clearmodifiers ctrl+x ctrl+d
  for _ in $(seq 1 30); do [ -f "$WORK/buffer" ] && break; sleep 0.1; done
  cat "$WORK/buffer" 2>/dev/null
}
clear_line() { xdotool key --clearmodifiers ctrl+e ctrl+u; sleep 0.2; }
shortcut() {  # count
  for i in $(seq 1 "$1"); do [ "$i" -gt 1 ] && sleep 0.05; xdotool key ctrl+alt+space; done
  sleep 1.2
}
layout() { "$BADDEL" --xkb-group "$1" >/dev/null; sleep 0.3; }   # 0 = us, 1 = ara
# Raw key codes through XTEST, so the active layout alone decides what is typed,
# exactly as on a keyboard. (xdotool picks a layout itself and switches to it.)
# "+N" holds key code N down, "-N" releases it, "N" presses and releases it.
cat > "$WORK/keys.py" <<'PY'
import sys, time
from Xlib import X, display
from Xlib.ext import xtest
d = display.Display()
for word in sys.argv[1:]:
    code = int(word.lstrip("+-"))
    if not word.startswith("-"):
        xtest.fake_input(d, X.KeyPress, code)
    if not word.startswith("+"):
        xtest.fake_input(d, X.KeyRelease, code)
    d.sync()
    time.sleep(0.025)
PY
raw_keys() { python3 "$WORK/keys.py" "$@"; }
# The shortcut by key code (Control_L, Alt_L, space), for use while the Arabic
# layout is active.
shortcut_keys() {  # count
  for i in $(seq 1 "$1"); do
    [ "$i" -gt 1 ] && sleep 0.05
    raw_keys +37 +64 65 -64 -37
  done
  sleep 1.2
}
# Types text as the physical keys of a US keyboard, whatever layout is active.
press_keys() {
  local text=$1 i char codes=""
  for ((i = 0; i < ${#text}; i++)); do
    char=${text:i:1}
    case "$char" in
      q) codes+=" 24" ;; w) codes+=" 25" ;; e) codes+=" 26" ;; r) codes+=" 27" ;; t) codes+=" 28" ;; y) codes+=" 29" ;;
      u) codes+=" 30" ;; i) codes+=" 31" ;; o) codes+=" 32" ;; p) codes+=" 33" ;; a) codes+=" 38" ;; s) codes+=" 39" ;;
      d) codes+=" 40" ;; f) codes+=" 41" ;; g) codes+=" 42" ;; h) codes+=" 43" ;; j) codes+=" 44" ;; k) codes+=" 45" ;;
      l) codes+=" 46" ;; ';') codes+=" 47" ;; z) codes+=" 52" ;; x) codes+=" 53" ;; c) codes+=" 54" ;; v) codes+=" 55" ;;
      b) codes+=" 56" ;; n) codes+=" 57" ;; m) codes+=" 58" ;; ' ') codes+=" 65" ;;
    esac
  done
  # shellcheck disable=SC2086
  raw_keys $codes
  sleep 0.3
}

say "session display=${DISPLAY:-none} xkb=$(setxkbmap -query | awk '/layout/{print $2}')"
say "$("$BADDEL" --terminal-key status | head -1)"

for TERMINAL in "$@"; do
  command -v "${TERMINAL%-stock}" >/dev/null || { say "SKIP $TERMINAL is not installed"; continue; }
  rm -f "$WORK/shell-ready" "$WORK/prompts" "$BADDEL_SETTINGS_DIR/terminal-integration"
  case "$TERMINAL" in
    gnome-terminal)
      # Its server is normally started by the desktop session; start one for this check.
      SERVER=$(ls /usr/libexec/gnome-terminal-server /usr/lib/gnome-terminal/gnome-terminal-server 2>/dev/null | head -1)
      [ -n "$SERVER" ] && { "$SERVER" --app-id org.baddel.TerminalCheck >/dev/null 2>&1 & sleep 1.5; }
      gnome-terminal --app-id org.baddel.TerminalCheck -- bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 & ;;
    xterm) xterm -xrm 'XTerm*metaSendsEscape: true' -e bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 & ;;
    xterm-stock) xterm -e bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 & ;;
    *) "$TERMINAL" -e "bash --noprofile --rcfile $WORK/rc -i" >/dev/null 2>&1 & ;;
  esac
  TERMINAL_PID=$!
  for _ in $(seq 1 100); do [ -f "$WORK/shell-ready" ] && break; sleep 0.1; done
  if [ ! -f "$WORK/shell-ready" ]; then say "SKIP $TERMINAL did not start a shell here"; kill "$TERMINAL_PID" 2>/dev/null; continue; fi
  sleep 1
  WINDOW=$(xdotool getactivewindow 2>/dev/null)
  say "== $TERMINAL window class: $(xprop -id "$WINDOW" WM_CLASS 2>/dev/null | cut -d= -f2 | tr -d ' ')"
  check "$TERMINAL: loading the Bash integration left the marker automatic sharing waits for" \
    "$([ -f "$BADDEL_SETTINGS_DIR/terminal-integration" ] && echo yes || echo no)" yes

  # 1. Sharing off: the app keeps its key grab, so the terminal never sees the key.
  printf '{ "TerminalSharing": "off" }' > "$BADDEL_SETTINGS_DIR/settings.json"
  start_app
  layout 0; clear_line; xdotool type --delay 20 'echo ugd;l'; shortcut 1
  check "$TERMINAL: with sharing off the global shortcut is consumed before the terminal" "$(buffer)" 'echo ugd;l'
  stop_app

  # 2. Sharing automatic (the default): the grab is released while the terminal has the focus.
  rm -f "$BADDEL_SETTINGS_DIR/settings.json"
  start_app
  sleep 0.5
  layout 0; clear_line; xdotool type --delay 20 'echo ugd;l'; shortcut 1
  check "$TERMINAL: English layout, one press corrects the last word" "$(buffer)" 'echo عليكم'
  xdotool key --clearmodifiers ctrl+underscore; sleep 0.3
  check "$TERMINAL: Ctrl+_ restores it" "$(buffer)" 'echo ugd;l'
  clear_line; xdotool type --delay 20 'hgsghl ugd;l'; shortcut 2
  check "$TERMINAL: English layout, two presses correct the whole line" "$(buffer)" 'السلام عليكم'

  # The same physical keys with the Arabic layout active: what a user types
  # when the layout is wrong. The shortcut itself is pressed under that layout.
  # The buffer is read back with the English layout, because the check's own
  # read-back key is a Control combination.
  clear_line; layout 1; press_keys 'git status'; layout 0
  check "$TERMINAL: the Arabic layout really typed Arabic" "$(buffer)" 'لهف سفشفعس'
  layout 1; shortcut_keys 1; layout 0
  check "$TERMINAL: Arabic layout, one press corrects the last word" "$(buffer)" 'لهف status'
  clear_line; layout 1; press_keys 'git status'; shortcut_keys 2; layout 0
  check "$TERMINAL: Arabic layout, two presses correct the whole line" "$(buffer)" 'git status'
  clear_line
  check "$TERMINAL: no command line was run" "$(grep -c p "$WORK/prompts")" 1
  stop_app
  kill "$TERMINAL_PID" 2>/dev/null; pkill -f "rcfile $WORK/rc" 2>/dev/null; TERMINAL_PID=""
  sleep 0.5
done

# Stock xterm, for the record: it does not send Alt as an Escape prefix.
if command -v xterm >/dev/null; then
  rm -f "$WORK/shell-ready"
  xterm -e bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 &
  TERMINAL_PID=$!
  for _ in $(seq 1 100); do [ -f "$WORK/shell-ready" ] && break; sleep 0.1; done
  sleep 1
  start_app; sleep 0.5
  layout 0; clear_line; xdotool type --delay 20 'ugd;l'; shortcut 1
  say "NOTE xterm with stock settings: corrected=$([ "$(buffer)" = 'عليكم' ] && echo yes || echo 'no (it needs metaSendsEscape for Ctrl+Alt+Space to arrive as Escape, NUL)')"
  clear_line; stop_app; kill "$TERMINAL_PID" 2>/dev/null; pkill -f "rcfile $WORK/rc" 2>/dev/null; TERMINAL_PID=""
fi

say "RESULT $([ "$failures" -eq 0 ] && echo pass || echo "fail ($failures)")"
exit "$failures"

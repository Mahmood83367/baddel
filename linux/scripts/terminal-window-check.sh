#!/bin/bash
# Checks Baddel's one shortcut in real terminal windows on X11: the running
# Baddel app holds the shortcut as a key grab, releases it while a terminal
# window has the focus, and the Bash integration in that window corrects the
# command line. Keys are pressed through XTEST with an English and an Arabic
# XKB layout active.
#
#   linux/scripts/terminal-window-check.sh <path to the unpacked package folder> [terminal ...]
#
# Terminals default to: xterm gnome-terminal. Needs an X11 session with a session
# D-Bus, xdotool, openbox and the terminals. Without a session, run:
#   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" linux/scripts/terminal-window-check.sh <folder>
# Everything runs with throwaway settings and start-up files; only fixture text
# is typed, and Enter is never pressed on it.
set -u
PACKAGE=$(realpath "$1"); shift
BADDEL="$PACKAGE/baddel"
SCRIPT="$PACKAGE/shell/baddel.bash"
[ $# -gt 0 ] || set -- xterm gnome-terminal
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

say "session display=${DISPLAY:-none} xkb=$(setxkbmap -query | awk '/layout/{print $2}')"
say "$("$BADDEL" --terminal-key status | head -1)"

for TERMINAL in "$@"; do
  command -v "$TERMINAL" >/dev/null || { say "SKIP $TERMINAL is not installed"; continue; }
  rm -f "$WORK/shell-ready" "$WORK/prompts" "$BADDEL_SETTINGS_DIR/terminal-integration"
  case "$TERMINAL" in
    gnome-terminal) gnome-terminal --wait -- bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 & ;;
    *) "$TERMINAL" -e bash --noprofile --rcfile "$WORK/rc" -i >/dev/null 2>&1 & ;;
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
  layout 1; clear_line; xdotool type --delay 20 'git status'; sleep 0.3
  check "$TERMINAL: the Arabic layout really typed Arabic" "$(buffer)" 'لهف سفشفعس'
  shortcut 1
  check "$TERMINAL: Arabic layout, one press corrects the last word" "$(buffer)" 'لهف status'
  clear_line; xdotool type --delay 20 'git status'; shortcut 2
  check "$TERMINAL: Arabic layout, two presses correct the whole line" "$(buffer)" 'git status'
  layout 0; clear_line
  check "$TERMINAL: no command line was run" "$(grep -c p "$WORK/prompts")" 1
  stop_app
  kill "$TERMINAL_PID" 2>/dev/null; pkill -f "rcfile $WORK/rc" 2>/dev/null; TERMINAL_PID=""
  sleep 0.5
done

say "RESULT $([ "$failures" -eq 0 ] && echo pass || echo "fail ($failures)")"
exit "$failures"

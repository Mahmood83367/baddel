# Baddel for the Bash command line (Bash 4.0 or later, Readline in emacs mode).
# Copyright (c) 2026 Mahmood. Released under the MIT License.
#
# Opt in by adding one line to ~/.bashrc (use the folder you unpacked Baddel into):
#
#   source ~/baddel/shell/baddel.bash
#
# Press Baddel's shortcut (the one in its settings, Ctrl+Alt+Space unless you
# changed it) once to correct the last word before the cursor. Press it twice
# quickly to correct the whole command line. If that combination cannot reach a
# terminal, Ctrl+T is used. Readline's own undo (Ctrl+_)
# restores the previous text; after a double press, undo twice. Nothing is ever
# run or accepted for you: the line stays on the prompt for you to review.
#
# Settings, to be set before the `source` line:
#   BADDEL_KEY              a key of your own in Readline notation, instead of Baddel's
#                           shortcut; empty binds nothing
#   BADDEL_BIN              path of the baddel executable
#   BADDEL_DOUBLE_PRESS_MS  time allowed for the second press (default 300)
#   BADDEL_HINT             latin | arabic | none: the layout to assume when the text
#                           itself does not decide (default: the active layout on X11)
#
# Functions you can bind yourself with `bind -x`: _baddel_fix, _baddel_fix_word,
# _baddel_fix_line.

[[ $- == *i* ]] || return 0
if (( BASH_VERSINFO[0] < 4 )); then
  echo "baddel: the Bash integration needs Bash 4.0 or later" >&2
  return 0
fi

: "${BADDEL_BIN:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/baddel}"
: "${BADDEL_DOUBLE_PRESS_MS:=300}"
_baddel_before= _baddel_after= _baddel_time=0 _baddel_armed=0

_baddel_now_ms() {
  if [[ -n ${EPOCHREALTIME-} ]]; then
    local t=${EPOCHREALTIME/[.,]/}
    _baddel_now=$(( ${t%???} ))
  else
    _baddel_now=$(date +%s%3N)
  fi
}

# READLINE_POINT counts characters from Bash 5.0 on and bytes before that
# (checked on 4.4, 5.0, 5.1 and 5.2).
if (( BASH_VERSINFO[0] >= 5 )); then
  _baddel_unit=scalars
else
  _baddel_unit=bytes
fi

# _baddel_apply word|line: corrects READLINE_LINE in place. Returns 1 when unchanged.
_baddel_apply() {
  local mode=$1 out head
  local -a args=(--fix-text --mode "$mode" --unit "$_baddel_unit" --cursor "$READLINE_POINT")
  [[ -n ${BADDEL_HINT-} ]] && args+=(--hint "$BADDEL_HINT")
  [[ -x $BADDEL_BIN ]] || return 1
  # The trailing "x" keeps newlines at the end of the line through $(...).
  out=$(printf '%s' "$READLINE_LINE" | "$BADDEL_BIN" "${args[@]}" 2>/dev/null; printf x)
  out=${out%x}
  head=${out%%$'\n'*}
  if [[ $head =~ ^ok\ [0-9]+$ && $out == *$'\n'* ]]; then
    READLINE_LINE=${out#*$'\n'}
    READLINE_POINT=${head#ok }
    return 0
  fi
  return 1
}

_baddel_fix_word() { _baddel_apply word; }
_baddel_fix_line() { _baddel_apply line; }

# One press: the last word. A second press within the window, while the line is
# still what the first press left: the whole line instead.
_baddel_fix() {
  local start=$READLINE_LINE
  _baddel_now_ms
  if (( _baddel_armed )) && [[ $READLINE_LINE == "$_baddel_after" ]] \
      && (( _baddel_now - _baddel_time <= BADDEL_DOUBLE_PRESS_MS )); then
    _baddel_armed=0
    READLINE_LINE=$_baddel_before
    if [[ $_baddel_unit == bytes ]]; then
      local LC_ALL=C
      READLINE_POINT=${#READLINE_LINE}
      unset LC_ALL
    else
      READLINE_POINT=${#READLINE_LINE}
    fi
    _baddel_apply line || { READLINE_LINE=$start; READLINE_POINT=${#start}; }
    return
  fi
  _baddel_apply word
  _baddel_before=$start
  _baddel_after=$READLINE_LINE
  _baddel_armed=1
  _baddel_now_ms
  _baddel_time=$_baddel_now
}

if [[ -n ${BADDEL_KEY+set} ]]; then
  [[ -n $BADDEL_KEY ]] && bind -m emacs -x "\"$BADDEL_KEY\": _baddel_fix" 2>/dev/null
else
  # Ask Baddel which key sequences its shortcut sends in a terminal.
  _baddel_answer=()
  [[ -x $BADDEL_BIN ]] && mapfile -t _baddel_answer < <("$BADDEL_BIN" --terminal-key bash 2>/dev/null)
  if [[ ${_baddel_answer[0]-} == ok && ${#_baddel_answer[@]} -gt 1 ]]; then
    for _baddel_sequence in "${_baddel_answer[@]:1}"; do
      bind -m emacs -x "\"$_baddel_sequence\": _baddel_fix" 2>/dev/null
    done
  else
    bind -m emacs -x '"\C-t": _baddel_fix' 2>/dev/null
  fi
  unset _baddel_answer _baddel_sequence
fi

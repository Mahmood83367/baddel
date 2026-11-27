# Baddel for the zsh command line.
# Copyright (c) 2026 Mahmood. Released under the MIT License.
#
# Opt in by adding one line to ~/.zshrc (adjust the path if Baddel is elsewhere):
#
#   source /Applications/Baddel.app/Contents/Resources/shell/baddel.zsh
#
# Press Ctrl+T once to correct the selected region, or the last word before the
# cursor when nothing is selected. Press it twice quickly to correct the whole
# command line. zsh's own undo (Ctrl+_) restores the previous text. Nothing is
# ever run or accepted for you: the line stays on the prompt for you to review.
#
# Settings, to be set before the `source` line:
#   BADDEL_KEY              key in bindkey notation (default '^T'); empty binds nothing
#   BADDEL_BIN              path of the Baddel executable
#   BADDEL_DOUBLE_PRESS_MS  time allowed for the second press (default 300)
#   BADDEL_HINT             latin | arabic | none: the layout to assume when the text
#                           itself does not decide (default: the active layout)
#
# Widgets you can bind yourself: baddel-fix, baddel-fix-word, baddel-fix-line.

[[ -o interactive ]] || return 0
zmodload zsh/datetime 2>/dev/null || return 0

: ${BADDEL_BIN:=${${(%):-%x}:A:h:h:h}/MacOS/Baddel}
: ${BADDEL_DOUBLE_PRESS_MS:=300}
typeset -g _baddel_before= _baddel_after= _baddel_time=0

# _baddel_apply word|line: corrects BUFFER in place. Returns 1 when unchanged.
_baddel_apply() {
  emulate -L zsh
  local mode=$1 out head
  local -a args
  args=(--fix-text --mode $mode --unit scalars --cursor $CURSOR)
  if [[ $mode == word ]] && (( REGION_ACTIVE )); then
    if (( MARK < CURSOR )); then args+=(--selection $MARK $(( CURSOR - MARK )))
    else args+=(--selection $CURSOR $(( MARK - CURSOR ))); fi
  fi
  [[ -n ${BADDEL_HINT:-} ]] && args+=(--hint $BADDEL_HINT)
  if [[ ! -x $BADDEL_BIN ]]; then
    zle -M "Baddel: executable not found (set BADDEL_BIN)"
    return 1
  fi
  # The trailing "x" keeps newlines at the end of the buffer through $(...).
  out=$(print -rn -- "$BUFFER" | "$BADDEL_BIN" $args 2>/dev/null; print -n x)
  out=${out%x}
  head=${out%%$'\n'*}
  if [[ $head == ok\ <-> && $out == *$'\n'* ]]; then
    BUFFER=${out#*$'\n'}
    CURSOR=${head#ok }
    REGION_ACTIVE=0
    return 0
  fi
  case $head in
    'no noWord'|'no emptyField') zle -M "Baddel: nothing to correct here" ;;
    'no nothingToConvert') zle -M "Baddel: nothing to convert" ;;
    'no ambiguousDirection') zle -M "Baddel: cannot tell which layout this was typed with" ;;
    no\ *) zle -M "Baddel: left unchanged (${head#no })" ;;
    *) zle -M "Baddel: no answer from $BADDEL_BIN" ;;
  esac
  return 1
}

baddel-fix-word() { _baddel_apply word }
baddel-fix-line() { _baddel_apply line }

# One press: selection or last word. A second press within the window, while
# the line is still what the first press left: the whole line instead.
baddel-fix() {
  emulate -L zsh
  local start=$BUFFER
  if [[ -n $_baddel_after && $BUFFER == $_baddel_after ]] \
      && (( (EPOCHREALTIME - _baddel_time) * 1000 <= BADDEL_DOUBLE_PRESS_MS )); then
    if [[ $_baddel_before != $BUFFER ]]; then
      # Take the first press back, so one undo later returns to the original.
      zle undo
      [[ $BUFFER == $_baddel_before ]] || BUFFER=$_baddel_before
      CURSOR=${#BUFFER}
    fi
    _baddel_after=
    _baddel_apply line
    return
  fi
  _baddel_apply word
  _baddel_before=$start
  _baddel_after=$BUFFER
  _baddel_time=$EPOCHREALTIME
}

zle -N baddel-fix
zle -N baddel-fix-word
zle -N baddel-fix-line
if [[ -n ${BADDEL_KEY-^T} ]]; then bindkey ${BADDEL_KEY-^T} baddel-fix; fi

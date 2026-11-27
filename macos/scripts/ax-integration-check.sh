#!/bin/bash
# Runs the correction engine against a real TextEdit document through
# Accessibility. Requires that the process running this script (your terminal)
# already has Accessibility access; the script never requests or grants it.
#
# TextEdit is opened in the background with throwaway fixture files and is
# terminated afterwards. The check refuses to run if TextEdit is already open,
# so it cannot touch your documents.
set -u
cd "$(dirname "$0")/.."
swift build --product baddel-axcheck >/dev/null || exit 1
CHECK=.build/debug/baddel-axcheck

if pgrep -x TextEdit >/dev/null; then
  echo "TextEdit is already running; close it first. Skipping."
  exit 2
fi

WORK=$(mktemp -d)
trap 'pkill -x TextEdit 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0

run_case() {  # name initial expected -- extra args
  local name=$1 initial=$2 expected=$3
  shift 3
  printf '%s' "$initial" > "$WORK/initial.txt"
  printf '%s' "$expected" > "$WORK/expected.txt"
  cp "$WORK/initial.txt" "$WORK/doc.txt"
  open -g -F -a TextEdit "$WORK/doc.txt"
  local pid=""
  for _ in $(seq 1 50); do
    pid=$(pgrep -x TextEdit) && break
    sleep 0.1
  done
  sleep 1.5
  echo "== $name"
  if "$CHECK" --pid "$pid" --initial "$WORK/initial.txt" --expected "$WORK/expected.txt" "$@"; then :; else
    failures=$((failures + 1))
  fi
  pkill -x TextEdit
  for _ in $(seq 1 50); do pgrep -x TextEdit >/dev/null || break; sleep 0.1; done
}

run_case "whole field, then undo" 'hgsghl ugd;l' 'السلام عليكم' --mode field --arabic arabic-pc --undo
run_case "last word before caret, trailing spaces, RTL context" 'مرحبا ugd;l  ' 'مرحبا عليكم  ' --mode single --caret 13 --undo
run_case "exact selection, then undo refused after the text changes" 'say ugd;l now' 'say عليكم now' --mode single --select 4,5 --tamper
run_case "UTF-16 offsets after an emoji (Mac Arabic layout)" '😀 lnpfh' '😀 مرحبا' --mode single --caret 8 --arabic arabic-mac --undo
run_case "Arabic typed instead of English" 'اثممخ' 'hello' --mode single --caret 5 --undo
run_case "safe rejection: nothing before the caret" '   ' '   ' --mode single --caret 3 --expect-reject noWord

echo
if [ "$failures" -eq 0 ]; then echo "All TextEdit checks passed."; else echo "$failures check(s) failed."; exit 1; fi

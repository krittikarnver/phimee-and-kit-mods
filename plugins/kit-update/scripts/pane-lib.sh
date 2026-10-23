#!/usr/bin/env bash
# kit-update pane-lib — screen checks shared by reload-all.sh and restart.
#
# Source this file; it only defines functions and has no side effects.
# Both read a Claude Code screen (the last ~15 non-blank lines) as text.
# The check is a reading of the UI: when unsure, callers skip the pane.

# The input box is the last ❯ line; empty, or showing only its "Try …" hint.
prompt_empty() { grep -E '^❯' <<<"$1" | tail -1 | grep -qE '^❯[[:space:]]*($|Try ")'; }

# Echo busy | question | draft | idle for SCREEN, checked in that order.
screen_state() {
  if grep -qE '…[[:space:]]*\([0-9]|esc to interrupt' <<<"$1"; then
    echo busy
  elif grep -qE 'Do you want|Enter to confirm|Esc to cancel' <<<"$1"; then
    echo question
  elif ! prompt_empty "$1"; then
    echo draft
  else
    echo idle
  fi
}

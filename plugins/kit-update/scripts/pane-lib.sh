#!/usr/bin/env bash
# kit-update pane-lib — screen checks shared by reload-all.sh and restart.
#
# Source this file; it only defines functions and has no side effects.
# They read a Claude Code screen with its escape codes (tmux capture-pane -p -e, herdr agent read
# --format ansi), or as plain text: only the codes tell Claude Code's suggested next prompt, dim text
# in the input box, from typed text. The check is a reading of the UI: when unsure, callers skip the pane.

# awk PROGRAM over stdin (bytes, LC_ALL=C), with two functions for it:
#   esc(s)    s as plain text: without escape codes, CSI (colours, dim, ...) and OSC (hyperlinks), and
#             with its no-break spaces as spaces (Claude Code puts one after ❯; [[:space:]] reads it as
#             a space only in a UTF-8 locale, and a tmux server started without LANG has none)
#   undim(s)  s without the text drawn dim (SGR 2, up to 0, 22 or a bare m); the parameters of
#             a 38/48/58 colour are skipped, so a colour number 2 isn't taken for dim
screen_awk() {
  LC_ALL=C awk '
    function esc(s) { gsub(/\033\[[0-?]*[ -\/]*[@-~]|\033\][^\007\033]*(\007|\033\\)/, "", s); gsub(/\302\240/, " ", s); return s }
    function undim(s,   out, dim, n, p, k, c) {
      while (match(s, /\033\[[0-9;:]*m/)) {
        if (!dim) out = out substr(s, 1, RSTART - 1)
        n = split(substr(s, RSTART + 2, RLENGTH - 3), p, ";")
        if (n == 0) dim = 0
        for (k = 1; k <= n; k++) {
          c = p[k]; sub(/:.*/, "", c); c += 0
          if ((c == 38 || c == 48 || c == 58) && p[k] !~ /:/) k += (p[k + 1] == 5 ? 2 : (p[k + 1] == 2 ? 4 : 0))
          else if (c == 0 || c == 22) dim = 0
          else if (c == 2) dim = 1
        }
        s = substr(s, RSTART + RLENGTH)
      }
      return dim ? out : out s
    }
  '"$1"
}

# The last 15 lines of the screen on stdin whose text isn't blank (a line of escape codes and spaces only is blank).
screen_tail() { screen_awk 'esc($0) ~ /[^[:space:]]/' | tail -15; }

# The input box is the last line whose text starts with ❯ (tmux writes a colour code before it); empty,
# or showing only its "Try …" hint. Its dim text is a suggestion, not typed, and is dropped there only:
# elsewhere on the screen, dim text counts.
prompt_empty() {
  screen_awk 'esc($0) ~ /^❯/ { l = $0 } END { print esc(undim(l)) }' <<<"$1" | grep -qE '^❯[[:space:]]*($|Try ")'
}

# Echo busy | question | draft | idle for SCREEN, checked in that order.
screen_state() {
  local s
  s=$(screen_awk '{ print esc($0) }' <<<"$1")
  if grep -qE '…[[:space:]]*\([0-9]|esc to interrupt' <<<"$s"; then
    echo busy
  elif grep -qE 'Do you want|Enter to confirm|Esc to cancel' <<<"$s"; then
    echo question
  elif ! prompt_empty "$1"; then
    echo draft
  else
    echo idle
  fi
}

#!/usr/bin/env bash
# kit-update pane-lib — screen checks shared by reload-all.sh and restart.
#
# Source this file; it only defines functions (and _pane_lib_dir) and has no side effects.
# They read a Claude Code screen with its escape codes (tmux capture-pane -p -e, or hc-screen.pl for
# a herdr-core terminal), or as plain text: only the codes tell Claude Code's suggested next prompt, dim
# text in the input box, from typed text. The check is a reading of the UI: when unsure, callers skip the pane.

# awk PROGRAM over stdin (bytes, LC_ALL=C), with two functions for it:
#   esc(s)    s as plain text: without escape codes, CSI (colours, dim, ...), OSC (hyperlinks) and
#             two-character escapes (the reset a herdr-core first paint starts with: ESC H, ESC ( B; not
#             ESC [ and ESC ], which are CSI and OSC), and
#             with its no-break spaces as spaces (Claude Code puts one after ❯; [[:space:]] reads it as
#             a space only in a UTF-8 locale, and a tmux server started without LANG has none)
#   undim(s)  s without the text drawn dim (SGR 2, up to 0, 22 or a bare m); the parameters of
#             a 38/48/58 colour are skipped, so a colour number 2 isn't taken for dim
screen_awk() {
  LC_ALL=C awk '
    function esc(s) { gsub(/\033\[[0-?]*[ -\/]*[@-~]|\033\][^\007\033]*(\007|\033\\)|\033[ -\/]*[0-Z\\^-~]/, "", s); gsub(/\302\240/, " ", s); return s }
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

# herdr-core (hc).

# Is herdr-core up? Every hc command starts it when it is not, so ask pgrep first. A tmux started from an hc
# tab keeps that tab's HC_TERMINAL_ID after the core is gone, so that variable counts only outside tmux, and
# only when pgrep cannot answer (missing, or status 2 and up).
hc_up() {
  "${KIT_UPDATE_PGREP_BIN:-pgrep}" -x -U "$(id -u)" herdr-core >/dev/null 2>&1
  case $? in
    0) return 0 ;;
    1) return 1 ;;
  esac
  [[ -n "${HC_TERMINAL_ID:-}" && -z "${TMUX:-}" ]]
}

# The only way the scripts run hc: without HC_TERMINAL_ID (hc would wrap what it sends as chat from that
# terminal) and without the caller's stdin (reload calls it inside a `while read` loop, and hc would eat the list).
hc_call() { env -u HC_TERMINAL_ID "${KIT_UPDATE_HC_BIN:-hc}" "$@" </dev/null; }

_pane_lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Terminal T's screen with its escape codes; status 1 when it cannot be read. hc-screen.pl's stderr is dropped:
# it would land in the report Claude reads.
hc_screen() {
  if [[ -n "${KIT_UPDATE_SCREEN_BIN:-}" ]]; then
    "$KIT_UPDATE_SCREEN_BIN" "$1" </dev/null 2>/dev/null
  else
    perl "$_pane_lib_dir/hc-screen.pl" "$1" </dev/null 2>/dev/null
  fi
}

# Echo busy | question | draft | idle | unreadable for terminal T, whose status word is STATUS ("" when it has none).
# hc knows a turn in progress and an open question; for anything else the screen decides, as in tmux.
hc_state() {
  local raw
  case "$2" in
    working) echo busy; return ;;
    blocked) echo question; return ;;
  esac
  raw=$(hc_screen "$1") || { echo unreadable; return; }
  screen_state "$(screen_tail <<<"$raw")"
}

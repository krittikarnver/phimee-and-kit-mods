#!/usr/bin/env bash
# kit-update reload — type /reload-plugins into every idle Claude Code session in tmux.
#
# A session only loads updated plugins after /reload-plugins, and nothing can
# run it from outside. When Claude runs in tmux, this types it for you:
#   1. lists every tmux pane      (tmux list-panes -a)
#   2. keeps the Claude Code ones (the process is named after its version, or `claude`)
#   3. reads each one's screen and skips it unless it is idle with an empty prompt
#   4. types /reload-plugins + Enter into the rest
#
# Skipped, never typed into: the pane this runs from ($TMUX_PANE), a turn in
# progress, an open question or dialog (Enter would answer it), a half-typed
# prompt. The screen check is a reading of the UI: when unsure, it skips.
#
# Usage: reload-all.sh   (no options)
# Exit code: 0, also when there is no tmux server.

set -uo pipefail

TMUX_BIN="${KIT_UPDATE_TMUX_BIN:-tmux}"   # override for testing

if [[ -t 1 ]]; then
  B=$'\e[1m'; G=$'\e[32m'; N=$'\e[0m'
else
  B=; G=; N=
fi

panes=$("$TMUX_BIN" list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}' 2>/dev/null) || {
  echo "No tmux server — run /reload-plugins in each Claude Code session yourself."
  exit 0
}

reloaded=() skipped=()
while IFS=$'\t' read -r id name cmd; do
  [[ -z "$id" ]] && continue
  if [[ ! "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$cmd" != claude ]]; then
    continue # not Claude Code: not worth listing
  fi
  if [[ "$id" == "${TMUX_PANE:-}" ]]; then
    skipped+=("$name — this session: run /reload-plugins here yourself")
    continue
  fi

  screen=$("$TMUX_BIN" capture-pane -p -t "$id" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -15)
  if grep -qE '…[[:space:]]*\([0-9]|esc to interrupt' <<<"$screen"; then
    skipped+=("$name — busy")
    continue
  fi
  if grep -qE 'Do you want|Enter to confirm|Esc to cancel' <<<"$screen"; then
    skipped+=("$name — waiting on a question")
    continue
  fi
  # The input box is the last ❯ line; empty, or showing only its "Try …" hint.
  if ! grep -E '^❯' <<<"$screen" | tail -1 | grep -qE '^❯[[:space:]]*($|Try ")'; then
    skipped+=("$name — prompt not empty or not found")
    continue
  fi

  "$TMUX_BIN" send-keys -t "$id" -l '/reload-plugins' && "$TMUX_BIN" send-keys -t "$id" Enter \
    && reloaded+=("$name") || skipped+=("$name — send-keys failed")
done <<<"$panes"

printf '%sSummary%s  reloaded: %s%d%s · skipped: %d\n' "$B" "$N" "$G" "${#reloaded[@]}" "$N" "${#skipped[@]}"
((${#reloaded[@]})) && { echo "  Reloaded:"; printf '    - %s\n' "${reloaded[@]}"; }
((${#skipped[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${skipped[@]}"; }
exit 0

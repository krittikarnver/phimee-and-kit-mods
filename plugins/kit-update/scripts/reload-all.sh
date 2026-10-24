#!/usr/bin/env bash
# kit-update reload — type /reload-plugins into every idle Claude Code session in tmux or herdr.
#
# A session only loads updated plugins after /reload-plugins, and nothing can
# run it from outside. When Claude runs in tmux or herdr, this types it for you:
#   tmux:  1. lists every tmux pane      (tmux list-panes -a)
#          2. keeps the Claude Code ones (the process is named after its version, or `claude`)
#          3. reads each one's screen and skips it unless it is idle with an empty prompt
#   herdr: 1. lists the Claude agents    (herdr agent list)
#          2. skips any whose state is not idle or done (herdr knows busy and open questions)
#          3. reads each one's screen and skips it unless the prompt is empty
#   then types /reload-plugins + Enter into the rest.
#
# Skipped, never typed into: the pane this runs from ($TMUX_PANE, $HERDR_PANE_ID),
# a turn in progress, an open question or dialog (Enter would answer it), a
# half-typed prompt. The screen check is a reading of the UI: when unsure, it skips.
#
# Usage: reload-all.sh   (no options)
# Exit code: 0, also when there is no tmux or herdr server.

set -uo pipefail

TMUX_BIN="${KIT_UPDATE_TMUX_BIN:-tmux}"     # override for testing
HERDR_BIN="${KIT_UPDATE_HERDR_BIN:-herdr}"  # override for testing

if [[ -t 1 ]]; then
  B=$'\e[1m'; G=$'\e[32m'; N=$'\e[0m'
else
  B=; G=; N=
fi

source "$(dirname "$0")/pane-lib.sh"

reloaded=() skipped=() found=0

if panes=$("$TMUX_BIN" list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}' 2>/dev/null); then
  found=1
  while IFS=$'\t' read -r id name cmd; do
    [[ -z "$id" ]] && continue
    if [[ ! "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$cmd" != claude ]]; then
      continue # not Claude Code: not worth listing
    fi
    if [[ "$id" == "${TMUX_PANE:-}" ]]; then
      skipped+=("$name — this session: run /reload-plugins here yourself")
      continue
    fi

    screen=$("$TMUX_BIN" capture-pane -p -e -t "$id" 2>/dev/null | screen_tail)
    case "$(screen_state "$screen")" in
      busy) skipped+=("$name — busy"); continue ;;
      question) skipped+=("$name — waiting on a question"); continue ;;
      draft) skipped+=("$name — prompt not empty or not found"); continue ;;
    esac

    "$TMUX_BIN" send-keys -t "$id" -l '/reload-plugins' && "$TMUX_BIN" send-keys -t "$id" Enter \
      && reloaded+=("$name") || skipped+=("$name — send-keys failed")
  done <<<"$panes"
fi

if agents=$("$HERDR_BIN" agent list 2>/dev/null); then
  found=1
  while IFS=$'\t' read -r id name state; do
    [[ -z "$id" ]] && continue
    if [[ "$id" == "${HERDR_PANE_ID:-}" ]]; then
      skipped+=("$name — this session: run /reload-plugins here yourself")
      continue
    fi
    case "$state" in
      idle | done) ;;
      working) skipped+=("$name — busy"); continue ;;
      blocked) skipped+=("$name — waiting on a question"); continue ;;
      *) skipped+=("$name — state $state"); continue ;;
    esac

    screen=$("$HERDR_BIN" agent read "$id" --source visible --format ansi 2>/dev/null | screen_tail)
    if ! prompt_empty "$screen"; then
      skipped+=("$name — prompt not empty or not found")
      continue
    fi

    # agent prompt sends the text and Enter together, and refuses an agent that is blocked
    "$HERDR_BIN" agent prompt "$id" '/reload-plugins' >/dev/null 2>&1 \
      && reloaded+=("$name") || skipped+=("$name — agent prompt failed")
  done < <(jq -r '.result.agents[] | select(.agent == "claude")
    | [.pane_id, "\(.name // (.cwd | split("/") | last)) (herdr \(.pane_id))", .agent_status] | @tsv' <<<"$agents")
fi

if ((!found)); then
  echo "No tmux or herdr server — run /reload-plugins in each Claude Code session yourself."
  exit 0
fi

printf '%sSummary%s  reloaded: %s%d%s · skipped: %d\n' "$B" "$N" "$G" "${#reloaded[@]}" "$N" "${#skipped[@]}"
((${#reloaded[@]})) && { echo "  Reloaded:"; printf '    - %s\n' "${reloaded[@]}"; }
((${#skipped[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${skipped[@]}"; }
exit 0

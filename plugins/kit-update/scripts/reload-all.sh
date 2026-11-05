#!/usr/bin/env bash
# kit-update reload — type /reload-plugins into every idle Claude Code session in tmux or herdr-core.
#
# A session only loads updated plugins after /reload-plugins, and nothing can
# run it from outside. When Claude runs in tmux or herdr-core (hc), this types it for you:
#   tmux:  1. lists every tmux pane      (tmux list-panes -a)
#          2. keeps the Claude Code ones (the process is named after its version, or `claude`)
#          3. reads each one's screen and skips it unless it is idle with an empty prompt
#   hc:    1. lists the Claude terminals (hc ls), only when herdr-core is already running: hc would start it
#          2. skips any whose status is working or blocked (hc knows busy and open questions) or that has
#             something else in front than Claude Code (a tmux client, say)
#          3. reads each one's screen (hc-screen.pl) and skips it unless the prompt is empty
#   then types /reload-plugins + Enter into the rest.
#
# Skipped, never typed into: the pane this runs from ($TMUX_PANE, $HC_TERMINAL_ID outside tmux), a turn in
# progress, an open question or dialog (Enter would answer it), a half-typed prompt. The screen check is
# a reading of the UI: when unsure, it skips.
#
# Usage: reload-all.sh   (no options)
# Exit code: 0, also when there is no tmux or herdr-core server.

set -uo pipefail

TMUX_BIN="${KIT_UPDATE_TMUX_BIN:-tmux}"  # override for testing

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

# Inside tmux, HC_TERMINAL_ID may be left over from the hc tab that started it: it is no terminal of ours.
me=; [[ -z "${TMUX:-}" ]] && me=${HC_TERMINAL_ID:-}

if hc_up && terms=$(hc_call ls --json 2>/dev/null); then
  found=1
  while IFS=$'\x1f' read -r t status name; do
    [[ -z "$t" ]] && continue
    if [[ "$t" == "$me" ]]; then
      skipped+=("$name — this session: run /reload-plugins here yourself")
      continue
    fi

    # hc lists the terminal's agent even when a tmux client is in front of it, and keys would go to that
    if ! info=$(hc_call get "$t" --json 2>/dev/null); then
      skipped+=("$name — herdr-core does not answer")
      continue
    fi
    front=$(jq -r '.foreground.name // empty' <<<"$info" 2>/dev/null)
    if [[ ! "$front" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$front" != claude ]]; then
      skipped+=("$name — Claude Code is not in front (${front:-nothing})")
      continue
    fi

    case "$(hc_state "$t" "$status")" in
      busy) skipped+=("$name — busy"); continue ;;
      question) skipped+=("$name — waiting on a question"); continue ;;
      draft) skipped+=("$name — prompt not empty or not found"); continue ;;
      unreadable) skipped+=("$name — screen unreadable"); continue ;;
    esac

    hc_call send "$t" '/reload-plugins' >/dev/null 2>&1 \
      && reloaded+=("$name") || skipped+=("$name — hc send failed")
  done < <(jq -r '.terminals[] | select(.agent == "claude-code" and .state == "live" and (.address | contains("/") | not))
    | [.address, (.status // ""),
       ((.name | select(. != "")) // (.where | select(. != "")) // ((.cwd // "") | split("/") | last)) + " (hc " + .address + ")"]
    | join("\u001f")' <<<"$terms")
fi

if ((!found)); then
  echo "No tmux or herdr-core server — run /reload-plugins in each Claude Code session yourself."
  exit 0
fi

printf '%sSummary%s  reloaded: %s%d%s · skipped: %d\n' "$B" "$N" "$G" "${#reloaded[@]}" "$N" "${#skipped[@]}"
((${#reloaded[@]})) && { echo "  Reloaded:"; printf '    - %s\n' "${reloaded[@]}"; }
((${#skipped[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${skipped[@]}"; }
exit 0

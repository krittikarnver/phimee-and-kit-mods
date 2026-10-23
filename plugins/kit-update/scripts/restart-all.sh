#!/usr/bin/env bash
# kit-update restart — restart every Claude Code session in tmux or herdr once it is idle,
# each one starting a fresh context from a handoff it writes first.
#
# This script only takes the snapshot and starts the worker. restart-worker.sh does the
# rest from a pane of its own: it waits for each session to be idle, asks it for a
# handoff, types /exit, then starts `claude --name <name>` with the handoff as the first
# message. Here:
#   1. take the lock <config>/kit-update/restart.lock (mkdir, so one worker at a time).
#      A live worker, or a lock that is still starting (under 60 s), is reported and left
#      alone. A lock whose worker is gone, or that has been starting for 60 s, is taken over.
#   2. snapshot the Claude Code sessions running now, each tied to its process through its
#      session file (<config>/sessions/<pid>.json):
#        tmux:  the pane's process, or a child of the pane's bash or zsh (or sh -c)
#        herdr: the agent's session id → the one live process whose session file has it
#      The session that runs this script is found up its parent chain; it goes last.
#   3. write the snapshot to restart.lock/state.<token>, open a pane for the worker (a herdr
#      workspace when this runs in herdr, else a detached tmux session) and type
#      `bash restart-worker.sh <state file>` into it.
#   4. print who will restart, who is skipped and why, and where the worker and log are.
#
# Skipped at the snapshot: a tmux pane that runs Claude through a wrapper, a herdr pane
# whose shell is not an interactive bash or zsh (nothing to relaunch in), a herdr pane that
# runs tmux (keys would land in whichever tmux pane is active; the tmux side covers it),
# two live processes on one session, teammates of an agent team, and a session file that
# is not interactive or lacks a field the worker checks. Sessions opened after the
# snapshot are left alone. Nothing is written outside <config>/kit-update.
#
# Usage: restart-all.sh   (no options)
# Exit code: 0, also when there is nothing to restart; 1 when the worker could not start.

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
source "$here/restart-lib.sh"
ku_paths
mkdir -p "$KU_DIR" "$HANDOFFS" || exit 1

TOKEN=$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')
SOCK=${TMUX:-}; SOCK=${SOCK%%,*} # the caller's tmux server, for a worker that runs outside it
tm() { "$TMUX_BIN" ${SOCK:+-S "$SOCK"} "$@"; }

# Until the worker is launched, every way out gives the lock back, if it is still ours.
cleanup() { lock_release "$TOKEN" || rm -f "$LOCK/state.$TOKEN" "$LOCK/state.$TOKEN.tmp"; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
fail() { echo "Could not start the worker: $1. Nothing was restarted."; exit 1; }

hhmmss() { date -r "$1" +%H%M%S 2>/dev/null || date -d "@$1" +%H%M%S; } # BSD, then GNU date

# The ppid chain above PID, up to (not including) pid 1.
ancestors() {
  local p=$1 n=0
  while p=$(proc_field "$p" ppid) && ((p > 1 && n++ < 64)); do echo "$p"; done
}

# 0 when a process above PID is tmux: Claude runs in a tmux pane (inside herdr or not).
tmux_above() {
  local p a
  for p in $(ancestors "$1"); do
    a=$(proc_field "$p" args); a=${a%% *}; a=${a##*/}
    [[ "$a" == tmux || "$a" == tmux: ]] && return 0
  done
  return 1
}

# A tmux pane may run Claude from bash or zsh (shell_ok), or from sh, bash or zsh -c (the
# pane then dies with Claude, and the worker respawns it). Anything else is a wrapper.
pane_shell_ok() {
  local IFS=$' \t\n' a w
  shell_ok "$1" && return 0
  read -ra a <<<"$1"
  w=${a[0]:-}; w=${w#-}; w=${w##*/}
  [[ ("$w" == sh || "$w" == bash || "$w" == zsh) && "${a[1]:-}" == -*c* ]]
}

# 0 when PID has a session file of its own (a stale file's pid may be reused). A file
# without procStart counts too, so that add reports it.
is_claude() {
  local s
  [[ -f "$(sf_path "$1")" ]] || return 1
  s=$(sf_get "$1" procStart)
  [[ -z "$s" || "$(tr -s ' ' <<<"$s")" == "$(proc_field "$1" start)" ]]
}

# Fields joined by tabs; a tab or newline inside a field becomes a space.
tsv() {
  local f out=$1
  shift
  for f in "$@"; do f=${f//$'\t'/ }; out+=$'\t'"${f//$'\n'/ }"; done
  printf '%s\n' "$out"
}

entry() { if [[ "$1" == tmux ]]; then echo "$4 (tmux $3)"; else echo "$4 (herdr $2)"; fi; } # MUX PANE LABEL NAME
skip() { SKIPPED+=("$1 — $2"); }
print_skipped() { ((${#SKIPPED[@]})) && { echo "Skipped:"; printf '  - %s\n' "${SKIPPED[@]}"; }; }

# Keep Claude PID's pane as a state row, or skip it with the reason.
add() { # MUX PANE LABEL PID SHELL_PID AGENT_NAME FALLBACK_NAME
  local k name args sid shown me=0
  name=$(sf_get "$4" name)
  shown=$(entry "$1" "$2" "$3" "${name:-$7}")
  k=$(sf_get "$4" kind)
  [[ "$k" == interactive ]] || { skip "$shown" "not interactive (kind ${k:-missing})"; return; }
  for k in status statusUpdatedAt procStart; do
    [[ -n "$(sf_get "$4" "$k")" ]] || { skip "$shown" "its session file has no $k"; return; }
  done
  args=$(proc_field "$4" args)
  case " $args" in
    *" --team-name"* | *" --agent-id"* | *" --parent-session-id"*) skip "$shown" "teammate of an agent team"; return ;;
  esac
  sid=$(sf_get "$4" sessionId)
  [[ -n "$sid" && "$(pid_for_sid "$sid")" == "$4" ]] || { skip "$shown" "not exactly one live process on session ${sid:-?}"; return; }
  [[ "$ANC" == *" $4 "* ]] && me=1 issuer=1
  ROWS+=("$(tsv pane "$1" "$2" "$3" "$4" "$(sf_get "$4" procStart)" "$(proc_field "$4" tty)" "$5" "$sid" "$name" \
    "$(sf_get "$4" version)" "$(sf_get "$4" cwd)" "$me" "$6" "$args")")
  LIST+=("$shown")
}

# 1. lock
take_lock() {
  local s
  mkdir "$LOCK" 2>/dev/null && return 0
  s=$(lock_check "$LOCK")
  case "$s" in
    running*) echo "A restart is already running: its worker is in ${s#running }. Log: $LOG"; exit 0 ;;
    stale) lock_takeover "$TOKEN" && return 0 ;;
  esac
  echo "A restart is starting from another session; try again in a minute."
  exit 0
}
take_lock
# ln, not mv: it fails rather than replace an owner file that is already there (another caller's)
printf 'starting %s\n' "$TOKEN" >"$LOCK/owner.$TOKEN" && ln "$LOCK/owner.$TOKEN" "$LOCK/owner" 2>/dev/null
rc=$?
rm -f "$LOCK/owner.$TOKEN"
((rc == 0)) || { rmdir "$LOCK" 2>/dev/null; fail "could not write $LOCK/owner"; } # rmdir: only if still empty

# 2. snapshot
ROWS=() LIST=() SKIPPED=() SEEN=' ' issuer=0 have_tmux= have_herdr=
ANC=" $(ancestors $$ | tr '\n' ' ')"

if panes=$(tm list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}' 2>/dev/null); then
  have_tmux=1
  while IFS=$'\t' read -r id where pp; do
    [[ -n "$id" ]] || continue
    cl= sh=-
    if is_claude "$pp"; then
      cl=$pp
    else
      sh=$pp
      for k in $(proc_children "$pp" | cut -d' ' -f1); do is_claude "$k" && cl+=" $k"; done
      cl=${cl# }
    fi
    [[ -n "$cl" ]] || continue # not Claude Code
    SEEN+="$cl "
    shown=$(entry tmux "$id" "$where" "${where%%:*}")
    if [[ "$cl" == *' '* ]]; then skip "$shown" "two Claude processes in the pane"; continue; fi
    if [[ "$sh" != - ]] && ! pane_shell_ok "$(proc_field "$sh" args)"; then
      skip "$shown" "launched through a wrapper ($(proc_field "$sh" args))"
      continue
    fi
    add tmux "$id" "$where" "$cl" "$sh" '' "${where%%:*}"
  done <<<"$panes"
fi

if agents=$("$HERDR_BIN" agent list 2>/dev/null); then
  have_herdr=1
  ws=$("$HERDR_BIN" workspace list 2>/dev/null) && jq -e . >/dev/null 2>&1 <<<"$ws" || ws='{}'
  while IFS=$'\x1f' read -r id label aname sid; do # \x1f, not tab: read merges empty tab-separated fields
    [[ -n "$id" ]] || continue
    shown=$(entry herdr "$id" "$label" "${aname:-$label}")
    [[ -n "$sid" ]] || { skip "$shown" "herdr shows no session id"; continue; }
    pid=$(pid_for_sid "$sid") || { skip "$shown" "not exactly one live process on session $sid"; continue; }
    if tmux_above "$pid"; then
      [[ "$SEEN" == *" $pid "* ]] || skip "$shown" "runs inside a tmux that was not listed"
      continue
    fi
    sh=$(proc_field "$pid" ppid)
    shell_ok "$(proc_field "$sh" args)" || { skip "$shown" "its shell is not an interactive bash or zsh ($(proc_field "$sh" args))"; continue; }
    add herdr "$id" "$label" "$pid" "$sh" "$aname" "${aname:-$label}"
  done < <(jq -r --argjson ws "$ws" '
    ([$ws.result.workspaces[]? | select(.workspace_id != null) | {key: .workspace_id, value: (.label // "")}]
      | from_entries) as $label
    | .result.agents[]? | select(.agent == "claude")
    | [.pane_id, ($label[.workspace_id // ""] // ""), (.name // ""), (.agent_session.value // "")] | join("\u001f")
  ' <<<"$agents")
fi

if [[ -z "$have_tmux$have_herdr" ]]; then
  echo "No tmux or herdr server — restart each Claude Code session yourself."
  exit 0
fi
if ((${#ROWS[@]} == 0)); then
  echo "No Claude Code session to restart."
  print_skipped
  exit 0
fi

# 3. state, then the worker, in the caller's multiplexer, else in the one that has a server
if [[ -n "${HERDR_ENV:-}" ]]; then wmux=herdr
elif [[ -n "${TMUX:-}" ]]; then wmux=tmux
elif [[ -n "$have_herdr" ]]; then wmux=herdr
else wmux=tmux
fi
st="$LOCK/state.$TOKEN"
{ printf 'config\t%s\nsocket\t%s\nmux\t%s\n' "$CFG" "$SOCK" "$wmux"; printf '%s\n' "${ROWS[@]}"; } >"$st.tmp" \
  && mv -f "$st.tmp" "$st" || fail "could not write $st"
if [[ "$(lock_token)" != "$TOKEN" ]]; then
  echo "Another session took the restart lock meanwhile; not starting a second worker."
  exit 0
fi

cmd="bash $(printf %q "$here/restart-worker.sh") $(printf %q "$st")"
(($(printf '%s' "$cmd" | wc -c) <= 1024)) || fail "its command line is over 1024 bytes"
t=$(hhmmss "$(ku_now)")
if [[ "$wmux" == herdr ]]; then
  worker=$("$HERDR_BIN" workspace create --label "kit-update restart $t" --no-focus 2>/dev/null \
    | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null)
  [[ -n "$worker" ]] || fail "herdr workspace create failed"
  run_detached "$HERDR_BIN" pane run "$worker" "$cmd" || fail "herdr pane run failed"
else
  worker=kit-update-restart-$t n=1 # the worker pane of an earlier run may still be open
  while tm has-session -t "=$worker" 2>/dev/null && ((n++ < 9)); do worker=kit-update-restart-$t-$n; done
  tm new-session -d -s "$worker" -c "$KU_DIR" 2>/dev/null || fail "tmux new-session failed"
  run_detached tm send-keys -t "$worker" -l "$cmd" \; send-keys -t "$worker" Enter || fail "tmux send-keys failed"
fi
trap - EXIT INT TERM HUP # the worker owns the lock from here

# 4. report
echo "Restarting ${#LIST[@]} session(s) when idle:"
printf '  - %s\n' "${LIST[@]}"
print_skipped
if ((issuer)); then echo "This session: in the snapshot, goes last"; else echo "This session: not found — restart it yourself"; fi
echo "Worker: $worker"
echo "Log: $LOG"
echo "Handoffs: $HANDOFFS"
exit 0

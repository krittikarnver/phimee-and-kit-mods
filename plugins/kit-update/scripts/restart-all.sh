#!/usr/bin/env bash
# kit-update restart — restart every Claude Code session in tmux or herdr-core once it is idle,
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
#        tmux: the pane's process, or a child of the pane's bash or zsh (or sh -c)
#        hc:   the program in front of a terminal (hc get), when it has a session file here and
#              is a child of the terminal's own shell. hc is asked only while herdr-core is
#              already running: any hc command would start it.
#      The session that runs this script is found up its parent chain; it goes last.
#   3. write the snapshot to restart.lock/state.<token> and start the worker: a herdr-core
#      terminal of its own (hc run) unless this runs in tmux or herdr-core is not up, else a
#      detached tmux session, where `bash restart-worker.sh <state file>` is typed.
#   4. print who will restart, who is skipped and why, and where the worker and log are.
#
# Skipped at the snapshot: a tmux pane that runs Claude through a wrapper, an hc terminal with
# something else in front than a Claude Code of this config (a tmux client: the tmux side covers
# it), Claude as the terminal's own program or under a parent that is not its shell, or under a
# shell that is not an interactive bash or zsh (nothing to relaunch in), no live process on a
# session or two, teammates of an agent team, and a session file that is not interactive or lacks
# a field the worker checks. Sessions opened after the snapshot are left alone. Nothing is
# written outside <config>/kit-update.
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

entry() { if [[ "$1" == tmux ]]; then echo "$4 (tmux $3)"; else echo "$4 (hc $2)"; fi; } # MUX PANE LABEL NAME
skip() { SKIPPED+=("$1 — $2"); }
# Why session SID has no single live process, from pid_for_sid's status RC (2: more than one).
no_pid() { # RC SID
  if [[ "$1" == 2 ]]; then echo "not exactly one live process on session $2"
  else echo "no live Claude Code process for session $2"; fi
}
print_skipped() { ((${#SKIPPED[@]})) && { echo "Skipped:"; printf '  - %s\n' "${SKIPPED[@]}"; }; }

# Keep Claude PID's pane as a state row, or skip it with the reason.
add() { # MUX PANE LABEL PID SHELL_PID AGENT_NAME FALLBACK_NAME
  local k name args sid shown p rc me=0
  name=$(sf_get "$4" name)
  shown=$(entry "$1" "$2" "$3" "${name:-$7}")
  k=$(sf_get "$4" kind)
  [[ "$k" == interactive ]] || { skip "$shown" "not interactive (kind ${k:-missing})"; return; }
  for k in status statusUpdatedAt procStart; do
    [[ -n "$(sf_get "$4" "$k")" ]] || { skip "$shown" "its session file has no $k"; return; }
  done
  args=$(proc_field "$4" args)
  # A Claude a restart relaunched has the handoff on its command line: any text, and kilobytes of it for the log.
  [[ "$args" == *" [kit-update restart] "* ]] && args="${args%%" [kit-update restart] "*} <kit-update handoff>"
  case " $args" in
    *" --team-name"* | *" --agent-id"* | *" --parent-session-id"*) skip "$shown" "teammate of an agent team"; return ;;
  esac
  sid=$(sf_get "$4" sessionId)
  p=$(pid_for_sid "$sid"); rc=$?
  [[ -n "$sid" && "$p" == "$4" ]] || { skip "$shown" "$(no_pid "$rc" "${sid:-?}")"; return; }
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
ROWS=() LIST=() SKIPPED=() issuer=0 have_tmux= have_hc=
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
    shown=$(entry tmux "$id" "$where" "${where%%:*}")
    if [[ "$cl" == *' '* ]]; then skip "$shown" "two Claude processes in the pane"; continue; fi
    if [[ "$sh" != - ]] && ! pane_shell_ok "$(proc_field "$sh" args)"; then
      skip "$shown" "launched through a wrapper ($(proc_field "$sh" args))"
      continue
    fi
    add tmux "$id" "$where" "$cl" "$sh" '' "${where%%:*}"
  done <<<"$panes"
fi

if hc_up && terms=$(hc_call ls --json 2>/dev/null); then
  have_hc=1
  while IFS=$'\x1f' read -r t label; do # \x1f, not tab: read merges empty tab-separated fields
    [[ -n "$t" ]] || continue
    shown=$(entry hc "$t" "$label" "$label")
    info=$(hc_call get "$t" --json 2>/dev/null) || { skip "$shown" "herdr-core does not answer"; continue; }
    IFS=$'\x1f' read -r pid cl front < <(jq -r '[.pid, .foreground.pid, .foreground.name] | map(. // "") | join("\u001f")' <<<"$info")
    is_claude "$cl" || { skip "$shown" "the program in front is not a Claude Code of this config (${front:-nothing})"; continue; }
    [[ "$cl" != "$pid" ]] || { skip "$shown" "Claude is the terminal's program: no shell to relaunch in"; continue; }
    [[ "$(proc_field "$cl" ppid)" == "$pid" ]] || { skip "$shown" "its parent is not the terminal's shell"; continue; }
    shell_ok "$(proc_field "$pid" args)" || { skip "$shown" "its shell is not an interactive bash or zsh ($(proc_field "$pid" args))"; continue; }
    add hc "$t" "$label" "$cl" "$pid" '' "$label"
  done < <(jq -r '.terminals[] | select(.agent == "claude-code" and .state == "live" and (.address | contains("/") | not))
    | [.address, ((.where | select(. != "")) // ((.cwd // "") | split("/") | last))] | join("\u001f")' <<<"$terms")
fi

if [[ -z "$have_tmux$have_hc" ]]; then
  echo "No tmux or herdr-core server — restart each Claude Code session yourself."
  exit 0
fi
if ((${#ROWS[@]} == 0)); then
  echo "No Claude Code session to restart."
  print_skipped
  exit 0
fi

# 3. state, then the worker: in tmux when the caller is in tmux (an hc tab's HC_TERMINAL_ID outlives its core and
# rides into the tmux it started, so it says nothing there), else in herdr-core when it is up, else in tmux
if [[ -z "${TMUX:-}" && -n "$have_hc" ]]; then wmux=hc; else wmux=tmux; fi
st="$LOCK/state.$TOKEN"
{ printf 'config\t%s\nsocket\t%s\nmux\t%s\n' "$CFG" "$SOCK" "$wmux"; printf '%s\n' "${ROWS[@]}"; } >"$st.tmp" \
  && mv -f "$st.tmp" "$st" || fail "could not write $st"
if [[ "$(lock_token)" != "$TOKEN" ]]; then
  echo "Another session took the restart lock meanwhile; not starting a second worker."
  exit 0
fi

t=$(hhmmss "$(ku_now)")
worker=kit-update-restart-$t n=1 # the worker of an earlier run may still be there
if [[ "$wmux" == hc ]]; then
  while hc_call get "$worker" >/dev/null 2>&1 && ((n++ < 9)); do worker=kit-update-restart-$t-$n; done
  # run's program gets herdr-core's environment, not ours: pass what the worker needs, and TMUX_TMPDIR to find our tmux server
  wenv=("PATH=$PATH")
  for v in LANG "${!LC_@}" TMUX_TMPDIR; do [[ -n "${!v:-}" ]] && wenv+=("$v=${!v}"); done
  run_detached hc_call run --bg --no-parent --name "$worker" --cwd "$KU_DIR" -- env "${wenv[@]}" bash "$here/restart-worker.sh" "$st" \
    || fail "hc run failed"
else
  cmd="bash $(printf %q "$here/restart-worker.sh") $(printf %q "$st")"
  (($(printf '%s' "$cmd" | wc -c) <= 1024)) || fail "its command line is over 1024 bytes"
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
if [[ "$wmux" == hc ]]; then
  echo "Worker: $worker (watch: hc attach $worker · stop: Ctrl-C there, or hc kill $worker · when done: hc rm $worker)"
else
  echo "Worker: $worker"
fi
echo "Log: $LOG"
echo "Handoffs: $HANDOFFS"
exit 0

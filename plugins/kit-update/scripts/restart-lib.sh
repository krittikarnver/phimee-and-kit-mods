#!/usr/bin/env bash
# kit-update restart-lib — process, session file and log helpers for restart.
#
# Source this file; it only defines functions (and sources pane-lib.sh). Call
# ku_paths first: the other helpers read what it sets. It creates nothing, so
# callers make $KU_DIR and $HANDOFFS themselves before logging or writing there.
#
# Other processes are read through $PS_BIN only, so tests can stand in a fake ps.
# Session files (<config>/sessions/<pid>.json) are Claude Code's internal state,
# not documented: pid, sessionId, name, version, status, statusUpdatedAt, kind,
# procStart (the process start in UTC, in ps lstart form) and cwd.

source "$(dirname "${BASH_SOURCE[0]}")/pane-lib.sh"

# Set the paths and binaries. The KIT_UPDATE_* overrides are for testing.
ku_paths() {
  CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  KU_DIR="$CFG/kit-update"
  LOCK="$KU_DIR/restart.lock"
  LOG="$KU_DIR/restart.log"
  HANDOFFS="$KU_DIR/handoffs"
  TMUX_BIN="${KIT_UPDATE_TMUX_BIN:-tmux}"
  HERDR_BIN="${KIT_UPDATE_HERDR_BIN:-herdr}"
  PS_BIN="${KIT_UPDATE_PS_BIN:-ps}"
}

ku_now() { if [[ -n "${KIT_UPDATE_CLOCK_BIN:-}" ]]; then "$KIT_UPDATE_CLOCK_BIN"; else date +%s; fi; }
ku_nap() { "${KIT_UPDATE_SLEEP_BIN:-sleep}" "$1"; }

# Append "YYYY-MM-DD HH:MM:SS  LABEL — MESSAGE" to $LOG, then echo it.
ku_log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S')  $1 — $2"
  printf '%s\n' "$line" >>"$LOG"
  printf '%s\n' "$line"
}

# "PID PPID PGID TPGID TTY <lstart: 5 words> ARGS", or return 1 when PID is gone.
# TZ=UTC because procStart in session files is UTC.
proc_row() {
  local row
  row=$(TZ=UTC LC_ALL=C "$PS_BIN" -o pid=,ppid=,pgid=,tpgid=,tty=,lstart=,args= -p "$1" 2>/dev/null) \
    && [[ -n "$row" ]] && printf '%s\n' "$row"
}

# One field of proc_row: ppid | pgid | tpgid | tty | start (lstart, single-spaced) | args.
proc_field() {
  local row pid ppid pgid tpgid tty w1 w2 w3 w4 w5 args start
  row=$(proc_row "$1") || return 1
  read -r pid ppid pgid tpgid tty w1 w2 w3 w4 w5 args <<<"$row"
  start="$w1 $w2 $w3 $w4 $w5"
  case "$2" in
    ppid | pgid | tpgid | tty | start | args) printf '%s\n' "${!2}" ;;
    *) return 2 ;;
  esac
}

proc_alive() { proc_row "$1" >/dev/null; }

# Its process group owns the terminal (pgid = tpgid): not suspended or in the background.
proc_foreground() {
  local g t
  g=$(proc_field "$1" pgid) && t=$(proc_field "$1" tpgid) && [[ "$g" == "$t" ]]
}

# "PID ARGS" for each direct child of PID.
proc_children() {
  local pid ppid args
  "$PS_BIN" -A -o pid=,ppid=,args= 2>/dev/null | while read -r pid ppid args; do
    if [[ "$ppid" == "$1" ]]; then printf '%s %s\n' "$pid" "$args"; fi
  done
}

# 0 when ARGS is bash or zsh (basename of argv[0], leading - of a login shell dropped)
# with no c in any option group before the first operand (-c, -lc, -ic): a shell that
# is still there to type into after Claude exits.
shell_ok() {
  local a w
  read -ra a <<<"$1"
  w=${a[0]:-}; w=${w#-}; w=${w##*/}
  [[ "$w" == bash || "$w" == zsh ]] || return 1
  for w in "${a[@]:1}"; do
    case "$w" in
      -*c*) return 1 ;;
      -*) ;;
      *) break ;;
    esac
  done
  return 0
}

# Pids of the background Bash shells of Claude PID: direct children that source a
# shell snapshot. MCP servers (npm exec ..., docker mcp gateway ...) and caffeinate don't count.
bg_shells() {
  local pid args
  proc_children "$1" | while read -r pid args; do
    if [[ "$args" == */shell-snapshots/snapshot-* ]]; then echo "$pid"; fi
  done
}

sf_path() { printf '%s\n' "$CFG/sessions/$1.json"; }
sf_get() { jq -r ".$2 // empty" "$(sf_path "$1")" 2>/dev/null; }

# The pid whose session file has sessionId SID, whose process is alive and started at
# procStart (a stale file's pid may have been reused). Empty when none or more than one.
pid_for_sid() {
  local f pid start hit=
  for f in "$CFG"/sessions/*.json; do
    start=$(jq -r --arg s "$1" 'select(.sessionId == $s) | .procStart // empty' "$f" 2>/dev/null)
    [[ -n "$start" ]] || continue
    pid=${f##*/}; pid=${pid%.json}
    [[ "$(tr -s ' ' <<<"$start")" == "$(proc_field "$pid" start)" ]] || continue
    [[ -n "$hit" ]] && return 1 # two live processes on one session
    hit=$pid
  done
  [[ -n "$hit" ]] && echo "$hit"
}

# The transcript of session SID, or empty.
transcript_for() {
  local f
  for f in "$CFG"/projects/*/"$1".jsonl; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

# Run CMD in its own process group, so Ctrl-C or HUP sent to the worker's pane
# can't cut it halfway (then nobody knows whether its keys arrived). Output goes
# to $LOG. Returns CMD's exit status. Job control is on only while CMD starts:
# left on, the foreground commands get their own group and Ctrl-C misses the worker's trap.
run_detached() {
  local p
  set -m; "$@" </dev/null >>"$LOG" 2>&1 & p=$!; set +m
  while kill -0 "$p" 2>/dev/null; do wait "$p"; done # a trap cuts wait short: wait again
  wait "$p" # gone now; bash still has its exit status
}

#!/usr/bin/env bash
# Self-check for restart-lib.sh against a fake world: fake tmux, herdr, ps, clock and sleep,
# and a fake config dir. Nothing real is touched: no ~/.claude, no real panes or processes.
# Run: bash plugins/kit-update/scripts/restart-all.test.sh
#
# The fake world, for the sections below:
#   $FAKE/procs   one row per process, tab-separated: pid ppid pgid tpgid tty lstart args
#                 (fake_proc adds a row, fake_kill removes it; the fake ps reads it)
#   $FAKE/now     the clock in epoch seconds, from 1000000; fake sleep N adds N to it
#   $FAKE/cfg     CLAUDE_CONFIG_DIR: sessions/<pid>.json (fake_session), projects/<dir>/<sid>.jsonl
#   $FAKE/panes, $FAKE/agents             what the fake tmux list-panes / herdr agent list print
#   $FAKE/tmux-calls, $FAKE/herdr-calls   every call to the fake tmux / herdr, one per line
#   KIT_FAKE_REAL_SLEEP=<seconds>         real time each fake sleep takes (default 0.01)

set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FAKE=$(mktemp -d "${TMPDIR:-/tmp}/kit-restart-test.XXXXXX")
trap 'rm -rf "$FAKE"' EXIT
mkdir -p "$FAKE/bin" "$FAKE/cfg/sessions"
echo 1000000 >"$FAKE/now"
: >"$FAKE/procs"

cat >"$FAKE/bin/ps" <<'EOF'
#!/usr/bin/env bash
# fake ps: rows from $FAKE/procs, in columns like macOS ps; answers only the forms restart-lib.sh uses
case "$*" in
  "-o pid=,ppid=,pgid=,tpgid=,tty=,lstart=,args= -p "*)
    [[ "${TZ:-}" == UTC ]] || { echo "fake ps: lstart without TZ=UTC won't match procStart" >&2; exit 2; }
    awk -F'\t' -v p="$4" '$1 == p { printf "%5s %5s %5s %5s %-8s %s     %s\n", $1, $2, $3, $4, $5, $6, $7; n++ }
      END { exit !n }' "$FAKE/procs" ;;
  "-A -o pid=,ppid=,args=") awk -F'\t' '{ printf "%5s %5s %s\n", $1, $2, $7 }' "$FAKE/procs" ;;
  *) echo "fake ps: unexpected arguments: $*" >&2; exit 2 ;;
esac
EOF
cat >"$FAKE/bin/clock" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE/now"
EOF
cat >"$FAKE/bin/sleep" <<'EOF'
#!/usr/bin/env bash
# fake sleep N: moves the fake clock on by N seconds, then sleeps a little for real
echo $(($(cat "$FAKE/now") + $1)) >"$FAKE/now"
sleep "${KIT_FAKE_REAL_SLEEP:-0.01}"
EOF
cat >"$FAKE/bin/tmux" <<'EOF'
#!/usr/bin/env bash
# fake tmux: calls logged to $FAKE/tmux-calls; no $FAKE/panes means no server
echo "$*" >>"$FAKE/tmux-calls"
case "$1" in
  list-panes) [[ -f "$FAKE/panes" ]] && cat "$FAKE/panes" ;;
esac
EOF
cat >"$FAKE/bin/herdr" <<'EOF'
#!/usr/bin/env bash
# fake herdr: calls logged to $FAKE/herdr-calls; no $FAKE/agents means no server
echo "$*" >>"$FAKE/herdr-calls"
case "$1 ${2:-}" in
  "agent list") [[ -f "$FAKE/agents" ]] && cat "$FAKE/agents" ;;
esac
EOF
chmod +x "$FAKE"/bin/*
export FAKE CLAUDE_CONFIG_DIR="$FAKE/cfg" \
  KIT_UPDATE_TMUX_BIN="$FAKE/bin/tmux" KIT_UPDATE_HERDR_BIN="$FAKE/bin/herdr" KIT_UPDATE_PS_BIN="$FAKE/bin/ps" \
  KIT_UPDATE_CLOCK_BIN="$FAKE/bin/clock" KIT_UPDATE_SLEEP_BIN="$FAKE/bin/sleep"

fails=0
check() { # $1 = label, $2 = condition result
  if [[ "$2" == 0 ]]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

# lstart of a fake process; the double space before a one-digit day is how ps prints it
fake_lstart() { printf 'Thu Oct  2 07:43:%02d 2026' $(($1 % 60)); }
fake_proc() { # PID PPID PGID TPGID TTY ARGS
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$(fake_lstart "$1")" "$6" >>"$FAKE/procs"
}
fake_kill() { awk -F'\t' -v p="$1" '$1 != p' "$FAKE/procs" >"$FAKE/procs.new" && mv "$FAKE/procs.new" "$FAKE/procs"; }
fake_session() { # PID SID NAME STATUS CWD; procStart matches fake_proc PID
  jq -n --argjson pid "$1" --arg sid "$2" --arg name "$3" --arg status "$4" --arg cwd "$5" \
    --arg start "$(fake_lstart "$1")" --argjson at "$(($(cat "$FAKE/now") * 1000))" \
    '{pid: $pid, sessionId: $sid, name: $name, version: "2.1.309", status: $status,
      statusUpdatedAt: $at, kind: "interactive", procStart: $start, cwd: $cwd}' \
    >"$CLAUDE_CONFIG_DIR/sessions/$1.json"
}

source "$here/restart-lib.sh"
ku_paths

# --- restart-lib: paths, clock, log
[[ "$LOG $LOCK $HANDOFFS" == "$FAKE/cfg/kit-update/restart.log $FAKE/cfg/kit-update/restart.lock $FAKE/cfg/kit-update/handoffs" ]]
check "ku_paths: restart's files live under CLAUDE_CONFIG_DIR/kit-update" $?
[[ "$TMUX_BIN $HERDR_BIN $PS_BIN" == "$FAKE/bin/tmux $FAKE/bin/herdr $FAKE/bin/ps" ]]; check "ku_paths: test overrides for the binaries" $?
[[ ! -e "$KU_DIR" ]]; check "sourcing and ku_paths create nothing" $?
ku_nap 30; [[ "$(ku_now)" == 1000030 ]]; check "fake sleep moves the fake clock" $?

mkdir -p "$KU_DIR"
out=$(ku_log alpha 'exited')
re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  alpha — exited$'
[[ "$out" =~ $re ]]; check "ku_log line format" $?
[[ "$(cat "$LOG")" == "$out" ]]; check "ku_log appends the same line to the log" $?

# --- restart-lib: processes
fake_proc 101 100 101 101 ttys001 claude
[[ "$(proc_field 101 start)" == "Thu Oct 2 07:43:41 2026" ]]; check "lstart collapsed" $?
[[ "$(proc_field 101 ppid) $(proc_field 101 tty) $(proc_field 101 args)" == "100 ttys001 claude" ]]; check "proc_field ppid, tty, args" $?
proc_foreground 101; check "foreground when pgid = tpgid" $?
fake_proc 102 100 102 999 ttys002 claude; ! proc_foreground 102; check "suspended is not foreground" $?
fake_kill 102; ! proc_alive 102 && ! proc_foreground 102 && [[ -z "$(proc_field 102 tty)" ]]
check "a gone pid: not alive, not foreground, no fields" $?
for a in '-zsh' '/opt/homebrew/bin/zsh' 'zsh -l' 'bash'; do shell_ok "$a"; check "shell ok: $a" $?; done
for a in 'bash -lc x' 'zsh -ic x' 'zsh -c x' 'sh -c x' 'fish' '/bin/sh' ''; do ! shell_ok "$a"; check "shell not ok: $a" $?; done

fake_proc 301 101 301 101 ttys001 "/bin/zsh -c source $CFG/shell-snapshots/snapshot-zsh-1-x.sh && eval 'sleep 300'"
fake_proc 302 101 101 101 ttys001 "npm exec @playwright/mcp@latest"
fake_proc 303 101 303 101 ttys001 "caffeinate -i -t 300"
[[ "$(proc_field 301 args)" == "/bin/zsh -c source $CFG/shell-snapshots/snapshot-zsh-1-x.sh && eval 'sleep 300'" ]]
check "proc_field args keeps the whole command line" $?
[[ "$(proc_children 101 | cut -d' ' -f1 | tr '\n' ' ')" == "301 302 303 " ]]; check "proc_children lists direct children only" $?
[[ "$(bg_shells 101)" == 301 ]]; check "bg_shells finds the Bash shell, not the MCP server" $?

# --- restart-lib: session files and transcripts
# S1: a stale file of a dead pid, a live pid whose procStart differs (pid reused), and the right one
fake_session 200 S1 alpha idle /x/alpha
fake_proc 201 1 201 201 ttys003 claude; fake_session 201 S1 alpha idle /x/alpha
fake_proc 202 1 202 202 ttys004 claude; fake_session 202 S1 alpha idle /x/alpha
jq '.procStart = "Wed Oct  1 01:02:03 2026"' "$(sf_path 202)" >"$FAKE/s.json" && mv "$FAKE/s.json" "$(sf_path 202)"
[[ "$(pid_for_sid S1)" == 201 ]]; check "pid_for_sid picks the live, matching file" $?
fake_proc 211 1 211 211 ttys005 claude; fake_session 211 S2 beta idle /x/beta
fake_proc 212 1 212 212 ttys006 claude; fake_session 212 S2 beta idle /x/beta
[[ -z "$(pid_for_sid S2)" ]]; check "pid_for_sid: two live matches is ambiguous" $?
[[ -z "$(pid_for_sid S9)" ]]; check "pid_for_sid: no match is empty" $?
[[ "$(sf_get 201 name) $(sf_get 201 cwd) $(sf_get 201 kind)" == "alpha /x/alpha interactive" ]]; check "sf_get reads a field" $?
[[ -z "$(sf_get 201 nothing)$(sf_get 999 name)" ]]; check "sf_get: missing field or file is empty" $?
mkdir -p "$CFG/projects/-x-alpha"; : >"$CFG/projects/-x-alpha/S1.jsonl"
[[ "$(transcript_for S1)" == "$CFG/projects/-x-alpha/S1.jsonl" && -z "$(transcript_for S9)" ]]
check "transcript_for finds the file by session id" $?

# --- restart-lib: run_detached (runs real sh and ps, on this test's own children only)
run_detached sh -c 'exit 3'; [[ $? == 3 ]]; check "run_detached returns the command's status" $?
run_detached sh -c 'echo "pgid $(ps -o pgid= -p $$)"'
child=$(awk '$1 == "pgid" { print $2 }' "$LOG")
[[ -n "$child" ]] && ((child != $(ps -o pgid= -p $$))); check "run_detached: own process group, output to the log" $?
trap 'echo USR1 >>"$FAKE/trapped"' USR1
(sleep 0.2 && kill -USR1 $$) &
run_detached sh -c 'sleep 0.6; exit 4'; [[ $? == 4 && -s "$FAKE/trapped" ]]
check "run_detached waits again after a trap cuts wait short" $?
trap - USR1

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"

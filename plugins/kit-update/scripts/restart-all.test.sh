#!/usr/bin/env bash
# Self-check for restart-lib.sh and restart-all.sh against a fake world: fake tmux, herdr, ps, clock and sleep,
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
#   $FAKE/workspaces                      what the fake herdr workspace list prints
#   $FAKE/tmux-sessions                   tmux session names that exist (has-session, new-session)
#   $FAKE/ran         "<pane or session> <command>" per herdr pane run / tmux send-keys -l
#   $FAKE/fail-launch                     makes herdr workspace create and tmux new-session fail
#   $FAKE/hook-<cmd>                      sourced by the fake tmux before it answers <cmd>
#   $FAKE/hook-ps                         sourced by the fake ps before it answers (remove it inside to run once)
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
[[ -f "$FAKE/hook-ps" ]] && . "$FAKE/hook-ps"
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
[[ "${1:-}" == -S ]] && shift 2
[[ -f "$FAKE/hook-$1" ]] && . "$FAKE/hook-$1" # a test's side effect for this command
case "$1" in
  list-panes) [[ -f "$FAKE/panes" ]] && cat "$FAKE/panes" ;;
  has-session) grep -qxF "${3#=}" "$FAKE/tmux-sessions" 2>/dev/null ;;
  new-session) # new-session -d -s NAME -c DIR
    [[ ! -f "$FAKE/fail-launch" ]] && ! grep -qxF "$4" "$FAKE/tmux-sessions" 2>/dev/null && echo "$4" >>"$FAKE/tmux-sessions" ;;
  send-keys) [[ "$4" == -l ]] && echo "$3 $5" >>"$FAKE/ran" ;; # send-keys -t TARGET -l TEXT ...
esac
EOF
cat >"$FAKE/bin/herdr" <<'EOF'
#!/usr/bin/env bash
# fake herdr: calls logged to $FAKE/herdr-calls; no $FAKE/agents means no server
echo "$*" >>"$FAKE/herdr-calls"
case "$1 ${2:-}" in
  "agent list") [[ -f "$FAKE/agents" ]] && cat "$FAKE/agents" ;;
  "workspace list") [[ -f "$FAKE/workspaces" ]] && cat "$FAKE/workspaces" ;;
  "workspace create") [[ ! -f "$FAKE/fail-launch" ]] \
    && echo '{"result":{"workspace":{"workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1"}}}' ;;
  "pane run") echo "$3 $4" >>"$FAKE/ran" ;;
esac
EOF
chmod +x "$FAKE"/bin/*
unset HERDR_ENV HERDR_PANE_ID TMUX TMUX_PANE # the multiplexer this test runs in must not leak into the runs below
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
for a in 'bash -lc x' 'zsh -ic x' 'zsh -c x' 'sh -c x' 'fish' '/bin/sh' '' 'bash foo.sh' 'zsh script.zsh'; do ! shell_ok "$a"; check "shell not ok: $a" $?; done

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

# --- restart-lib: transcript reading
# j_* print one transcript line each (j_routine prints several), shaped like Claude Code 2.1.309's.
j_prompt() { jq -nc --arg t "$1" '{type: "user", message: {role: "user", content: $t}}'; }
j_queued() { # MODE TEXT; MODE = prompt (typed while busy) | task-notification (start of session)
  jq -nc --arg m "$1" --arg t "$2" '{type: "attachment", attachment: ({type: "queued_command", prompt: $t, commandMode: $m}
    + if $m == "task-notification" then {isMeta: true} else {humanTurn: true} end)}'
}
j_asst() { # ID STOP KIND [TEXT]; STOP null = interrupted; KIND = text | thinking | tool_use
  jq -nc --arg id "$1" --arg stop "$2" --arg kind "$3" --arg t "${4:-}" '{type: "assistant", message: {id: $id, model: "claude-x",
    content: [if $kind == "text" then {type: "text", text: $t} elif $kind == "thinking" then {type: "thinking", thinking: $t}
      else {type: "tool_use", name: "Bash", input: {}} end],
    stop_reason: (if $stop == "null" then null else $stop end)}}'
}
j_synthetic() {
  jq -nc '{type: "assistant", isApiErrorMessage: true, message: {id: "x", model: "<synthetic>",
    content: [{type: "text", text: "API Error: 529 overloaded"}], stop_reason: "stop_sequence"}}'
}
j_interrupt() { jq -nc '{type: "user", message: {content: [{type: "text", text: "[Request interrupted by user]"}]}}'; }
j_routine() { # what follows a normal turn
  jq -nc '{type: "system", subtype: "turn_duration"}, {type: "attachment", attachment: {type: "total_tokens_reminder"}},
    {type: "attachment", attachment: {type: "prompt_snapshot"}}, {type: "file-history-snapshot"}, {type: "last-prompt"},
    {type: "custom-title"}, {type: "permission-mode"}'
}
T=$FAKE/t.jsonl OUT=$FAKE/handoff.md
ASK='[kit-update restart N1] ตอบเป็น handoff ของงานใน session นี้'
H=$'## เป้าหมาย\nลองระบบ\n## ทำเสร็จแล้ว\n- a\n## ค้างอยู่ตรงไหน\n- b\n## ตัดสินใจอะไรไปแล้วและเพราะอะไร\n- c\n## ไฟล์ที่เกี่ยวข้อง\n- /x/alpha/a.sh\n## ขั้นต่อไป\n- d'
expect() { # LABEL VERDICT [DETAIL] [IDLE]: answer_state of all of $T with nonce N1; OUT is written on handoff only
  local v e d
  rm -f "$OUT"
  IFS=$'\t' read -r v e d < <(answer_state "$T" 0 N1 "${4:-1}" "$OUT")
  [[ "$v" == "$2" && "$d" == "${3:-}" && "$e" == "$(($(wc -c <"$T")))" && ("$v" == handoff || ! -e "$OUT") ]]
  check "$1" $?
}

{ j_prompt "$ASK"; j_asst m1 end_turn thinking 'คิดก่อน'; j_asst m1 end_turn text "$H"; } >"$T"
expect "handoff: thinking + text of one message" handoff
[[ "$(cat "$OUT")" == "$H" ]]; check "handoff: OUT holds the text, not the thinking" $?
{ j_prompt $'\n\n<pasted_content id="5444">\n'"$ASK"; j_asst m1 end_turn text "$H"; } >"$T"
expect "handoff: nonce entry wrapped in pasted_content" handoff
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; j_routine; j_prompt $'<task-notification>\n<task-id>b1</task-id>'; } >"$T"
expect "stale: task notification as a user string after the answer" stale 'prompt after the request'
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; j_routine; } >"$T"
expect "handoff: routine entries after are ignored" handoff
{ j_prompt "$ASK"; j_queued task-notification '<task-notification>a'; j_queued task-notification '<task-notification>b'
  j_asst m1 end_turn text "$H"; } >"$T"
expect "handoff: start-of-session task notifications before the answer" handoff
for a in 'plain|NOT-READY: bg job' '**|**NOT-READY:** bg job' 'backtick|`NOT-READY`: bg job' $'leading spaces|  \n NOT-READY: bg job'; do
  { j_prompt "$ASK"; j_asst m1 end_turn text "${a#*|}"; } >"$T"
  expect "not-ready: ${a%%|*}" not-ready 'bg job'
done
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"$'\nเกือบตอบ NOT-READY แล้ว แต่งานจบก่อน'; } >"$T"
expect "handoff mentioning NOT-READY inside" handoff

{ j_prompt "$ASK"; j_asst m1 tool_use tool_use; } >"$T"
expect "invalid: tool_use" invalid 'tool call'
{ j_prompt "$ASK"; j_asst m1 tool_use tool_use
  jq -nc '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "x", content: "ok"}]}}'
  j_asst m2 end_turn text "$H"; } >"$T"
expect "invalid: tool call before a valid-looking handoff" invalid 'tool call'
{ j_prompt "$ASK"; j_synthetic; } >"$T"
expect "invalid: api error" invalid 'api error'
{ j_prompt "$ASK"; j_asst m1 max_tokens text "$H"; } >"$T"
expect "invalid: max_tokens" invalid 'stop_reason max_tokens'
{ j_prompt "$ASK"; j_asst m1 end_turn text $'## เป้าหมาย\n## ทำเสร็จแล้ว\n## ตัดสินใจ\n## ขั้นต่อไป'; } >"$T"
expect "invalid: missing heading" invalid 'missing headings: ค้าง, ไฟล์'

{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; j_prompt 'อีกเรื่อง'; } >"$T"
expect "stale: prompt after answer" stale 'prompt after the request'
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; j_asst m2 end_turn text 'อีกข้อความ'; } >"$T"
expect "stale: assistant message after answer" stale 'message after the answer'
{ j_prompt "$ASK"; j_queued prompt 'แก้ตรงนี้ด้วย'; j_asst m1 end_turn text "$H"; } >"$T"
expect "stale: queued prompt before answer" stale 'prompt after the request'
{ j_prompt "$ASK"; j_asst m1 end_turn thinking 'คิดก่อน'; j_queued task-notification '<task-notification>a'
  j_asst m1 end_turn text "$H"; } >"$T"
expect "stale: task notification after the answer started" stale 'prompt after the request'
{ j_prompt "$ASK"; j_asst m1 null text "$H"; } >"$T"
expect "stale: interrupted (stop_reason null)" stale interrupted
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; j_interrupt; } >"$T"
expect "stale: interrupted ([Request interrupted by user])" stale interrupted
{ j_queued prompt "$ASK"; j_asst m1 end_turn text "$H"; } >"$T"
expect "stale: nonce entry is queued" stale 'request queued'

{ jq -nc --arg t "$ASK" '{type: "api-request-blob", messages: [{role: "user", content: $t}]}'
  jq -nc --arg t "$ASK" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: "x", content: $t}]}}'
  j_asst m1 end_turn text "$H"; } >"$T"
expect "no-nonce: nonce only inside api-request-blob or a tool_result" no-nonce
{ j_prompt "${ASK/N1/N0}"; j_asst m1 end_turn text "$H"; } >"$T"
expect "no-nonce: other nonce" no-nonce
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; } >"$T"
expect "pending: answer ended but pane not idle" pending '' 0
{ j_prompt "$ASK"; j_queued task-notification '<task-notification>a'; } >"$T"
expect "pending: no answer yet" pending

# a complete prompt still missing its \n: it would make the answer stale if it were read
part=$(j_prompt 'พิมพ์ต่อ')
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; printf '%s' "$part"; } >"$T"
IFS=$'\t' read -r v e d < <(answer_state "$T" 0 N1 1 "$OUT")
[[ "$v" == handoff && "$e" == $(($(wc -c <"$T") - $(printf '%s' "$part" | wc -c))) ]]
check "partial last line: ignored, end offset before it" $?
{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; } >"$T"
off=$(($(wc -c <"$T")))
{ j_prompt 'อีกเรื่อง'; j_asst m2 end_turn text 'ตอบ'; } >>"$T"
IFS=$'\t' read -r v e d < <(answer_state "$T" "$off" N1 1 "$OUT")
[[ "$v" == no-nonce && "$e" == $(($(wc -c <"$T"))) ]]; check "offset in the middle: earlier nonce is not seen" $?

{ j_prompt "$ASK"; j_asst m1 end_turn text "$H"; } >"$T.base"
off=$(($(wc -c <"$T.base")))
{ cat "$T.base"; j_routine; } >"$T"
! activity_after "$T" "$off"; check "activity_after: routine only" $?
for a in prompt queued assistant; do
  { cat "$T.base"; j_routine
    case $a in prompt) j_prompt 'ต่อ' ;; queued) j_queued prompt 'ต่อ' ;; assistant) j_asst m2 end_turn text 'ต่อ' ;; esac; } >"$T"
  activity_after "$T" "$off"; check "activity_after: $a" $?
done

# --- restart-all.sh: snapshot, state file, lock and worker launch
# The worker is never run: the fake pane run and send-keys only record its command line in $FAKE/ran.
reset_world() {
  rm -rf "${CFG:?}/sessions" "${KU_DIR:?}" "${FAKE:?}"/{panes,agents,workspaces,tmux-calls,herdr-calls,ran,tmux-sessions,fail-launch,hook-list-panes,hook-ps}
  mkdir -p "$CFG/sessions"
  : >"$FAKE/procs"
}
ra() { /bin/bash "$here/restart-all.sh" 2>&1; }
ra_as() { # PPID: run restart-all.sh as a process the fake ps knows, whose parent is PPID (exec keeps the pid)
  sh -c 'printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" $$ "$1" $$ $$ "??" "Thu Oct  2 07:43:00 2026" "bash restart-all.sh" >>"$FAKE/procs"
    exec /bin/bash "$2"' sh "$1" "$here/restart-all.sh" 2>&1
}
agent() { # PANE NAME|null WORKSPACE SID: one entry of herdr agent list
  printf '{"pane_id":"%s","name":%s,"agent":"claude","agent_status":"idle","cwd":"/x","workspace_id":"%s","agent_session":{"value":"%s"}}' "$@"
}
agents() { local IFS=,; printf '{"result":{"agents":[%s]}}\n' "$*" >"$FAKE/agents"; }
tpane() { printf '%s\t%s\t%s\n' "$@" >>"$FAKE/panes"; } # PANE_ID SESSION:WINDOW.PANE PANE_PID
sf_set() { jq "$2" "$(sf_path "$1")" >"$FAKE/s.json" && mv "$FAKE/s.json" "$(sf_path "$1")"; } # PID JQ_PROGRAM
state() { echo "$LOCK/state.$(lock_token)"; }
row() { awk -F'\t' -v p="$1" '$1 == "pane" && $5 == p' "$(state)" 2>/dev/null; } # the state row of Claude PID
launches() { cat "$FAKE/ran" 2>/dev/null | wc -l | tr -d ' '; }

reset_world
out=$(ra)
grep -q 'No tmux or herdr server' <<<"$out" && [[ ! -e "$LOCK" ]]; check "no server: says so, no lock left" $?

# One world for the snapshot rules: herdr agents w1:p1-p6, tmux panes %1-%8 on server 130.
reset_world
echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"alpha work"},{"workspace_id":"w2","label":"beta"}]}}' >"$FAKE/workspaces"
fake_proc 100 1 100 101 ttys001 -zsh # w1:p1: Claude 101 under a login shell; its Bash tool shell 102 runs the script
fake_proc 101 100 101 101 ttys001 'claude --name alpha'; fake_session 101 S1 alpha idle /x/alpha
fake_proc 102 101 102 101 ttys001 "/bin/zsh -c source $CFG/shell-snapshots/snapshot-zsh-1-x.sh && eval 'bash restart-all.sh'"
fake_proc 110 1 110 111 ttys002 'zsh -ic claude' # w1:p2: Claude under zsh -ic
fake_proc 111 110 111 111 ttys002 claude; fake_session 111 S2 beta idle /x/beta
fake_proc 130 1 130 0 '??' 'tmux new -s main' # the tmux server
fake_proc 131 130 131 132 ttys003 -zsh # %1, which herdr also lists as w1:p3
fake_proc 132 131 132 132 ttys003 claude; fake_session 132 S3 gamma idle /x/gamma
fake_proc 140 1 140 141 ttys004 -zsh # w1:p4 and %2 both run session S5
fake_proc 141 140 141 141 ttys004 'claude --continue'; fake_session 141 S5 delta idle /x/delta
fake_proc 142 130 142 143 ttys005 -zsh
fake_proc 143 142 143 143 ttys005 'claude --continue'; fake_session 143 S5 delta idle /x/delta
fake_proc 151 130 151 151 ttys006 'claude -p hi'; fake_session 151 S6 eps busy /x/eps; sf_set 151 '.kind = "sdk-cli"' # %3
fake_proc 160 1 160 161 ttys007 -zsh # w1:p5: a session file without status
fake_proc 161 160 161 161 ttys007 claude; fake_session 161 S7 zeta idle /x/zeta; sf_set 161 'del(.status)'
fake_proc 171 130 171 172 ttys008 'node /x/wrap.js' # %4: Claude under a wrapper
fake_proc 172 171 172 172 ttys008 claude; fake_session 172 S8 eta idle /x/eta
fake_proc 181 130 181 181 ttys009 'claude --team-name t1'; fake_session 181 S9 t1 idle /x/team # %5-%7: teammates
fake_proc 182 130 182 182 ttys010 'claude --agent-id a1@t1'; fake_session 182 S10 t1 idle /x/team
fake_proc 183 130 183 183 ttys011 'claude --parent-session-id S0'; fake_session 183 S11 t1 idle /x/team
fake_proc 191 130 191 191 ttys012 'claude --name theta'; fake_session 191 S12 theta idle /x/theta # %8: Claude is the pane process
fake_proc 200 1 200 0 '??' 'tmux -L other new' # w1:p6: inside a tmux server that is not listed
fake_proc 201 200 201 202 ttys013 zsh
fake_proc 202 201 202 202 ttys013 claude; fake_session 202 S13 iota idle /x/iota
agents "$(agent w1:p1 '"alpha"' w1 S1)" "$(agent w1:p2 null w2 S2)" "$(agent w1:p3 null w1 S3)" \
  "$(agent w1:p4 null w1 S5)" "$(agent w1:p5 null w1 S7)" "$(agent w1:p6 null w1 S13)"
tpane %1 main:0.0 131; tpane %2 main:0.1 142; tpane %3 main:0.2 151; tpane %4 main:0.3 171
tpane %5 main:1.0 181; tpane %6 main:1.1 182; tpane %7 main:1.2 183; tpane %8 main:2.0 191

out=$(HERDR_ENV=1 ra_as 102)
[[ "$(row 101 | cut -f3)" == w1:p1 ]]; check "herdr: pid found through agent_session and session file" $?
[[ -z "$(row 111)" ]] && grep -q '^  - beta (herdr w1:p2) — .*zsh -ic claude' <<<"$out"; check "herdr: parent shell zsh -ic is skipped" $?
[[ "$(row 101 | cut -f8)" == 100 ]]; check "herdr: login shell -zsh is kept" $?
[[ "$(awk -F'\t' '$5 == 132 { print $2, $3 }' "$(state)")" == "tmux %1" ]] && ! grep -q 'w1:p3' <<<"$out"
check "tmux in herdr: kept once, on the tmux side" $?
[[ -z "$(row 141)$(row 143)" ]] && grep -q '(tmux main:0.1) — ' <<<"$out" && grep -q '(herdr w1:p4) — ' <<<"$out"
check "two live processes share a sessionId: both skipped" $?
[[ -z "$(row 151)" ]] && grep -q '(tmux main:0.2) — not interactive' <<<"$out"; check "kind not interactive: skipped" $?
[[ -z "$(row 161)" ]] && grep -q '(herdr w1:p5) — .*status' <<<"$out"; check "session file missing status: skipped" $?
[[ -z "$(row 172)" ]] && grep -q '(tmux main:0.3) — .*wrapper' <<<"$out"; check "tmux wrapper process: skipped" $?
[[ -z "$(row 181)$(row 182)$(row 183)" && "$(grep -c 'teammate' <<<"$out")" == 3 ]]; check "teammate: skipped" $?
[[ -z "$(row 202)" ]] && grep -q '(herdr w1:p6) — .*tmux' <<<"$out"
check "herdr agent with tmux ancestor not in the tmux list: still dropped" $?
grep -qx 'This session: in the snapshot, goes last' <<<"$out" \
  && [[ "$(awk -F'\t' '$1 == "pane" { printf "%s:%s ", $5, $13 }' "$(state)")" == "132:0 191:0 101:1 " ]]
check "issuer found through the ppid chain" $?
want=$(printf '%s\t' pane herdr w1:p1 'alpha work' 101 'Thu Oct  2 07:43:41 2026' ttys001 100 S1 alpha 2.1.309 /x/alpha 1 alpha)
[[ "$(row 101)" == "$want"'claude --name alpha' ]]; check "state rows carry every field" $?
want=$(printf '%s\t' pane tmux %8 main:2.0 191 'Thu Oct  2 07:43:11 2026' ttys012 - S12 theta 2.1.309 /x/theta 0 '')
[[ "$(row 191)" == "$want"'claude --name theta' && "$(row 132 | cut -f4,8)" == $'main:0.0\t131' ]]
check "tmux rows: session:window.pane label, the pane's shell or - as shell pid" $?
grep -qx 'Restarting 3 session(s) when idle:' <<<"$out" && grep -qx '  - alpha (herdr w1:p1)' <<<"$out" \
  && grep -qx '  - gamma (tmux main:0.0)' <<<"$out" && grep -qx "Log: $LOG" <<<"$out" && grep -qx "Handoffs: $HANDOFFS" <<<"$out" \
  && [[ -d "$HANDOFFS" ]]
check "output: who restarts, the log and the handoffs folder" $?
t=$(date -r "$(cat "$FAKE/now")" +%H%M%S)
line=$(cat "$FAKE/ran" 2>/dev/null); cmd=${line#w9:p1 }
[[ "$(launches)" == 1 && "$line" == "w9:p1 "* && "$cmd" == "bash $here/restart-worker.sh $(state)" ]] \
  && (($(printf '%s' "$cmd" | wc -c) <= 1024)) && [[ -f "$(state)" && -f "$here/restart-worker.sh" ]] \
  && grep -qxF "workspace create --label kit-update restart $t --no-focus" "$FAKE/herdr-calls" \
  && [[ "$(sed -n 1,3p "$(state)")" == $'config\t'"$CFG"$'\nsocket\t\nmux\therdr' ]] \
  && grep -qx 'Worker: w9:p1' <<<"$out" && ! grep -q new-session "$FAKE/tmux-calls"
check "launch in herdr when HERDR_ENV is set" $?

rm -rf "${LOCK:?}" "${FAKE:?}/ran"
out=$(ra)
grep -qx 'This session: not found — restart it yourself' <<<"$out" && [[ "$(row 101 | cut -f13)" == 0 ]]
check "issuer not in snapshot: says so" $?

# The rest: one Claude pane in tmux. The fake clock is at the real time, so a lock made now is fresh.
lock_world() {
  reset_world
  fake_proc 130 1 130 0 '??' 'tmux new -s main'; fake_proc 131 130 131 132 ttys003 -zsh
  fake_proc 132 131 132 132 ttys003 claude; fake_session 132 S3 gamma idle /x/gamma
  tpane %1 main:0.0 131
  date +%s >"$FAKE/now"
}
old_lock() { touch -t 202001010000 "$LOCK"; } # mtime far older than 60 s

lock_world
out=$(TMUX="$FAKE/sock,1,0" ra)
grep -q "^-S $FAKE/sock new-session -d -s kit-update-restart-[0-9]\{6\} -c $KU_DIR\$" "$FAKE/tmux-calls" \
  && grep -q "^-S $FAKE/sock send-keys -t kit-update-restart-[0-9]\{6\} -l bash .* ; send-keys -t kit-update-restart-[0-9]\{6\} Enter\$" "$FAKE/tmux-calls" \
  && [[ "$(sed -n 2,3p "$(state)")" == $'socket\t'"$FAKE/sock"$'\nmux\ttmux' && "$(launches)" == 1 ]]
check "launch in tmux when only TMUX is set" $?
lock_world
out=$(ra)
grep -q '^new-session -d -s kit-update-restart-' "$FAKE/tmux-calls" && ! grep -q 'workspace create' "$FAKE/herdr-calls" \
  && [[ "$(sed -n 2,3p "$(state)")" == $'socket\t\nmux\ttmux' ]]
check "neither HERDR_ENV nor TMUX: uses the multiplexer that has a server" $?
lock_world
t=$(date -r "$(cat "$FAKE/now")" +%H%M%S); echo "kit-update-restart-$t" >"$FAKE/tmux-sessions"
out=$(ra)
grep -qxF "new-session -d -s kit-update-restart-$t-2 -c $KU_DIR" "$FAKE/tmux-calls" && grep -qx "Worker: kit-update-restart-$t-2" <<<"$out"
check "second run while previous worker pane is open" $?

lock_world
mkdir -p "$LOCK"; printf 'TOKW 555 w8:p2\ncmd bash /x/restart-worker.sh /x/state.TOKW\n' >"$LOCK/owner"
fake_proc 555 1 555 555 ttys020 'bash /x/restart-worker.sh /x/state.TOKW'
out=$(ra)
[[ "$(launches)" == 0 && "$(lock_token)" == TOKW ]] && grep -q 'w8:p2' <<<"$out"; check "running worker: reports its pane, no second launch" $?
lock_world
mkdir -p "$LOCK"; echo 'starting TOKS' >"$LOCK/owner"
out=$(ra)
[[ "$(launches)" == 0 && "$(lock_token)" == TOKS ]] && grep -q 'starting' <<<"$out"; check "fresh starting lock: no launch" $?
lock_world
mkdir -p "$LOCK"
out=$(ra)
[[ "$(launches)" == 0 && -d "$LOCK" && ! -e "$LOCK/owner" ]]; check "empty lock dir under 60s: no launch" $?
lock_world
mkdir -p "$LOCK"; printf 'TOKD 556 w8:p3\ncmd bash /x/restart-worker.sh /x/state.TOKD\n' >"$LOCK/owner"
out=$(ra); tok=$(lock_token)
[[ "$(launches)" == 1 && -n "$tok" && "$tok" != TOKD && -f "$LOCK/state.$tok" ]]; check "dead worker pid: takes over" $?
lock_world
mkdir -p "$LOCK"; printf 'TOKR 557 w8:p4\ncmd bash /x/restart-worker.sh /x/state.TOKR\n' >"$LOCK/owner"
fake_proc 557 1 557 557 ttys021 'vim notes.txt'
out=$(ra); tok=$(lock_token)
[[ "$(launches)" == 1 && "$tok" != TOKR ]]; check "worker pid reused by another command: takes over" $?
lock_world
mkdir -p "$LOCK"; echo 'starting TOKO' >"$LOCK/owner"; old_lock
out=$(ra); tok=$(lock_token)
[[ "$(launches)" == 1 && "$tok" != TOKO && -f "$LOCK/state.$tok" ]]; check "starting older than 60s: takes over" $?
lock_world
mkdir -p "$LOCK"; echo 'starting TOKO' >"$LOCK/owner"; old_lock
ra >"$FAKE/out1" & ra >"$FAKE/out2" & wait
tok=$(lock_token); line=$(cat "$FAKE/ran" 2>/dev/null)
[[ "$(launches)" == 1 && -n "$tok" && "${line##* }" == "$LOCK/state.$tok" && -f "$LOCK/state.$tok" ]]
check "two callers on a stale lock: exactly one launch, the winner's lock survives" $?
lock_world
echo "echo 'starting OTHER' >'$LOCK/owner'" >"$FAKE/hook-list-panes" # another caller takes the lock mid-snapshot
out=$(ra)
[[ "$(launches)" == 0 && "$(lock_token)" == OTHER ]] && ! ls "$LOCK"/state.* >/dev/null 2>&1 && grep -q 'lock' <<<"$out"
check "lost the lock after writing state: no launch" $?
lock_world
touch "$FAKE/fail-launch"
out=$(ra); rc=$?
[[ $rc == 1 && ! -e "$LOCK" && "$(launches)" == 0 ]] && grep -q 'Could not start the worker' <<<"$out"; check "launch fails: lock removed" $?

# A caller judged the lock stale, then another caller made a fresh one or its worker started,
# before the move: lock_takeover runs here as that delayed caller would, after the swap.
lock_world
mkdir -p "$LOCK"; echo 'starting FRESH' >"$LOCK/owner"
! lock_takeover LATE && [[ "$(lock_token)" == FRESH && ! -e "$LOCK.stale.LATE" ]]
check "takeover that moved a fresh lock: puts it back, no lock of its own" $?
lock_world
mkdir -p "$LOCK"; printf 'TOKW 558 w8:p5\ncmd bash /x/restart-worker.sh /x/state.TOKW\n' >"$LOCK/owner"
fake_proc 558 1 558 558 ttys022 'bash /x/restart-worker.sh /x/state.TOKW'
echo "rm -f '$FAKE/hook-ps'; mkdir '$LOCK'" >"$FAKE/hook-ps" # a third caller makes a new lock during the check
! lock_takeover LATE && [[ "$(head -1 "$LOCK.stale.LATE/owner")" == 'TOKW 558 w8:p5' && -d "$LOCK" && -z "$(ls -A "$LOCK")" ]]
check "takeover that moved a running worker's lock while a new one was made: leaves it aside, deletes nothing" $?
rm -rf "${LOCK:?}.stale.LATE"

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"

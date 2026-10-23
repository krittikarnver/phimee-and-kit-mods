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

((fails)) && { echo "$fails failed"; exit 1; }
echo "all passed"

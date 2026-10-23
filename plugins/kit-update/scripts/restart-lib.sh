#!/usr/bin/env bash
# kit-update restart-lib — process, session file, transcript and log helpers for restart.
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

# Run jq PROGRAM over transcript FILE after byte OFFSET. Only that tail is read: a
# transcript grows to MBs and is read every 10 s. The tail comes in raw (-Rs) so PROGRAM
# can count its bytes, and PROGRAM gets:
#   entries    the JSON objects on its complete lines (a half-written last line waits for the next read)
#   is_prompt  one entry is something sent to Claude: a user string that isn't meta, or a queued_command
#   ptext      that prompt's text
transcript_jq() { # FILE OFFSET PROGRAM [JQ OPTIONS...]
  local file=$1 off=$2 prog=$3
  shift 3 # not "${@:4}": bash 3.2 joins that into one word when IFS isn't the default
  tail -c +$((off + 1)) "$file" 2>/dev/null | jq -Rs "$@" '
    def entries: [split("\n")[:-1][] | fromjson? | objects];
    def is_prompt: (.type == "user" and (.message.content | type) == "string" and (.isMeta | not))
      or (.type == "attachment" and .attachment.type == "queued_command");
    def ptext: if .type == "user" then .message.content else .attachment.prompt end;
    '"$prog"
}

# Read Claude's answer to the request "[kit-update restart NONCE] ..." in FILE after byte
# OFFSET (spec §3 step 3). IDLE is 1 when the pane is idle now. Echoes VERDICT<TAB>END_OFFSET<TAB>DETAIL:
#   no-nonce   the request isn't in the transcript
#   pending    no answer yet, or it ended but the pane isn't idle yet (more of it may come)
#   stale      something else got in (a prompt, another message, an interrupt), or the request was queued
#   not-ready  Claude answered NOT-READY; DETAIL is its reason
#   handoff    a usable handoff; the answer's text is written to OUT
#   invalid    no handoff; DETAIL says why
# END_OFFSET is where the complete lines read end.
# The checks run in the spec's order. The answer is Claude's entries from the request to the
# end of the first message whose stop_reason isn't tool_use (one message spans several entries).
# shortcut: an OFFSET inside a multibyte character skews END_OFFSET (jq reads the cut bytes
# as U+FFFD). Callers pass line starts (the file size while idle, or an END_OFFSET); count
# the bytes outside jq if that changes.
answer_state() { # FILE OFFSET NONCE IDLE OUT
  local line
  transcript_jq "$1" "$2" '
    def has_tool: .message.stop_reason == "tool_use" or any(.message.content[]?; .type == "tool_use");
    def interrupt: .type == "user" and (.message.content | type) == "array"
      and any(.message.content[]; .type == "text" and (.text | startswith("[Request interrupted by user")));
    ($off + utf8bytelength - (split("\n") | last // "" | utf8bytelength)) as $end
    | entries as $e
    # a long request is stored wrapped: "\n\n<pasted_content id=\"5444\">\n[kit-update restart ..."
    | ([$e | to_entries[] | select(.value | is_prompt and (ptext | strings
        | sub("^\\s*<pasted_content id=\"[^\"]*\">\\s*"; "") | startswith($tag))) | .key] | first) as $n
    | if $n == null then ["no-nonce", ""]
      elif $e[$n].type == "attachment" then ["stale", "request queued"]
      else $e[$n + 1:] as $a
        | ([$a | to_entries[] | select(.value.type == "assistant") | .key] | first // ($a | length)) as $c1
        | [$a[] | select(.type == "assistant")] as $c
        | ([$c | to_entries[] | select(.value.message.stop_reason != "tool_use") | .key] | first) as $k
        | (if $k == null then $c else $c[:$k] + [$c[$k:][] | select(.message.id == $c[$k].message.id)] end) as $ans
        | (if $k == null then [] else [$c[$k + 1:][] | select(.message.id != $c[$k].message.id)] end) as $later
        | ($ans | map(.message.content[]? | select(.type == "text") | .text) | join("\n")) as $text
        | ($text | sub("^[\\s*`]+"; "")) as $bare
        | (["เป้าหมาย", "ทำเสร็จ", "ค้าง", "ตัดสินใจ", "ไฟล์", "ขั้นต่อไป"]
          | map(select(. as $h | $text | contains($h) | not))) as $missing
        # start-of-session task notifications come queued right after the first prompt, before the answer
        | if any($a | to_entries[]; (.value | is_prompt)
            and (.value.attachment.commandMode == "task-notification" and .key < $c1 | not))
          then ["stale", "prompt after the request"]
        elif any($ans[]; has_tool) then ["invalid", "tool call"]
        elif any($c[]; .message.stop_reason == null) or any($a[]; interrupt) then ["stale", "interrupted"]
        elif $k == null then ["pending", ""]
        elif $later != [] then ["stale", "message after the answer"]
        elif $idle != "1" then ["pending", ""]
        elif any($ans[]; .message.model == "<synthetic>" or .isApiErrorMessage) then ["invalid", "api error"]
        elif $c[$k].message.stop_reason != "end_turn" then ["invalid", "stop_reason \($c[$k].message.stop_reason)"]
        elif $bare | startswith("NOT-READY") then
          ["not-ready", ($bare | ltrimstr("NOT-READY") | sub("^[\\s:*`]+"; "") | gsub("\\s+"; " ") | sub(" $"; ""))]
        elif $missing == [] then ["handoff", "", $text]
        else ["invalid", "missing headings: \($missing | join(", "))"]
        end
      end
    | "\(.[0])\t\($end)\t\(.[1])", (.[2] // empty)
  ' --argjson off "$2" --arg tag "[kit-update restart $3]" --arg idle "$4" -r | {
    IFS= read -r line
    printf '%s\n' "$line"
    if [[ "$line" == handoff$'\t'* ]]; then cat >"$5"; fi
  }
}

# 0 when, after byte OFFSET of FILE, something was sent to Claude or Claude wrote anything.
activity_after() { # FILE OFFSET
  transcript_jq "$1" "$2" 'any(entries[]; is_prompt or .type == "assistant")' -e >/dev/null
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

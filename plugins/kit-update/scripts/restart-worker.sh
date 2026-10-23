#!/usr/bin/env bash
# kit-update restart worker — restart-all.sh starts it in a pane of its own with the snapshot it took,
# <config>/kit-update/restart.lock/state.<token>, and it restarts each session in it once idle (spec §3).
#
# Every 10 s it moves each pane in the snapshot on by one step. A pane goes through
#   wait      until it may take keys: its session file says idle, the screen is idle with an empty
#             prompt, nobody scrolls the pane, no background Bash shell runs under Claude, a request
#             slot is free (2 at a time) and the time to ask again has come
#   asked     "[kit-update restart <nonce>] ..." was typed into it; the answer is read from the transcript
#             after the offset taken before sending. NOT-READY → notready, a handoff → ready, a stale
#             one → wait (ask again 30 min after the last request), no usable handoff → wait 5 min, 3 times
#   notready  until its own session moves on after the answer (a new session id, statusUpdatedAt, or a
#             prompt or message in its transcript), then wait (again 30 min after the last request)
#   ready     its handoff is in <config>/kit-update/handoffs/<YYYYMMDD-HHMMSS>-<name>-<pane>.md. Moved on since
#             (typed into, a new session): back to wait. Once idle again, <handoff>.start.md gets a header line,
#             the handoff and a closing line, the relaunch command `claude --name <name> "$(cat <start file>)"`
#             goes to the log (over 1024 bytes: skipped), and /exit is typed (tmux: remain-on-exit on first)
#   exiting   until its Claude is gone, 60 s at most
#   relaunching  a tmux pane that died with Claude is respawned with that command as argv; else its shell
#             must be back in front within 10 s, and the command is typed into it
#   confirming  until a new Claude there has a session file (herdr: its agent name is set back), 60 s at most
# and ends as gone (not the Claude of the snapshot any more), skipped:<reason> or done. Before any key up to
# /exit the pane must still run the same Claude (pid, start time, tty; herdr: the pane is listed) in front of
# its terminal. The session that started the restart asks only when no other pane holds or waits for a slot,
# or is past /exit and not relaunched yet. A pane that hasn't got /exit after 4 h is skipped (for that session,
# 4 h from when it could start). A tmux pane gets its own remain-on-exit back however its relaunch ends.
# Ctrl-C, TERM or closing this pane (HUP) stop the worker: panes without /exit yet are skipped, the others
# are relaunched to the end, then the lock goes. Keys go through run_detached, out of reach of those signals.
# Each step is logged to <config>/kit-update/restart.log and this pane; a Summary ends both.
#
# Usage: restart-worker.sh <state file>   (the token is in its name: the worker stops if the lock has another)

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
source "$here/restart-lib.sh"

STATE=${1:-}
TOKEN=${STATE##*/state.}
hdr() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$STATE" 2>/dev/null; } # a header line of the state
cfg=$(hdr config)
[[ -n "$cfg" ]] && CLAUDE_CONFIG_DIR=$cfg
ku_paths
[[ "$(lock_token)" == "$TOKEN" ]] || exit 0 # not our lock (another restart took it): touch nothing
mkdir -p "$KU_DIR" "$HANDOFFS"
SOCK=$(hdr socket) WMUX=$(hdr mux)
tm() { "$TMUX_BIN" ${SOCK:+-S "$SOCK"} "$@"; }

# The owner file now names this worker, so restart-all.sh can tell it is running and where.
me=${HERDR_PANE_ID:-?}
[[ "$WMUX" == tmux ]] && me=${TMUX_PANE:-?}
printf '%s %s %s\ncmd %s\n' "$TOKEN" $$ "$me" "$(proc_field $$ args)" >"$LOCK/owner.$TOKEN" \
  && mv -f "$LOCK/owner.$TOKEN" "$LOCK/owner" || { echo "Could not write $LOCK/owner"; lock_release "$TOKEN"; exit 1; }

REQUEST=' ตอบเป็น handoff ของงานใน session นี้ในแชทเลย ห้ามเขียนไฟล์และห้ามเรียก tool ใด ๆ รวมถึง handoff ของ kit-checkpoint ใช้หัวข้อตามนี้ตรงตัว: เป้าหมาย / ทำเสร็จแล้ว / ค้างอยู่ตรงไหน / ตัดสินใจอะไรไปแล้วและเพราะอะไร / ไฟล์ที่เกี่ยวข้อง / ขั้นต่อไป ยกเว้นสองกรณีให้ตอบ NOT-READY: <เหตุผลหนึ่งบรรทัด> แล้วจบ turn (1) ยังมีงานเบื้องหลังที่ยังไม่จบ (background Bash, subagent, teammate ของ agent team, Monitor, /loop) ไม่นับ worker ของ kit-update restart (2) หลังคำถามล่าสุดที่คุณถามผู้ใช้ ยังไม่มีข้อความจากผู้ใช้เข้ามาเลย (ข้อความ [kit-update restart ...], คำตอบ NOT-READY ของคุณเอง, task notification และรอบของ /loop ไม่นับเป็นข้อความจากผู้ใช้) ไม่นับคำถามในสรุปที่คุณตอบกลับ handoff ที่ส่งมาเป็นข้อความแรก เช่นจาก [kit-update restart] หรือ [kit-checkpoint #...] (เรื่องที่ค้างอยู่ใน handoff แล้ว)' # spec §3 step 2, after "[kit-update restart <nonce>]"
HEAD='[kit-update restart] handoff จาก session ก่อน restart (Claude Code %s → %s)' # spec §3 step 5: old version, new
FOOT='ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร แล้วรอ'          # the same as kit-checkpoint's
CAP=14400  # 4 h, for panes that haven't reached /exit
SLOTS=2    # panes asked at once

# One entry per state row (the columns, then what the worker keeps):
#   MUX PANE_ID LABEL PID PROCSTART TTY SHELL_PID SID NAME VERSION CWD ISSUER AGENT_NAME CMDLINE
#   SNAME   the name it goes by: NAME, else the herdr agent name or workspace label, else the tmux session
#   SHOWN   "SNAME (herdr PANE_ID)" / "SNAME (tmux LABEL)", for the log and the Summary
#   FILE    "<SNAME>-<PANE_ID>" for the handoff file: other than [A-Za-z0-9_-] is _, the name part <= 40 bytes
#   PH      the phase; NONCE OFF ASKED: the last request, its transcript offset and time
#   BASE_OFF BASE_SUA  transcript offset and statusUpdatedAt when the answer was read, to see activity after it
#   NEXT_ASK  not asked before then; FAILS  answers that were no handoff; BUSY  status busy seen since the request
#   WHY     why it isn't asked yet (the reason it is skipped with at the cap); SLOTWAIT  ready but no slot, this tick
#   HANDOFF the handoff file; START its .start.md, the first message after the relaunch; LINE the relaunch command
#   ROE ROE_SET  tmux: the pane's own remain-on-exit (empty: none) and whether the worker has set it on since
#   EXITED SENT  when /exit, and the relaunch, were sent; RESPAWNED  the relaunch was a tmux respawn-pane
N=0 ORDER= late=
while IFS=$'\x1f' read -r _ mux pane label pid start tty sh sid name ver cwd iss aname args; do
  MUX[N]=$mux PANE_ID[N]=$pane LABEL[N]=$label PID[N]=$pid PROCSTART[N]=$start TTY[N]=$tty SHELL_PID[N]=$sh
  SID[N]=$sid NAME[N]=$name VERSION[N]=$ver CWD[N]=$cwd ISSUER[N]=$iss AGENT_NAME[N]=$aname CMDLINE[N]=$args
  if [[ "$mux" == herdr ]]; then
    SNAME[N]=${name:-${aname:-$label}} SHOWN[N]="${name:-${aname:-$label}} (herdr $pane)"
  else
    SNAME[N]=${name:-${label%%:*}} SHOWN[N]="${name:-${label%%:*}} (tmux $label)"
  fi
  FILE[N]=$(jq -rn --arg n "${SNAME[N]}" --arg p "$pane" '"\($n | gsub("[^A-Za-z0-9_-]"; "_") | .[:40])-\($p | gsub("[^A-Za-z0-9_-]"; "_"))"')
  PH[N]=wait NONCE[N]= OFF[N]=0 ASKED[N]=0 BASE_OFF[N]=0 BASE_SUA[N]= NEXT_ASK[N]=0 FAILS[N]=0 BUSY[N]=0
  WHY[N]='not checked yet' SLOTWAIT[N]=0 HANDOFF[N]= START[N]= LINE[N]= ROE[N]= ROE_SET[N]=0 EXITED[N]=0 SENT[N]=0
  RESPAWNED[N]=0
  if [[ "$iss" == 1 ]]; then late+=" $N"; else ORDER+=" $N"; fi
  N=$((N + 1))
done < <(awk -F'\t' '$1 == "pane"' "$STATE" | tr '\t' '\037') # \x1f, not tab: read merges empty tab-separated fields
ORDER+=$late # the issuing session's turn comes last in every tick, once it knows who waits for a slot

stamp() { date -r "$NOW" +%Y%m%d-%H%M%S 2>/dev/null || date -d "@$NOW" +%Y%m%d-%H%M%S; } # BSD, then GNU date

# Stop at once when the lock isn't this worker's any more (a restart took it over by mistake):
# two workers must never type into the same panes.
own_lock() {
  [[ "$(lock_token)" == "$TOKEN" ]] && return 0
  ku_log worker "lost the lock to another restart; stopping without touching any pane"
  exit 1
}

live() { case ${PH[$1]} in done* | gone | skipped:*) return 1 ;; esac; }

# End pane I as PHASE (gone, skipped:<reason>, done, done:<note>), logged as MESSAGE or the phase; it is
# not touched again.
finish() { PH[$1]=$2; ku_log "${SHOWN[$1]}" "${3:-${2/skipped:/skipped: }}"; }

# Note why pane I isn't asked yet; while it waits, each new reason goes to the log.
why() {
  [[ "${WHY[$1]}" == "$2" || "${PH[$1]}" != wait ]] || ku_log "${SHOWN[$1]}" "waiting: $2"
  WHY[$1]=$2
}

# 0 when pane I still runs the Claude of the snapshot, in front of its terminal: same pid, start
# time (its session file and the live process) and tty; in herdr, the pane is still listed.
# 1 when it doesn't (gone); 2 when it is there but can't take keys now (WHY says why).
identity_ok() {
  local i=$1 row l p pp g t tty w1 w2 w3 w4 w5
  row=$(proc_row "${PID[i]}") || return 1
  read -r p pp g t tty w1 w2 w3 w4 w5 _ <<<"$row" # one row: pgid and tpgid of the same moment
  [[ "$tty" == "${TTY[i]}" && "$w1 $w2 $w3 $w4 $w5" == "$(tr -s ' ' <<<"${PROCSTART[i]}")" \
    && "$(sf_get "${PID[i]}" procStart)" == "${PROCSTART[i]}" ]] || return 1
  if [[ "${MUX[i]}" == herdr ]]; then
    l=$("$HERDR_BIN" agent list 2>/dev/null) || { why "$i" "herdr does not answer"; return 2; }
    jq -e --arg p "${PANE_ID[i]}" 'any(.result.agents[]?; .pane_id == $p)' <<<"$l" >/dev/null 2>&1 || return 1
  fi
  [[ "$g" == "$t" ]] || { why "$i" "not in front of its terminal (suspended?)"; return 2; }
}

# 0 when keys may go to pane I now (spec §3 step 1): its session is idle, the screen is idle with an
# empty prompt (reload's check), nobody scrolls the pane, and no background Bash shell runs.
pane_sendable() {
  local i=$1 p=${PANE_ID[i]} s
  case $(sf_get "${PID[i]}" status) in
    idle) ;;
    shell) why "$i" "background process still running"; return 1 ;;
    *) why "$i" busy; return 1 ;;
  esac
  if [[ "${MUX[i]}" == herdr ]]; then
    s=$("$HERDR_BIN" agent list 2>/dev/null | jq -r --arg p "$p" '.result.agents[]? | select(.pane_id == $p) | .agent_status' 2>/dev/null)
    case $s in
      idle | done) ;;
      blocked) why "$i" "waiting on a question"; return 1 ;;
      *) why "$i" busy; return 1 ;;
    esac
    s=$("$HERDR_BIN" agent read "$p" --source visible 2>/dev/null | grep -v '^[[:space:]]*$' | tail -15)
    prompt_empty "$s" || { why "$i" "prompt not empty or not found"; return 1; }
  else
    s=$(tm capture-pane -p -t "$p" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -15)
    case $(screen_state "$s") in
      busy) why "$i" busy; return 1 ;;
      question) why "$i" "waiting on a question"; return 1 ;;
      draft) why "$i" "prompt not empty or not found"; return 1 ;;
    esac
  fi
  not_scrolled "$i" || return 1
  [[ -z "$(bg_shells "${PID[i]}")" ]] || { why "$i" "background process still running"; return 1; }
}

# 0 when nobody scrolls pane I, so keys reach what runs in it: tmux not in copy mode, herdr at the bottom.
not_scrolled() {
  local i=$1 p=${PANE_ID[$1]}
  if [[ "${MUX[i]}" == herdr ]]; then
    [[ "$("$HERDR_BIN" pane get "$p" 2>/dev/null | jq -r '.result.pane.scroll.offset_from_bottom' 2>/dev/null)" == 0 ]] \
      || { why "$i" "scrolled up"; return 1; }
  else
    [[ "$(tm display-message -p -t "$p" '#{pane_in_mode}' 2>/dev/null)" == 0 ]] || { why "$i" "in copy mode"; return 1; }
  fi
}

asked_count() { local j c=0; for ((j = 0; j < N; j++)); do [[ "${PH[j]}" == asked ]] && c=$((c + 1)); done; echo $c; }

# 0 while a pane other than I holds a request slot or waits for one, or got /exit and isn't relaunched
# yet: the issuing session goes after them.
others_block() {
  local j
  for ((j = 0; j < N; j++)); do
    ((j == $1)) && continue
    case ${PH[j]} in asked | exiting | relaunching | confirming) return 0 ;; esac
    [[ "${SLOTWAIT[j]}" == 1 ]] && return 0
  done
  return 1
}

# Type the handoff request into pane I (spec §3 step 2), after taking the transcript's size (a line
# start, as the session is idle; 0 when it has none yet). Whether the keys arrived is not asked:
# only the request showing up in the transcript, or the session turning busy, tells.
send_request() {
  local i=$1 n f t
  own_lock
  SID[i]=$(sf_get "${PID[i]}" sessionId)
  if f=$(transcript_for "${SID[i]}"); then OFF[i]=$(($(wc -c <"$f"))); else OFF[i]=0; fi
  n=$(od -An -tx1 -N8 /dev/urandom | tr -d ' \n')
  t="[kit-update restart $n]$REQUEST"
  printf '%s' "$t" >"$LOCK/request-$n.txt" # no \n at the end: tmux would paste it as a new line
  NONCE[i]=$n ASKED[i]=$NOW BUSY[i]=0 PH[i]=asked
  ku_log "${SHOWN[i]}" "asked for a handoff (request $n, its transcript read from byte ${OFF[i]})"
  if [[ "${MUX[i]}" == herdr ]]; then
    run_detached "$HERDR_BIN" agent prompt "${PANE_ID[i]}" "$t"
  else # a buffer of our own, pasted as one bracketed paste, then Enter, in one tmux call
    run_detached tm load-buffer -b "kit-update-$n" "$LOCK/request-$n.txt" \; \
      paste-buffer -b "kit-update-$n" -p -d -t "${PANE_ID[i]}" \; send-keys -t "${PANE_ID[i]}" Enter
  fi
}

# Pane I's answer was no usable handoff (REASON): ask again in 5 min, and give up after 3.
no_handoff() {
  local i=$1
  FAILS[i]=$((FAILS[i] + 1))
  if ((FAILS[i] >= 3)); then
    ku_log "${SHOWN[i]}" "no valid handoff: $2 (3 of 3)"
    finish "$i" "skipped:no valid handoff"
  else
    PH[i]=wait NEXT_ASK[i]=$((NOW + 300)) WHY[i]="no valid handoff: $2"
    ku_log "${SHOWN[i]}" "no valid handoff: $2 (${FAILS[i]} of 3); asking again in 5 min"
  fi
}

# Read pane I's answer to its request (spec §3 step 3). ID is what identity_ok said this tick.
read_answer() {
  local i=$1 id=$2 sid f out res v end d idle=0 r
  sid=$(sf_get "${PID[i]}" sessionId)
  if [[ "$sid" != "${SID[i]}" ]]; then # /clear: that handoff can't be used; not a failure
    PH[i]=wait
    ku_log "${SHOWN[i]}" "its session changed before the answer (/clear?); asking again once idle"
    return
  fi
  [[ "$(sf_get "${PID[i]}" status)" == busy ]] && BUSY[i]=1
  ((id == 0)) && pane_sendable "$i" && idle=1
  f=$(transcript_for "$sid")
  out=$HANDOFFS/$(stamp)-${FILE[i]}.md
  res=$(answer_state "$f" "${OFF[i]}" "${NONCE[i]}" "$idle" "$out") # stdout only: its status says nothing more
  IFS=$'\t' read -r v end d <<<"$res"
  case $v in
    handoff)
      [[ -s "$out" ]] || { finish "$i" "skipped:could not write its handoff to $HANDOFFS"; return; }
      HANDOFF[i]=$out BASE_OFF[i]=$end BASE_SUA[i]=$(sf_get "${PID[i]}" statusUpdatedAt) PH[i]=ready
      ku_log "${SHOWN[i]}" "handoff written: $out" ;;
    not-ready)
      BASE_OFF[i]=$end BASE_SUA[i]=$(sf_get "${PID[i]}" statusUpdatedAt) NEXT_ASK[i]=$((ASKED[i] + 1800))
      PH[i]=notready WHY[i]="NOT-READY: $d"
      ku_log "${SHOWN[i]}" "NOT-READY: $d" ;;
    stale)
      PH[i]=wait NEXT_ASK[i]=$((ASKED[i] + 1800)) WHY[i]="handoff out of date ($d)"
      ku_log "${SHOWN[i]}" "handoff out of date ($d); asking again 30 min after the request" ;;
    invalid) no_handoff "$i" "$d" ;;
    no-nonce) # the request isn't in the transcript: not typed in, or Claude is busy before it (auto-compact)
      if ((BUSY[i])); then
        r="no answer within 15 min"; [[ -n "$f" ]] || r="no transcript"
        ((NOW - ASKED[i] >= 900)) && no_handoff "$i" "$r"
      elif ((NOW - ASKED[i] >= 30)); then
        finish "$i" "skipped:request not submitted"
      fi ;;
    *) ((NOW - ASKED[i] >= 900)) && no_handoff "$i" "no answer within 15 min" ;; # pending
  esac
}

# 0 when the transcript FILE has a prompt or a Claude message after byte OFFSET. An error counts as
# activity: better to look again than to wait for nothing.
moved() { activity_after "$1" "$2"; (($? != 1)); }

# 0 when pane I's own session moved on since its answer was read: a new session id or statusUpdatedAt,
# or a prompt or Claude message in its transcript.
moved_on() {
  local i=$1
  [[ "$(sf_get "${PID[i]}" sessionId)" != "${SID[i]}" || "$(sf_get "${PID[i]}" statusUpdatedAt)" != "${BASE_SUA[i]}" ]] \
    || moved "$(transcript_for "${SID[i]}")" "${BASE_OFF[i]}"
}

# The command that relaunches pane I: claude --name <name> "$(cat <start file>)". %q in the C locale:
# bash 3.2 otherwise escapes only some bytes of a UTF-8 name, which leaves the line invalid UTF-8.
relaunch_line() { local LC_ALL=C; printf 'claude --name %q "$(cat %q)"' "${SNAME[$1]}" "${START[$1]}"; }

# Pane I is idle and its handoff still current (spec §3 step 4): write the start file, log the relaunch
# command (too long for one line: skip it now, while Claude still runs), then type /exit. A tmux pane gets
# remain-on-exit on first, so it stays when Claude was its process or its shell was sh -c.
exit_pane() {
  local i=$1 p=${PANE_ID[$1]} v
  v=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) # the version it comes back as
  START[i]=${HANDOFF[i]%.md}.start.md
  printf "$HEAD"'\n\n%s\n\n%s\n' "${VERSION[i]:-?}" "${v:-?}" "$(cat "${HANDOFF[i]}")" "$FOOT" >"${START[i]}" \
    || { finish "$i" "skipped:could not write ${START[i]}"; return; }
  LINE[i]=$(relaunch_line "$i")
  ku_log "${SHOWN[i]}" "relaunch command: ${LINE[i]} (it was started as: ${CMDLINE[i]})"
  if (($(printf '%s' "${LINE[i]}" | wc -c) > 1024)); then finish "$i" "skipped:relaunch command too long"; return; fi
  own_lock
  if [[ "${MUX[i]}" == tmux ]]; then
    ROE[i]=$(tm show-options -p -v -t "$p" remain-on-exit 2>/dev/null) ROE_SET[i]=1
    tm set-option -p -t "$p" remain-on-exit on 2>/dev/null
  fi
  if ((STOPPING)); then restore_roe "$i"; finish "$i" skipped:stopped; return; fi
  PH[i]=exiting EXITED[i]=$NOW
  ku_log "${SHOWN[i]}" "sent /exit"
  if [[ "${MUX[i]}" == herdr ]]; then
    run_detached "$HERDR_BIN" agent prompt "$p" /exit
  else
    run_detached tm send-keys -t "$p" -l /exit \; send-keys -t "$p" Enter
  fi # its status says nothing: whether Claude exits does
}

# Give tmux pane I its own remain-on-exit back, if the worker set it on (none of its own: the window's).
restore_roe() {
  local i=$1
  ((ROE_SET[i])) || return 0
  ROE_SET[i]=0
  if [[ -n "${ROE[i]}" ]]; then
    tm set-option -p -t "${PANE_ID[i]}" remain-on-exit "${ROE[i]}"
  else
    tm set-option -pu -t "${PANE_ID[i]}" remain-on-exit
  fi 2>/dev/null
}
restore_all() { local i; for ((i = 0; i < N; i++)); do restore_roe "$i"; done; }

# Pane I's Claude exited: start it again (spec §3 step 5). A tmux pane that died with it is respawned with
# the command as argv, through no shell of the user's; else the shell that ran it must be back in front
# (checked each second, 10 s at most), and the command is typed into it. herdr: the pane must still be
# listed. Every key here is typed once; respawn-pane is tried twice, as it refuses a pane that runs anything.
relaunch() {
  local i=$1 p=${PANE_ID[$1]} t k
  PH[i]=relaunching
  ku_log "${SHOWN[i]}" "exited"
  if [[ "${MUX[i]}" == tmux && "$(tm display-message -p -t "$p" '#{pane_dead}' 2>/dev/null)" == 1 ]]; then
    own_lock
    for k in 1 2; do
      run_detached tm respawn-pane -t "$p" -c "${CWD[i]}" /bin/sh -c 'exec claude --name "$1" "$(cat "$2")"' sh \
        "${SNAME[i]}" "${START[i]}" && break
    done
    RESPAWNED[i]=1
  else
    if [[ "${MUX[i]}" == herdr ]] && ! "$HERDR_BIN" pane list 2>/dev/null \
      | jq -e --arg p "$p" 'any(.result.panes[]?; .pane_id == $p)' >/dev/null 2>&1; then
      finish "$i" gone "gone: its pane closed after /exit"
      return
    fi
    t=$(ku_now)
    until proc_foreground "${SHELL_PID[i]}" && not_scrolled "$i"; do
      if (($(ku_now) - t >= 10)); then
        ku_log "${SHOWN[i]}" "relaunch it yourself: ${LINE[i]}"
        restore_roe "$i"
        finish "$i" "skipped:shell not in front"
        return
      fi
      ku_nap 1
    done
    own_lock
    if [[ "${MUX[i]}" == herdr ]]; then
      run_detached "$HERDR_BIN" pane run "$p" "${LINE[i]}"
    else
      run_detached tm send-keys -t "$p" -l "${LINE[i]}" \; send-keys -t "$p" Enter
    fi
  fi
  restore_roe "$i"
  PH[i]=confirming SENT[i]=$(ku_now)
}

# What runs in pane I since its relaunch: "session" when a new Claude there has a session file, "process"
# when only a claude process does (a dialog on its first start), else nothing. There: a child of its shell;
# for a respawned pane, the pane's process or a child of it.
new_claude() {
  local i=$1 top=${SHELL_PID[$1]} own= p a r=
  if ((RESPAWNED[i])); then top=$(tm display-message -p -t "${PANE_ID[i]}" '#{pane_pid}' 2>/dev/null) own=$top; fi
  for p in $own $(proc_children "$top" | cut -d' ' -f1); do
    [[ -f "$(sf_path "$p")" ]] && { echo session; return; }
    a=$(proc_field "$p" args); a=${a%% *}
    [[ "${a##*/}" == claude ]] && r=process
  done
  echo "$r"
}

# Pane I was relaunched (spec §3 step 6): done once its new Claude has a session file, and a herdr agent
# that had a name has it again. After 60 s, a claude process alone counts as started; nothing is a failure.
confirm() {
  local i=$1
  case $(new_claude "$i") in
    session)
      if [[ "${MUX[i]}" == herdr && -n "${AGENT_NAME[i]}" ]]; then
        own_lock
        run_detached "$HERDR_BIN" agent rename "${PANE_ID[i]}" "${AGENT_NAME[i]}" \
          || ku_log "${SHOWN[i]}" "could not set its herdr agent name ${AGENT_NAME[i]} again"
      fi
      finish "$i" done restarted ;;
    process) ((NOW - SENT[i] >= 60)) && finish "$i" "done:started, waiting on screen" "restarted: started, waiting on screen" ;;
    *)
      if ((NOW - SENT[i] >= 60)); then
        ku_log "${SHOWN[i]}" "relaunch it yourself: ${LINE[i]}"
        finish "$i" "skipped:relaunch failed"
      fi ;;
  esac
}

# Move pane I on by one step.
step() {
  local i=$1 id start
  SLOTWAIT[i]=0
  case ${PH[i]} in # past /exit: the pid is meant to go, no cap, and stopping lets it finish (spec §3 steps 4–6)
    exiting)
      if [[ "$(proc_field "${PID[i]}" start)" != "$(tr -s ' ' <<<"${PROCSTART[i]}")" ]]; then
        relaunch "$i"
      elif ((NOW - EXITED[i] >= 60)); then
        restore_roe "$i"
        finish "$i" "skipped:did not exit"
      fi
      return ;;
    confirming) confirm "$i"; return ;;
  esac
  if ((STOPPING)); then finish "$i" skipped:stopped; return; fi
  identity_ok "$i"; id=$?
  if ((id == 1)); then finish "$i" gone; return; fi
  if [[ "${ISSUER[i]}" == 1 && -z "$ISSUER_FROM" ]] && ! others_block "$i"; then ISSUER_FROM=$NOW; fi
  start=$T0; [[ "${ISSUER[i]}" == 1 ]] && start=$ISSUER_FROM
  if [[ -n "$start" ]] && ((NOW - start >= CAP)); then finish "$i" "skipped:${WHY[i]}, gave up after 4 h"; return; fi
  case ${PH[i]} in
    wait)
      ((NOW >= NEXT_ASK[i] && id == 0)) && pane_sendable "$i" || return 0
      if [[ "${ISSUER[i]}" == 1 ]] && others_block "$i"; then why "$i" "goes after the other sessions"; return 0; fi
      if (($(asked_count) >= SLOTS)); then SLOTWAIT[i]=1; why "$i" "waiting for a free request slot"; return 0; fi
      send_request "$i" ;;
    asked) read_answer "$i" "$id" ;;
    notready)
      if moved_on "$i"; then
        PH[i]=wait
        ku_log "${SHOWN[i]}" "moved on after NOT-READY; asking again once idle, 30 min after the request"
      fi ;;
    ready)
      if moved_on "$i"; then # typed into since the handoff: it is out of date
        PH[i]=wait NEXT_ASK[i]=$((ASKED[i] + 1800))
        ku_log "${SHOWN[i]}" "moved on after its handoff; asking again once idle, 30 min after the request"
      elif ((id == 0)) && pane_sendable "$i"; then
        exit_pane "$i"
      fi ;;
  esac
}

summary() {
  local i r=() s=()
  for ((i = 0; i < N; i++)); do
    case ${PH[i]} in
      done) r+=("${SHOWN[i]}") ;;
      done:*) r+=("${SHOWN[i]} — ${PH[i]#done:}") ;;
      gone) s+=("${SHOWN[i]} — gone") ;;
      skipped:*) s+=("${SHOWN[i]} — ${PH[i]#skipped:}") ;;
    esac
  done
  echo "Summary  restarted: ${#r[@]} · skipped: ${#s[@]}"
  ((${#r[@]})) && { echo "  Restarted:"; printf '    - %s\n' "${r[@]}"; }
  ((${#s[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${s[@]}"; }
  return 0
}

# Ctrl-C and TERM stop it; so does HUP (this pane closed), after which nothing may be written to it: a
# write there must not kill the worker in the middle of a relaunch.
STOPPING=0
trap 'STOPPING=1' INT TERM
trap 'STOPPING=1; trap "" PIPE; exec >/dev/null 2>&1' HUP
trap restore_all EXIT # own_lock's exit too

T0=$(ku_now) ISSUER_FROM=
ku_log worker "started for $N session(s)"
while :; do
  own_lock
  NOW=$(ku_now) left=0
  for i in $ORDER; do live "$i" && step "$i"; done
  for i in $ORDER; do live "$i" && left=1; done
  ((left)) || break
  ku_nap 10
done
summary | tee -a "$LOG"
lock_release "$TOKEN"
exit 0

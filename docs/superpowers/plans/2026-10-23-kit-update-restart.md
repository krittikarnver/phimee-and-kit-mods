# kit-update restart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/kit-update:restart` รอให้ทุก Claude Code session ใน herdr/tmux ว่าง ขอ handoff ในแชท เก็บลงไฟล์ `/exit` แล้วเปิด `claude --name <ชื่อ>` ใหม่ใน pane เดิมโดยมี handoff เป็นข้อความแรก session ที่สั่งไปหลังสุด

**Architecture:** shell script สามตัวบน `/bin/bash` 3.2: `restart-all.sh` (ตัวเรียก: lock, snapshot, เขียน state, เปิด worker ใน pane ของตัวเอง), `restart-worker.sh` (loop เดียวไล่ทุก pane ทุก 10 วินาที แต่ละ pane เป็น state machine), `restart-lib.sh` (ฟังก์ชันที่สองตัวใช้ร่วม: process, session file, transcript, log) ส่วนการอ่านจอที่ reload ใช้อยู่แยกออกมาเป็น `pane-lib.sh` ให้ reload กับ restart ใช้ร่วมกัน test ทั้งหมดรันกับ "โลกปลอม" (fake tmux, herdr, ps, นาฬิกา, Claude) ใน `CLAUDE_CONFIG_DIR` ชั่วคราว

**Tech Stack:** bash 3.2, `jq`, `ps`, tmux 3.x, herdr 0.9.x, Claude Code 2.1.308

**Spec:** `docs/superpowers/specs/2026-10-22-kit-update-restart-design.md` (อ่านคู่กันเสมอ plan อ้างหัวข้อในนั้นเป็น "spec §N" และ "spec §3 ขั้น N")

## Global Constraints

- รันบน `/bin/bash` 3.2: ห้าม `declare -A`, `wait -n`, `mapfile`/`readarray`, `${x,,}`, `local -n` ใช้ indexed array ขนานกันแทน map
- `set -uo pipefail` แบบ `reload-all.sh` (ไม่ใช้ `-e`)
- ทุก path ที่ spec เขียนว่า `~/.claude` ใช้ `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` ไฟล์ของ restart อยู่ใต้ `<config>/kit-update/` เท่านั้น ห้ามเขียนอะไรใน cwd หรือ repo ของผู้ใช้
- ตัว override สำหรับ test (ห้ามมีตัวอื่น): `KIT_UPDATE_TMUX_BIN`, `KIT_UPDATE_HERDR_BIN`, `KIT_UPDATE_PS_BIN`, `KIT_UPDATE_CLOCK_BIN`, `KIT_UPDATE_SLEEP_BIN`, `CLAUDE_CONFIG_DIR` test ห้ามแตะ `~/.claude`, process จริง หรือ pane จริง (ห้าม `kill -0` กับ pid จาก state)
- ค่าคงที่ (spec): เช็กทุก `10` วินาที, ช่องขอ handoff `2`, เพดาน `14400` วินาที (ขั้น 1–3 และขั้น 4 ก่อน `/exit`), ถามซ้ำห่างกัน `>= 1800` วินาทีนับจากตอนถามครั้งก่อน, เห็น nonce entry ภายใน `30` วินาที, คำตอบจบภายใน `900` วินาที, คำตอบไม่ผ่านขอใหม่หลัง `300` วินาที สูงสุด `3` ครั้ง, `/exit` ภายใน `60` วินาที, ยืนยันการเปิดใหม่ภายใน `60` วินาที, รอ shell อยู่หน้าสุด `10` วินาที (เช็กทุก `1` วินาที), lock ค้างเมื่อ `60` วินาที, บรรทัดคำสั่งที่ส่งผ่าน `pane run` / `send-keys` ต้อง `<= 1024` byte, ส่วนชื่อในชื่อไฟล์ `<= 40` byte
- ข้อความขอ handoff, บรรทัดหัวและบรรทัดท้ายของไฟล์ start คัดลอกตรงตัวจาก spec §3 ขั้น 2 และขั้น 5 (เปลี่ยนแค่ `<nonce>` / `<version>`)
- output ของ script และ log เป็นภาษาอังกฤษแบบ `reload-all.sh` (`Summary`, เหตุผลอย่าง `gone`, `did not exit`) README, `plugin.json`, marketplace เป็นภาษาไทย
- คำสั่งที่ส่งแป้นเข้า pane ทุกตัว (`herdr agent prompt`, `herdr pane run`, `tmux paste-buffer`/`send-keys`/`respawn-pane`) เรียกผ่าน `run_detached` (Task 3) เท่านั้น และห้ามส่งซ้ำ ยกเว้น `respawn-pane` หนึ่งครั้ง (spec §2 "หยุด worker")
- ก่อนกดแป้นทุกครั้ง (จนถึง `/exit`) ต้องผ่าน `identity_ok` และ `pane_sendable` (Task 6)
- repo นี้ public: fixture, ชื่อ pane, path ใน test ใช้ของสมมติแบบ `reload-all.test.sh` (`/x/alpha`) ห้ามมีชื่อโปรเจกต์หรือ path จริงของเครื่อง
- version `0.2.0` ตั้งใน Task 2 commit subject ทุกตัวขึ้นต้น `kit-update 0.2.0:` ปิดท้าย commit message ด้วยบรรทัด `Claude-Session:` ตามที่ session กำหนด

## Review Focus

1. ชื่อ session มีภาษาไทย ช่องว่าง `'` `"` `$` และ handoff มี `$(...)`, backtick, `"` หรือบรรทัดที่ขึ้นต้นด้วย `-` ต้องไปถึง `claude` เป็น argv ตรงตัว ไม่มีอะไรถูก expand → Task 7 `relaunch argv survives hostile name and handoff`
2. cwd มีช่องว่าง (tmux `respawn-pane -c`) ต้องเปิดใหม่ถูกโฟลเดอร์ → Task 7 `respawn uses cwd with spaces`
3. transcript ใหญ่ที่บรรทัดท้ายยังเขียนไม่ครบ ต้องอ่านแค่ส่วนท้าย และ offset ต้องหยุดก่อนบรรทัดที่ไม่ครบ → Task 4 `partial last line: ignored, end offset before it`
4. herdr agent ไม่มีชื่อ และ label ของ workspace เป็นภาษาไทยมีช่องว่าง: ชื่อที่ใช้เปิดใหม่และชื่อไฟล์ต้องถูก และห้าม `agent rename` ถ้าเดิมไม่มีชื่อ → Task 7 `unnamed herdr agent: no rename, label fallback`
5. รันซ้ำทันทีหลังรอบก่อนจบ (pane ของ worker รอบก่อนยังเปิดอยู่, ไฟล์ handoff ชื่อคล้ายกัน): ต้องเริ่มได้ ไม่ชนชื่อ workspace/session และไม่ทับไฟล์ → Task 5 `second run while previous worker pane is open`

---

## File Structure

```
plugins/kit-update/
  .claude-plugin/plugin.json      version 0.2.0, description พูดถึง restart (Task 2, Task 8)
  commands/restart.md             คำสั่ง /kit-update:restart (Task 8)
  scripts/pane-lib.sh             prompt_empty + screen_state ที่ย้ายมาจาก reload-all.sh (Task 2)
  scripts/reload-all.sh           source pane-lib.sh แทนโค้ดที่ย้ายออก (Task 2)
  scripts/restart-lib.sh          ฟังก์ชันร่วมของ restart (Task 3, 4)
  scripts/restart-all.sh          ตัวเรียก (Task 5)
  scripts/restart-worker.sh       worker (Task 6, 7)
  scripts/restart-all.test.sh     test ทั้งหมดของ restart + โลกปลอม (Task 3–7)
README.md, .claude-plugin/marketplace.json, CLAUDE.md, guides/tmux-remote-control.md   (Task 8)
docs/superpowers/specs/2026-10-22-kit-update-restart-design.md                         (Task 1 เพิ่มผล spike)
```

---

### Task 1: Spike บนเครื่องจริง (ทำใน main session ไม่ใช่ subagent)

ตรวจข้อ "ต้องเช็คระหว่างทำ" ของ spec ก่อนเขียน worker เพราะหลายข้อเป็นสมมติฐานที่ design พึ่ง ใช้ของทิ้งเท่านั้น: herdr workspace `kit-update spike` (`herdr workspace create --label "kit-update spike" --no-focus`), tmux socket แยก `tmux -L kit-spike`, โฟลเดอร์งานจาก `mktemp -d` **ห้ามพิมพ์ลง pane ที่ไม่ได้สร้างเองใน task นี้** ปิดทุกอย่างที่สร้างตอนจบ

**Files:**
- Modify: `docs/superpowers/specs/2026-10-22-kit-update-restart-design.md` (เพิ่มหัวข้อ `## ผลการเช็ค (spike)` ต่อจาก "ต้องเช็คระหว่างทำ")

**Interfaces:**
- Produces: กฎที่ Task 3 ใช้ใน `bg_shells` (หน้าตา args ของ shell ที่ background Bash/Monitor ใช้ เทียบกับ MCP server), กฎแยก teammate ของ agent team ที่ Task 5 ใช้, ผลว่า `CLAUDE_CONFIG_DIR` ชั่วคราวต้อง `/login` ไหม (Task 9 ใช้)

- [x] **Step 1: กลุ่ม Claude Code** เปิด `claude --name spike` ใน pane ทิ้ง แล้วบันทึก:
  - `claude --name spike "$(cat <ไฟล์หลายบรรทัด ~3KB>)"` ขึ้นแบบ interactive และส่งข้อความแรกจริง
  - ข้อความภาษาไทยบรรทัดเดียวที่ส่งผ่าน `herdr agent prompt` และผ่าน `tmux -L kit-spike load-buffer -b x <file> \; paste-buffer -b x -p -d \; send-keys Enter` เข้าเป็นข้อความเดียว และใน transcript เป็น `type:"user"` ข้อความเต็ม (ไม่ใช่ `[Pasted text #1]`)
  - ข้อความที่พิมพ์ระหว่าง Claude ทำงานอยู่ถูกบันทึกเป็น `queued_command` `commandMode:"prompt"`
  - `/exit` ทำให้ Claude ออก และ `<config>/sessions/<pid>.json` หายไป, `/exit` ใน `claude --worktree` ขึ้น dialog ไหม, `/vim` NORMAL mode ทำให้ `/exit` กลายเป็นคำสั่ง vim ไหม
  - session file: `sessionId` หลัง `/clear`, `status`/`statusUpdatedAt` ระหว่าง turn และตอน idle (ดูห่างกัน 5 นาที), `status:"shell"` เกิดตอนไหน (ลอง Ctrl+Z และ `!` bash mode)
  - herdr `agent_session.value` หลัง `/clear`
  - args ของ process ลูกของ Claude ตอนรัน `sleep 300` เป็น background Bash, ตอนเปิด Monitor และ MCP server (`ps -A -o pid=,ppid=,args=`)
  - ถ้าเปิด agent team ได้ในเวลาไม่เกิน 10 นาที: args และ `kind` ของ teammate ถ้าไม่ได้ บันทึกว่าไม่ได้ตรวจ
  - `CLAUDE_CONFIG_DIR=$(mktemp -d) claude` ใช้ได้เลยหรือต้อง `/login`
- [x] **Step 2: กลุ่มโมเดล** ใน session ทิ้งเดียวกัน ส่งข้อความขอ handoff ตรงตัวตาม spec §3 ขั้น 2 ในสามสภาพ: (ก) ว่างและไม่มีคำถามค้าง (ข) หลัง Claude ถามคำถามแล้วยังไม่ตอบ จากนั้นมี task notification เข้ามาหนึ่งครั้ง แล้วถามซ้ำ (ค) มี `sleep 300` เป็น background Bash ค้าง บันทึกว่าได้ handoff หรือ `NOT-READY` และ Claude เรียก tool หรือเปล่า
- [x] **Step 3: กลุ่ม terminal/tmux/herdr**
  - ใน pane ทิ้งที่มี tty: script ที่ทำ `set -m; sleep 30 </dev/null & p=$!; set +m` แล้ว `trap 'echo INT' INT; sleep 30` กด Ctrl-C: trap ต้องทำงาน และ pgid ของ `$p` ต่างจาก worker
  - ปิด herdr pane และ `tmux kill-pane` ส่งแค่ `HUP` หรือมี `SIGKILL` ตามมา (script ที่ `trap 'echo HUP >>f; sleep 5; echo alive >>f' HUP`)
  - `tmux -L kit-spike`: `set-option -p remain-on-exit on`, `set-option -pu`, `show-options -p -v remain-on-exit` ตอนไม่ได้ตั้ง, `respawn-pane -t P -c '<dir มีช่องว่าง>' /bin/sh -c 'exec env' sh a b` (แบบ argv), `#{pane_in_mode}` ตอนอยู่ใน copy mode, `#{pane_dead}`
  - herdr: `pane run` ปฏิเสธบรรทัดเกิน 1024 byte, รูปแบบชื่อของ `agent rename --help`, แป้นจาก `agent prompt` ตอน pane กำลัง scroll อยู่ไปที่ไหน, shell ได้ terminal คืนหลัง Claude ออกช้าแค่ไหน
  - tmux ที่รันใน herdr pane: เจอ `tmux` ใน process ที่เป็นบรรพบุรุษของ Claude
- [x] **Step 4: บันทึกผล** ทุกข้อเป็นหนึ่งบรรทัด: ผล, หลักฐาน (คำสั่งที่รัน), ผลต่อ design แก้ข้อความใน spec ที่ผิดด้วย ห้ามใส่ชื่อโปรเจกต์หรือ path จริงของเครื่อง (`grep -niE '/Users/|<ชื่อโปรเจกต์>' spec` ต้องไม่เจอ)
- [x] **Step 5: จุดหยุด** ถ้าข้อไหนต่อไปนี้ผิดจากที่ spec สมมติ ให้หยุดแล้วรายงานกิตพร้อมข้อเสนอแก้ spec ห้ามทำ Task 2 ต่อ: ข้อความแรกจาก `claude --name ... "$(cat f)"`, transcript เก็บข้อความเต็ม, `/exit` ออกจริงและ session file หาย, trap ของ Ctrl-C, `queued_command`, `statusUpdatedAt` นิ่งตอน idle, แยก shell ของ background Bash ได้, โมเดลตอบ `NOT-READY` ถูกในสภาพ (ข) และ (ค)
- [x] **Step 6: ปิดของทิ้งทั้งหมด** (`herdr workspace close`, `tmux -L kit-spike kill-server`, ลบโฟลเดอร์ชั่วคราว) แล้ว commit

```bash
git add docs/superpowers/specs/2026-10-22-kit-update-restart-design.md
git commit -m "kit-update: spike results for restart"
```

---

### Task 2: แยกการอ่านจอออกเป็น `pane-lib.sh`

**Files:**
- Create: `plugins/kit-update/scripts/pane-lib.sh`
- Modify: `plugins/kit-update/scripts/reload-all.sh:32-33,49-61,84`
- Modify: `plugins/kit-update/.claude-plugin/plugin.json` (version `0.2.0`)
- Test: `plugins/kit-update/scripts/reload-all.test.sh` (ของเดิม ต้องผ่านโดยไม่แก้)

**Interfaces:**
- Produces: `prompt_empty SCREEN` (ย้ายมาตรงตัวจาก `reload-all.sh:33`), `screen_state SCREEN` → echo `busy` | `question` | `draft` | `idle` ด้วย regex เดิมของ `reload-all.sh:50,54,58` ตามลำดับนั้น

- [ ] **Step 1:** รัน `bash plugins/kit-update/scripts/reload-all.test.sh` ก่อนแก้ Expected: `all passed`
- [ ] **Step 2:** สร้าง `pane-lib.sh` (header comment บอกว่า reload และ restart ใช้ร่วมกัน) ให้ `reload-all.sh` `source "$(dirname "$0")/pane-lib.sh"` แล้วเปลี่ยน if สามชั้นของ tmux เป็น `case "$(screen_state "$screen")"` ที่ให้ข้อความ skip เดิมทุกตัว bump version เป็น `0.2.0`
- [ ] **Step 3:** รัน test เดิม Expected: `all passed` และ `diff <(git show HEAD:plugins/kit-update/scripts/reload-all.test.sh) plugins/kit-update/scripts/reload-all.test.sh` ว่าง
- [ ] **Step 4: Commit** `kit-update 0.2.0: move reload's screen checks into pane-lib.sh`

---

### Task 3: `restart-lib.sh` ส่วน process, session file, log และโลกปลอม

**Files:**
- Create: `plugins/kit-update/scripts/restart-lib.sh`
- Create: `plugins/kit-update/scripts/restart-all.test.sh`

**Interfaces:**
- Consumes: กฎ `bg_shells` และกฎ teammate จาก Task 1
- Produces (ทุกตัวอยู่ใน `restart-lib.sh` ซึ่ง source `pane-lib.sh`):
  - ตัวแปรจาก `ku_paths`: `CFG`, `KU_DIR=$CFG/kit-update`, `LOCK=$KU_DIR/restart.lock`, `LOG=$KU_DIR/restart.log`, `HANDOFFS=$KU_DIR/handoffs`, `TMUX_BIN`, `HERDR_BIN`, `PS_BIN`
  - `ku_now` → epoch วินาที (`$KIT_UPDATE_CLOCK_BIN` หรือ `date +%s`), `ku_nap N` (`$KIT_UPDATE_SLEEP_BIN N` หรือ `sleep N`)
  - `ku_log LABEL MESSAGE` → ต่อท้าย `$LOG` และ echo บรรทัด `YYYY-MM-DD HH:MM:SS  LABEL — MESSAGE`
  - `proc_row PID` → `PID PPID PGID TPGID TTY <lstart 5 คำ> ARGS` จาก `TZ=UTC LC_ALL=C $PS_BIN -o pid=,ppid=,pgid=,tpgid=,tty=,lstart=,args= -p PID` คืน 1 ถ้าไม่มี pid นั้น (`TZ=UTC` เพราะ `procStart` ใน session file เป็น UTC ผล spike)
  - `proc_field PID ppid|pgid|tpgid|tty|start|args` (`start` = lstart ที่ยุบช่องว่างแล้ว), `proc_alive PID`, `proc_foreground PID` (pgid = tpgid)
  - `proc_children PID` → บรรทัด `PID ARGS` ของลูกโดยตรง จาก `$PS_BIN -A -o pid=,ppid=,args=`
  - `shell_ok ARGS` → 0 เมื่อ basename ของ argv[0] (ตัด `-` นำหน้า) เป็น `bash` หรือ `zsh` และไม่มีกลุ่ม option ก่อน operand ตัวแรกที่มี `c`
  - `bg_shells PID` → echo pid ของลูกโดยตรงที่ args มี `/shell-snapshots/snapshot-` (shell ของ background Bash ตามผล spike MCP server อย่าง `npm exec ...` ไม่นับ)
  - `sf_path PID` = `$CFG/sessions/PID.json`, `sf_get PID FIELD` → `jq -r ".FIELD // empty"`
  - `pid_for_sid SID` → pid ของ session file ที่ `sessionId` ตรง, process ยังอยู่ และ `procStart` (ยุบช่องว่าง) = `proc_field start` ถ้าได้มากกว่าหนึ่งหรือไม่ได้เลย echo ว่าง
  - `transcript_for SID` → path แรกที่ตรง `$CFG/projects/*/SID.jsonl` หรือว่าง
  - `run_detached CMD...` → รันใน process group ของตัวเองแบบ spec §2 (`set -m; "$@" </dev/null >>"$LOG" 2>&1 & p=$!; set +m` แล้ว `wait` ซ้ำจนได้ exit status จริง) คืน exit status ของคำสั่ง
- Produces (โลกปลอมใน `restart-all.test.sh` ที่ Task 4–7 ใช้ต่อ): `$FAKE` ชั่วคราว, `export CLAUDE_CONFIG_DIR=$FAKE/cfg`, fake bin ทั้งห้าตัวใน `$FAKE/bin` และ helper:
  - `fake_proc PID PPID PGID TPGID TTY ARGS` เพิ่มแถวใน `$FAKE/procs` (lstart = `Thu Oct  2 07:43:<PID%60> 2026` ตั้งใจให้มีช่องว่างคู่) `fake_kill PID` ลบแถว
  - `fake_session PID SID NAME STATUS CWD` เขียน session file ครบทุก field ที่ spec §ข้อเท็จจริง ระบุ (`kind:"interactive"`, `procStart` ตรงกับ `fake_proc`)
  - นาฬิกาปลอม: `$FAKE/now` (เริ่ม `1000000`), fake sleep บวกเวลาเข้าไปแล้ว `sleep 0.01` จริง (`KIT_FAKE_REAL_SLEEP` ตั้งให้หลับจริงได้ สำหรับ test สัญญาณใน Task 7)
  - `check LABEL STATUS` แบบ `reload-all.test.sh`

- [ ] **Step 1: เขียน test ที่ล้ม** (ส่วนหัวของ `restart-all.test.sh` + โลกปลอม + กรณีเหล่านี้)

```bash
fake_proc 101 100 101 101 ttys001 claude
[[ "$(proc_field 101 start)" == "Thu Oct 2 07:43:41 2026" ]]; check "lstart collapsed" $?
proc_foreground 101; check "foreground when pgid = tpgid" $?
fake_proc 102 100 102 999 ttys002 claude; ! proc_foreground 102; check "suspended is not foreground" $?
for a in '-zsh' '/opt/homebrew/bin/zsh' 'zsh -l' 'bash'; do shell_ok "$a"; check "shell ok: $a" $?; done
for a in 'bash -lc x' 'zsh -ic x' 'zsh -c x' 'sh -c x' 'fish' '/bin/sh'; do ! shell_ok "$a"; check "shell not ok: $a" $?; done
# pid_for_sid: ไฟล์ค้างของ pid ที่ตาย + ไฟล์ของ pid ที่ procStart ไม่ตรง + ไฟล์ที่ถูกต้องหนึ่งไฟล์
[[ "$(pid_for_sid S1)" == 201 ]]; check "pid_for_sid picks the live, matching file" $?
[[ -z "$(pid_for_sid S2)" ]]; check "pid_for_sid: two live matches is ambiguous" $?
fake_proc 301 101 301 101 ttys001 "/bin/zsh -c source $CFG/shell-snapshots/snapshot-zsh-1-x.sh && eval 'sleep 300'"
fake_proc 302 101 101 101 ttys001 "npm exec @playwright/mcp@latest"
[[ "$(bg_shells 101)" == 301 ]]; check "bg_shells finds the Bash shell, not the MCP server" $?
run_detached sh -c 'exit 3'; [[ $? == 3 ]]; check "run_detached returns the command's status" $?
```

- [ ] **Step 2:** รัน `bash plugins/kit-update/scripts/restart-all.test.sh` Expected: FAIL (ยังไม่มี `restart-lib.sh`)
- [ ] **Step 3:** เขียน `restart-lib.sh` ตาม Interfaces (ไฟล์นี้ไม่ทำงานเองเมื่อถูก source มีแค่ฟังก์ชันกับ `ku_paths`)
- [ ] **Step 4:** รัน test Expected: `all passed` และ `/bin/bash -n` ผ่านทั้งสองไฟล์
- [ ] **Step 5: Commit** `kit-update 0.2.0: restart-lib process and session helpers`

---

### Task 4: `restart-lib.sh` ส่วน transcript

**Files:**
- Modify: `plugins/kit-update/scripts/restart-lib.sh`
- Test: `plugins/kit-update/scripts/restart-all.test.sh`

**Interfaces:**
- Produces:
  - `answer_state FILE OFFSET NONCE IDLE OUT` → echo `VERDICT<TAB>END_OFFSET<TAB>DETAIL` โดย VERDICT เป็น `no-nonce` | `pending` | `stale` | `not-ready` | `handoff` | `invalid` ถ้าเป็น `handoff` เขียน text ของคำตอบลง `OUT` ถ้าเป็น `not-ready` DETAIL คือเหตุผลหลัง `NOT-READY` (ตัด `:` และช่องว่าง) END_OFFSET = OFFSET + จำนวน byte ถึง `\n` ตัวสุดท้ายของส่วนที่อ่าน `IDLE` เป็น `1` เมื่อ pane ว่างอยู่ตอนนี้
  - `activity_after FILE OFFSET` → 0 ถ้าหลัง OFFSET มี prompt entry หรือ entry ของ Claude
  - `is_prompt` ของ jq (ใช้ร่วมกันสองฟังก์ชัน): `type=="user"` ที่ content เป็น string และไม่ใช่ `isMeta` หรือ `type=="attachment"` ที่ `attachment.type=="queued_command"` (ข้อความอยู่ที่ `attachment.prompt`)
- อ่านด้วย `tail -c +$((OFFSET+1)) FILE | jq -R 'fromjson?'` เท่านั้น ห้ามอ่านทั้งไฟล์ กฎของ verdict ตาม spec §3 ขั้น 3 ไล่ตามลำดับนี้:
  1. ไม่มี prompt entry ที่ขึ้นต้นด้วย `[kit-update restart NONCE]` หลังตัดส่วนนำหน้า `^\s*<pasted_content id="[^"]*">\s*` ออก (ถ้ามี) → `no-nonce` ถ้า nonce entry เป็น `queued_command` → `stale`
  2. prompt entry หลัง nonce entry → `stale` ยกเว้น `queued_command` ที่ `commandMode=="task-notification"` ซึ่งอยู่ก่อน entry แรกของ Claude
  3. entry ของ Claude ที่มี `tool_use` หรือ `stop_reason=="tool_use"` ก่อนคำตอบจบ → `invalid` (`tool call`)
  4. `stop_reason` null หรือ `type:"user"` ที่ content เป็น array และมี text `[Request interrupted by user` → `stale`
  5. message แรก (นับตาม `message.id`) ที่ `stop_reason` ไม่ใช่ `tool_use` ยังไม่มี → `pending` มีแล้วแต่หลังมันมี entry ของ Claude ที่ `message.id` อื่น → `stale` มีแล้วและไม่มีอะไรตามมาแต่ `IDLE` ไม่ใช่ `1` → `pending`
  6. มี `<synthetic>` / `isApiErrorMessage` → `invalid` (`api error`), `stop_reason` ไม่ใช่ `end_turn` → `invalid` (`stop_reason <x>`)
  7. text ของทุก entry ในคำตอบต่อกัน ตัดช่องว่าง `*` และ backtick ที่นำหน้าแล้วขึ้นต้นด้วย `NOT-READY` → `not-ready` มีครบทั้ง `เป้าหมาย` `ทำเสร็จ` `ค้าง` `ตัดสินใจ` `ไฟล์` `ขั้นต่อไป` → `handoff` ไม่งั้น `invalid` (`missing headings: ...`)

- [ ] **Step 1: เขียน test ที่ล้ม** เพิ่ม helper สร้างบรรทัด jsonl: `j_prompt TEXT`, `j_queued MODE TEXT`, `j_asst ID STOP KIND TEXT` (KIND = `text`/`thinking`/`tool_use`), `j_synthetic`, `j_interrupt`, `j_routine` (ออก `system`, `attachment` แบบ `total_tokens_reminder`, `file-history-snapshot`, `last-prompt`, `custom-title`) แล้วกรณี (label = ผลที่ต้องได้):
  - `handoff: thinking + text of one message` (สอง entry `message.id` เดียวกัน `end_turn` ทั้งคู่) → `handoff` และ OUT มี text ของ entry ที่สอง
  - `handoff: nonce entry wrapped in pasted_content` (content = `"\n\n<pasted_content id=\"5444\">\n[kit-update restart N] ..."`) → `handoff`
  - `stale: task notification as a user string after the answer` (`j_prompt '<task-notification>...'`) → `stale`
  - `handoff: routine entries after are ignored` → `handoff`
  - `handoff: start-of-session task notifications before the answer` (`j_queued task-notification` สองตัวหลัง nonce) → `handoff`
  - `not-ready: plain / ** / backtick / leading spaces` สี่แบบ → `not-ready` และ DETAIL = `bg job`
  - `handoff mentioning NOT-READY inside` → `handoff`
  - `invalid: tool_use` / `api error` / `max_tokens` / `missing heading` → `invalid` พร้อม DETAIL ที่ระบุ
  - `stale: prompt after answer` / `assistant message after answer` / `queued prompt before answer` / `task notification after the answer started` / `interrupted` / `nonce entry is queued` → `stale`
  - `no-nonce: nonce only inside api-request-blob or a tool_result` และ `no-nonce: other nonce` → `no-nonce`
  - `pending: answer ended but pane not idle` (IDLE=0) → `pending`
  - `partial last line: ignored, end offset before it` (ไฟล์จบด้วยครึ่งบรรทัดที่ไม่มี `\n`) → END_OFFSET = ขนาดไฟล์ลบความยาวครึ่งบรรทัด
  - `offset in the middle: earlier nonce is not seen` (มี nonce เดียวกันก่อน OFFSET) → `no-nonce`
  - `activity_after: prompt / queued / assistant` → 0, `activity_after: routine only` → 1
- [ ] **Step 2:** รัน test Expected: FAIL ที่กรณีใหม่
- [ ] **Step 3:** เขียน `answer_state` และ `activity_after` (jq program เดียวที่ `-s` รับ entry ทั้งหมดแล้วคืน verdict ไม่ต้องวน bash ต่อบรรทัด)
- [ ] **Step 4:** รัน test Expected: `all passed`
- [ ] **Step 5: Commit** `kit-update 0.2.0: restart-lib transcript reading`

---

### Task 5: `restart-all.sh` (lock, snapshot, state, เปิด worker)

**Files:**
- Create: `plugins/kit-update/scripts/restart-all.sh`
- Test: `plugins/kit-update/scripts/restart-all.test.sh`

**Interfaces:**
- Consumes: Task 3 ทั้งหมด, `screen_state`/`prompt_empty` (ใช้แค่รายงานตอน snapshot ไม่กรอง pane ที่ไม่ว่าง เพราะ worker รอเอง)
- Produces:
  - ไฟล์ lock `$LOCK/owner` (เขียนผ่านไฟล์ชั่วคราว + `mv`): บรรทัดเดียว `starting <token>` หรือ `<token> <pid> <pane>` ตามด้วยบรรทัด `cmd <command line>` ของ worker
  - `lock_token` → token ใน owner, `lock_release TOKEN` → ลบ `$LOCK` เฉพาะเมื่อ token ตรง (สองตัวนี้อยู่ใน `restart-lib.sh` เพราะ worker ใช้ด้วย)
  - `$LOCK/state.<token>` (TSV): บรรทัด `config<TAB><CFG>`, `socket<TAB><socket หรือว่าง>`, `mux<TAB>herdr|tmux` (multiplexer ของ worker) และหนึ่งบรรทัดต่อ pane: `pane<TAB>MUX<TAB>PANE_ID<TAB>LABEL<TAB>PID<TAB>PROCSTART<TAB>TTY<TAB>SHELL_PID<TAB>SID<TAB>NAME<TAB>VERSION<TAB>CWD<TAB>ISSUER(0/1)<TAB>AGENT_NAME<TAB>CMDLINE` (แทน tab ใน field ด้วยช่องว่าง) SHELL_PID = ppid ของ Claude (tmux ที่ Claude เป็น `#{pane_pid}` เอง ให้เป็น `-`)
  - คำสั่งเปิด worker: `bash <path เต็มของ restart-worker.sh> <path เต็มของ state.<token>>` worker หา token จากชื่อไฟล์ (ส่ง path แทน token เปล่า เพราะ worker ที่เปิดใน herdr ไม่ได้ `CLAUDE_CONFIG_DIR` ของตัวเรียก)
  - output: บรรทัด `Restarting N session(s) when idle:` + รายชื่อ, `Skipped:` + เหตุผล, `This session: in the snapshot, goes last` หรือ `This session: not found — restart it yourself`, `Worker: <herdr pane id หรือ tmux session>`, `Log: <LOG>`, `Handoffs: <HANDOFFS>`
- ลำดับตาม spec §2 ขั้น 1–4 snapshot ตามกฎ spec §2 ขั้น 2 ทุกข้อ (tmux: `list-panes -a -F '#{pane_id}<TAB>#{session_name}:#{window_index}.#{pane_index}<TAB>#{pane_pid}'` แล้วหา Claude จาก `#{pane_pid}` หรือลูกโดยตรง, herdr: `agent list` → `agent_session.value` → `pid_for_sid`) herdr agent ที่ Claude มี `tmux` เป็นบรรพบุรุษถูกตัดทิ้งเสมอ แม้ฝั่ง tmux จะไม่อยู่ในรายการ issuer = pid ใน snapshot ที่เป็นบรรพบุรุษของ `$$` ตามสาย ppid
- herdr: `herdr workspace create --label "kit-update restart <HHMMSS>" --no-focus` → `.result.root_pane.pane_id` → `run_detached herdr pane run <pane> <คำสั่งเปิด worker>` tmux: `tmux [-S socket] new-session -d -s kit-update-restart-<HHMMSS> -c "$KU_DIR"` แล้ว `send-keys -t <session> -l <คำสั่ง> \; send-keys -t <session> Enter` ถ้า `<HHMMSS>` ชนกับของรอบก่อน เติม `-2`, `-3`

- [ ] **Step 1: เขียน test ที่ล้ม** ขยาย fake tmux/herdr ของ `reload-all.test.sh` ให้รู้จัก `list-panes` แบบใหม่, `display -p`, `new-session`, `workspace create` (คืน json ที่มี `.result.root_pane.pane_id`), `pane run` (บันทึกลง `$FAKE/ran`) แล้วกรณี:
  - `no server: says so, no lock left`
  - `herdr: pid found through agent_session and session file` / `herdr: parent shell zsh -ic is skipped` / `herdr: login shell -zsh is kept`
  - `tmux in herdr: kept once, on the tmux side` / `two live processes share a sessionId: both skipped` / `kind not interactive: skipped` / `session file missing status: skipped` / `tmux wrapper process: skipped` / `teammate: skipped` (args มี `--team-name`, `--agent-id` หรือ `--parent-session-id` ตามผล spike ซึ่งยังไม่ยืนยัน)
  - `issuer found through the ppid chain` / `issuer not in snapshot: says so`
  - `launch in herdr when HERDR_ENV is set` (ตรวจ label, `pane run` ได้คำสั่งที่ `<= 1024` byte และชี้ state ที่มีอยู่จริง) / `launch in tmux when only TMUX is set` (ตรวจ `new-session -d -s kit-update-restart-` และ socket ใน state) / `neither HERDR_ENV nor TMUX: uses the multiplexer that has a server` / `herdr agent with tmux ancestor not in the tmux list: still dropped`
  - lock: `running worker: reports its pane, no second launch` / `fresh starting lock: no launch` / `empty lock dir under 60s: no launch` / `dead worker pid: takes over` / `starting older than 60s: takes over` / `two callers on a stale lock: exactly one launch, the winner's lock survives` (รันสองตัวพร้อมกันด้วย `&` แล้วตรวจว่า `lock_token` = token ใน state ที่ถูกเปิด) / `lost the lock after writing state: no launch` / `launch fails: lock removed`
  - `second run while previous worker pane is open` (มี `kit-update-restart-<HHMMSS>` อยู่แล้วและเวลาเดียวกัน) → ได้ชื่อ `-2`
  - `state rows carry every field` (ตรวจทุกคอลัมน์ของหนึ่งแถว)
- [ ] **Step 2:** รัน test Expected: FAIL ที่กรณีใหม่
- [ ] **Step 3:** เขียน `restart-all.sh` (header comment แบบ `reload-all.sh` อธิบายขั้นตอนและสิ่งที่ไม่ทำ) และ `lock_token` / `lock_release` ใน lib ใช้ `restart-worker.sh` ชั่วคราวที่แค่ `exit 0` ให้ test path มีไฟล์อยู่จริง (Task 6 เขียนทับ)
- [ ] **Step 4:** รัน test Expected: `all passed` แล้วรัน `bash plugins/kit-update/scripts/reload-all.test.sh` Expected: `all passed`
- [ ] **Step 5: Commit** `kit-update 0.2.0: restart-all.sh snapshot and worker launch`

---

### Task 6: worker ส่วนขอและอ่าน handoff (spec §3 กติกาที่ใช้ทุกขั้น + ขั้น 1–3)

**Files:**
- Create: `plugins/kit-update/scripts/restart-worker.sh` (แทนตัวชั่วคราวของ Task 5)
- Test: `plugins/kit-update/scripts/restart-all.test.sh`

**Interfaces:**
- Consumes: state format และ `lock_token`/`lock_release` จาก Task 5, `answer_state`/`activity_after` จาก Task 4
- Produces:
  - `restart-worker.sh STATE_PATH`: ถ้า `lock_token` ไม่ใช่ token จากชื่อไฟล์ → `exit 0` โดยไม่แตะ pane ไม่งั้นเขียน owner เป็น `<token> $$ <pane ของตัวเอง>`
  - array ต่อ pane (index ตรงกับแถวใน state): ค่าจาก state + `PH` (phase), `NONCE`, `OFF`, `BASE_OFF`, `BASE_SUA`, `ASKED`, `NEXT_ASK`, `FAILS`, `WHY` (เหตุผลล่าสุดที่ยังไม่พร้อม ใช้ตอนข้ามที่เพดาน), `HANDOFF` (path ไฟล์)
  - phase: `wait` → `asked` → (`notready` → `wait`) | `ready` | `wait` (ตกรุ่น/ไม่ผ่าน) และสถานะจบ `skipped:<reason>` / `gone` / `done` ในขั้นนี้ `ready` จบเป็น `skipped:exit not implemented` ชั่วคราว (Task 7 แทน)
  - `identity_ok i` → 0/1/2 (ผ่าน / gone / แค่ไม่อยู่หน้าสุด) ตาม spec §3 "ตรวจตัวตน" (pid, `procStart`, tty, pane ยังอยู่, หน้าสุด)
  - `pane_sendable i` → 0 เมื่อ session file `status=="idle"`, จอว่าง (herdr: `idle`/`done` + `prompt_empty`; tmux: `screen_state` เป็น `idle`), ไม่ได้ scroll อยู่ (tmux `#{pane_in_mode}` เป็น `0`; herdr `pane get` `.result.pane.scroll.offset_from_bottom` เป็น `0`) และ `bg_shells` ว่าง ห้ามใช้ `herdr pane process-info` (คืน JSON เสียเมื่อ cmdline มีขึ้นบรรทัดใหม่)
  - `send_request i` → จด `OFF` (ขนาด transcript หรือ `0` ถ้ายังไม่มีไฟล์) ก่อน เขียนข้อความขอ handoff ลง `$LOCK/request-<nonce>.txt` ด้วย `printf '%s'` (ไม่มี `\n` ท้าย, หายไปพร้อม lock) แล้วส่ง (herdr: `agent prompt <pane> <text>` ไม่มี `--wait`; tmux: `load-buffer -b kit-update-<nonce> <file> \; paste-buffer -b kit-update-<nonce> -p -d -t <pane> \; send-keys -t <pane> Enter`) ผ่าน `run_detached` ไม่ดูผลของคำสั่ง
  - nonce = 16 ตัว hex จาก `/dev/urandom` (`od -An -tx1`)
  - log ต่อ pane ผ่าน `ku_log <LABEL>` และตอนจบ `Summary  restarted: N · skipped: M` + รายการแบบ `reload-all.sh`
- กติกาการจัดคิวตาม spec §3: ช่อง 2 ช่องนับเฉพาะ pane ใน `asked`, pane ที่ `pane_sendable` ผ่านแต่ไม่ได้ช่องถือว่า "รอช่อง" ในรอบนั้น, issuer ส่งคำขอได้เมื่อไม่มี pane อื่นใน `asked`, ไม่มี pane อื่นรอช่อง และไม่มี pane อื่นที่ส่ง `/exit` แล้วแต่ยังไม่จบ (Task 7 เพิ่ม phase พวกนั้น), เพดานของ issuer นับจากรอบแรกที่เงื่อนไขนี้เป็นจริง
- กรณี `asked`: `sessionId` เปลี่ยน → `wait` (ไม่นับว่าล้มเหลว), `no-nonce` เกิน 30 วินาทีโดย `status` ไม่เคยเป็น `busy` → `skipped:request not submitted` ถ้าเคย `busy` รอจนครบ 900 วินาที (ถ้า `transcript_for` ยังว่างตอนครบเวลา นับเป็นไม่ผ่าน `no transcript` ตามกฎขอใหม่ ไม่ใช่ request not submitted), `pending` เกิน 900 วินาที → นับเป็นไม่ผ่าน, `stale` → `wait` และ `NEXT_ASK=ASKED+1800`, `not-ready` → `notready` + จุดเทียบ + `NEXT_ASK=ASKED+1800`, `invalid` → `FAILS++` ถึง 3 → `skipped:no valid handoff` ไม่งั้น `NEXT_ASK=now+300`, `handoff` → เขียน `$HANDOFFS/<YYYYMMDD-HHMMSS>-<ชื่อ>-<pane>.md` (แทนอักขระนอก `[A-Za-z0-9_-]` ด้วย `_`, ส่วนชื่อ `<= 40` byte) + จุดเทียบ → `ready`
- จุดเทียบ (`BASE_OFF`, `BASE_SUA`): END_OFFSET จาก `answer_state` และ `statusUpdatedAt` ในรอบที่ได้ verdict (verdict `handoff`/`not-ready` ออกได้เฉพาะตอน `IDLE=1`) `notready` → `wait` เมื่อ `sessionId` เปลี่ยน, `statusUpdatedAt` ≠ `BASE_SUA` หรือ `activity_after FILE BASE_OFF`

- [ ] **Step 1: เขียน test ที่ล้ม** เพิ่ม fake Claude ใน fake tmux/herdr: เมื่อได้ข้อความที่ขึ้นต้น `[kit-update restart ` ให้เรียก `$FAKE/react <pane> <nonce>` ซึ่งอ่าน scenario จาก `$FAKE/scenario-<pane>` (`handoff`, `not-ready`, `tool`, `api-error`, `max-tokens`, `no-heading`, `silent`, `queued-after`, `busy-silent`) แล้วต่อท้าย transcript ของ session นั้นและตั้ง `status` กลับเป็น `idle` แล้วกรณี:
  - `idle herdr pane: request sent, handoff file written` (ตรวจข้อความตรงกับ spec §3 ขั้น 2 ทุกตัวอักษรหลัง nonce และชื่อไฟล์ตามรูปแบบ)
  - `idle tmux pane: named buffer, paste -p, Enter in the same call`
  - `busy then idle: asked only after idle` / `blocked until the cap: skipped, no keys` / `background shell child: waits without asking`
  - `suspended (pgid != tpgid) with ❯ screen: no keys` / `tmux copy mode: no keys until it leaves, then asked` / `herdr pane scrolled up: no keys until back at the bottom` / `status shell (background shell): waits without asking`
  - `token mismatch: worker exits without touching panes`
  - `pid reused (procStart differs): gone` / `tty differs: gone` / `herdr pane vanished: gone`
  - `not-ready: no re-ask before activity and 30 min` (activity ที่ 5 นาที → ถามใหม่ที่ 30 นาที ไม่ใช่ 5) / `not-ready: reason is in the log` / `not-ready then /clear: new sessionId counts as activity` / `activity of another session in the same folder does not count`
  - `new session without a transcript yet: offset 0, answer read`
  - `/loop activity every 3 min: asked at most every 30 min`
  - `stale (queued prompt): re-asked after 30 min without activity`
  - `invalid x3: skipped no valid handoff, 5 min apart, never /exit`
  - `request not submitted: no nonce in 30s, then no more keys` / `busy after send: keeps waiting past 30s`
  - `sessionId changes while asked: back to wait, not a failure`
  - `three idle panes: at most two asked at once`
  - `issuer goes last` / `issuer still runs while another pane is NOT-READY forever` / `issuer still runs while another pane has a background shell forever` / `issuer does not jump a pane waiting for a slot`
- [ ] **Step 2:** รัน test Expected: FAIL ที่กรณีใหม่
- [ ] **Step 3:** เขียน `restart-worker.sh` (loop: ทุก `ku_nap 10` ไล่ advance ทุก pane หนึ่งก้าว จบเมื่อทุก pane อยู่ในสถานะจบ แล้วพิมพ์ Summary และ `lock_release`)
- [ ] **Step 4:** รัน test Expected: `all passed` (test ทั้งไฟล์ต้องจบใน 60 วินาทีด้วยนาฬิกาปลอม)
- [ ] **Step 5: Commit** `kit-update 0.2.0: restart worker collects handoffs`

---

### Task 7: worker ส่วนปิด เปิดใหม่ ยืนยัน และสัญญาณ (spec §2 "หยุด worker" + §3 ขั้น 4–6)

**Files:**
- Modify: `plugins/kit-update/scripts/restart-worker.sh`
- Test: `plugins/kit-update/scripts/restart-all.test.sh`

**Interfaces:**
- Consumes: Task 6 ทั้งหมด
- Produces:
  - phase ใหม่หลัง `ready`: `exiting` → `relaunching` → `confirming` → `done` | `skipped:<reason>` (เหตุผลตาม spec: `did not exit`, `relaunch command too long`, `shell not in front`, `relaunch failed`, `started, waiting on screen` นับเป็น restarted)
  - `relaunch_line i` → บรรทัดคำสั่งที่จะพิมพ์ `claude --name <printf %q ชื่อ> "$(cat <printf %q ไฟล์ start>)"` ไฟล์ start = `<handoff>.start.md` (บรรทัดหัว + handoff + บรรทัดท้าย ตาม spec §3 ขั้น 5)
  - ชื่อที่เปิดใหม่: `NAME` จาก session file ถ้าว่าง herdr ใช้ `AGENT_NAME` หรือ label ของ workspace, tmux ใช้ชื่อ session
  - tmux: `ROE` ต่อ pane = `show-options -p -v -t <pane> remain-on-exit` ก่อนตั้ง (ว่าง = ไม่ได้ตั้งที่ระดับ pane) คืนค่าด้วย `set-option -p ... <ค่าเดิม>` หรือ `set-option -pu` ทุกทางออกหลังตั้ง
- `ready`: ต้องผ่าน `identity_ok`, `pane_sendable`, ไม่มีความเคลื่อนไหวหลังจุดเทียบ (มี → `wait`, `NEXT_ASK=ASKED+1800`), สร้าง `relaunch_line` บันทึกลง log และถ้ายาวเกิน 1024 byte → `skipped:relaunch command too long` ก่อน `/exit` แล้ว tmux ตั้ง `remain-on-exit on` แล้วส่ง `/exit` (herdr `agent prompt`; tmux `send-keys -l /exit \; send-keys Enter`) → `exiting` ไม่ว่าคำสั่งส่งจะคืนอะไร
- `exiting`: pid หาย → `relaunching` (ตั้งแต่นี้ไม่เรียก `identity_ok` herdr ดู pane จาก `herdr pane list`) เกิน 60 วินาที → `skipped:did not exit` + คืน ROE
- `relaunching`: tmux ที่ `#{pane_dead}` เป็น `1` → `respawn-pane -t <pane> -c <CWD> /bin/sh -c 'exec claude --name "$1" "$(cat "$2")"' sh <ชื่อ> <ไฟล์ start>` (ลองซ้ำได้หนึ่งครั้ง) ไม่งั้นรอให้ `SHELL_PID` อยู่หน้าสุดสูงสุด 10 วินาที (เช็กทุก 1 วินาทีด้วย `ku_nap 1`) แล้วส่ง `relaunch_line` (herdr `pane run`; tmux `send-keys -l <line> \; send-keys Enter`) ไม่ทันก็ `skipped:shell not in front` และบันทึกคำสั่ง แล้วคืน ROE → `confirming`
- `confirming`: ภายใน 60 วินาทีมี session file ใหม่ที่ pid เป็นลูกของ `SHELL_PID` (respawn: เป็น `#{pane_pid}` หรือลูกของมัน) → herdr ที่มี `AGENT_NAME` เรียก `agent rename <pane> <AGENT_NAME>` → `done` ถ้ามีแค่ process `claude` ใหม่ → `done` พร้อมหมายเหตุ `started, waiting on screen` ไม่มีทั้งสอง → `skipped:relaunch failed` + คำสั่ง
- issuer gating ของ Task 6 นับ `exiting`/`relaunching`/`confirming` เป็น "ส่ง `/exit` แล้วแต่ยังไม่จบ" ส่วน `ready` ไม่นับ เพดาน 4 ชั่วโมงใช้กับ `ready` ด้วย แต่ไม่ใช้กับสาม phase หลัง
- สัญญาณ: `trap` `INT`/`TERM` → `STOPPING=1`, `HUP` → `STOPPING=1; trap '' PIPE; exec >/dev/null 2>&1` เมื่อ `STOPPING=1` pane ที่ยังไม่ส่ง `/exit` จบเป็น `skipped:stopped` (tmux ที่ตั้ง ROE แล้วต้องคืน) pane ที่ส่งแล้วทำต่อจนจบ แล้ว `lock_release`

- [ ] **Step 1: เขียน test ที่ล้ม** fake Claude เพิ่ม: `/exit` → `fake_kill` pid + ลบ session file (scenario `no-exit` ไม่ทำอะไร), fake shell ของ pane รันบรรทัดที่ได้ด้วย `bash -c` โดย PATH มี fake `claude` ที่เขียน argv ลง `$FAKE/argv-<pane>` (คั่นด้วย NUL) แล้วสร้าง pid + session file ใหม่ (scenario `dialog` สร้างแค่ process, `nostart` ไม่สร้าง) fake tmux `respawn-pane` รัน argv หลัง `-c <dir>` ด้วย `cd <dir>`, fake herdr ปฏิเสธ `pane run` ที่ยาวเกิน 1024 byte และ `agent rename` ที่ชื่อไม่ตรง `[a-z][a-z0-9_-]{0,31}` แล้วกรณี:
  - `herdr full restart: handoff, /exit, relaunch, rename, Summary restarted`
  - `relaunch argv survives hostile name and handoff` (ชื่อ `งาน/ก'ข "ค" $x` + handoff ที่มี `$(touch $FAKE/pwned)`, backtick, `"`, บรรทัด `-p`) → argv[1]=`--name`, argv[2]=ชื่อตรงตัว, argv[3]=เนื้อหาไฟล์ start ตรงตัว และไม่มี `$FAKE/pwned`
  - `relaunch line over 1024 bytes: skipped before /exit`
  - `tmux: remain-on-exit set before /exit and restored with -pu` / `tmux: previous pane value restored` / `restored on did not exit` / `restored when stopped after setting it`
  - `tmux pane died with claude: respawn-pane argv with exec` / `tmux pane whose shell is sh -c: respawned` / `respawn uses cwd with spaces` / `tmux shell alive: send-keys line and Enter in one call`
  - `shell not in front for 10s (vim): no relaunch keys, command logged` / `shell back in front after 3s: relaunched`
  - `did not exit within 60s` / `/exit send fails but claude exits: still relaunched`
  - `dialog on first start: started, waiting on screen` / `nothing started: relaunch failed with the command`
  - `activity after the handoff: no /exit, asked again later`
  - `cap reached while exiting: relaunch still completes` / `pane stuck in ready (copy mode) does not hold the issuer back, skipped at the cap`
  - `unnamed herdr agent: no rename, label fallback`
  - `INT to the worker group while sleeping: trap runs, waiting panes stopped, exiting pane finishes, lock released` (ตั้ง `KIT_FAKE_REAL_SLEEP=1`, รัน worker ด้วย `set -m` ให้ได้ group ของตัวเอง แล้ว `kill -INT -<pgid>`)
  - `INT while pane run is in flight: the command completes and is not sent twice` (fake `pane run` หลับจริง 1 วินาที)
  - `HUP with stdout closed: worker keeps going and finishes the relaunch` (`kill -HUP -<pgid>` แล้วปิดไฟล์ที่ stdout ชี้)
- [ ] **Step 2:** รัน test Expected: FAIL ที่กรณีใหม่
- [ ] **Step 3:** เขียนส่วนที่เหลือของ worker ลบสถานะชั่วคราว `skipped:exit not implemented`
- [ ] **Step 4:** รัน test Expected: `all passed` และ `grep -n 'exit not implemented' plugins/kit-update/scripts/` ไม่เจอ
- [ ] **Step 5: Commit** `kit-update 0.2.0: restart worker exits and relaunches`

---

### Task 8: คำสั่ง, เอกสาร, manifest

**Files:**
- Create: `plugins/kit-update/commands/restart.md`
- Modify: `plugins/kit-update/.claude-plugin/plugin.json` (description), `.claude-plugin/marketplace.json:26`, `README.md:49-65`, `CLAUDE.md:12,22`, `guides/tmux-remote-control.md:69,144`

**Interfaces:**
- Consumes: output ของ `restart-all.sh` (Task 5)

- [ ] **Step 1:** `restart.md` รูปแบบเดียวกับ `reload.md`: frontmatter `description: Restart every Claude Code session in tmux or herdr when idle, each with a handoff as its first message` สั่งรัน `bash "${CLAUDE_PLUGIN_ROOT}/scripts/restart-all.sh"` ครั้งเดียว แล้วให้รายงานตาม spec §2 ย่อหน้า `restart.md` (จำนวนและชื่อ session, restart ตอนว่าง, session นี้ไปหลังสุด หรือต้องปิดเปิดเองถ้าสคริปต์บอกว่าไม่เจอ, pane ของ worker, path ของ log และ handoff, จบโดยไม่ถามอะไร) กฎ: ห้ามพิมพ์ลง pane เอง ห้ามรันซ้ำ และบรรทัด `ARGUMENTS:` แบบเดียวกับ `reload.md`
- [ ] **Step 2:** README ตาม spec §5 ครบทุกข้อ (รวม "command ทั้งห้า" → "ทั้งหก", best effort ของ subagent/teammate/`/loop`/คำถาม, process เบื้องหลังที่รันตลอดทำให้ไม่ถูก restart และถูกข้ามหลัง 4 ชั่วโมง, flag ที่ไม่ตามมา, shell ต้องเป็น bash/zsh, Ctrl-C ใน pane ของ worker, `restart-all.sh` รันจาก terminal ได้) `plugin.json` และ marketplace description พูดถึง restart เป็นภาษาไทย `CLAUDE.md` บรรทัด 12 เพิ่ม `scripts/restart-all.sh` บรรทัดคำสั่ง test เพิ่ม `bash plugins/kit-update/scripts/restart-all.test.sh` guide สองจุดเพิ่ม `/kit-update:restart`
- [ ] **Step 3:** รัน `claude plugin validate ./plugins/kit-update` Expected: ผ่าน ไม่มี error แล้วรัน test ทั้งสองไฟล์ Expected: `all passed`
- [ ] **Step 4:** `grep -rn '/Users/' plugins/kit-update README.md guides CLAUDE.md` ไม่เจอ และอ่าน `git diff main --stat` ว่าไม่มีไฟล์แปลกปน
- [ ] **Step 5: Commit** `kit-update 0.2.0: /kit-update:restart command and docs`

---

### Task 9: ทดสอบกับของจริง (ทำใน main session ขอกิตก่อนเริ่ม)

แยกจาก session จริงของกิตด้วย `CLAUDE_CONFIG_DIR` ชั่วคราว (snapshot จะหา session file ของ session จริงไม่เจอแล้วข้ามทุกตัวโดยไม่พิมพ์อะไรลงไป) และ tmux socket แยก (`KIT_UPDATE_TMUX_BIN` ชี้ไป wrapper `exec tmux -L kit-e2e "$@"`) Task 1 ยืนยันแล้วว่า config ชั่วคราวต้อง `/login` ให้กิตทำเองใน pane ทิ้งหนึ่งครั้ง (เปิดครั้งแรกในโฟลเดอร์ใหม่จะมี dialog trust folder ที่ค่าเริ่มเป็น `No, exit` ด้วย ให้กิตกดเอง)

- [ ] **Step 1: herdr** สร้าง workspace ทิ้ง เปิด `CLAUDE_CONFIG_DIR=<tmp> claude --name e2e` คุยสั้น ๆ หนึ่งรอบ แล้วรัน `CLAUDE_CONFIG_DIR=<tmp> bash plugins/kit-update/scripts/restart-all.sh` จาก shell อีก pane Expected: output บอก 1 session จะ restart, session จริงของกิตอยู่ใน Skipped ทั้งหมด, ภายในไม่กี่นาทีได้ไฟล์ handoff, pane เดิมขึ้น Claude ใหม่ชื่อ `e2e` ที่ข้อความแรกขึ้นต้น `[kit-update restart]` และสรุปแล้วรอ, `Summary restarted: 1`
- [ ] **Step 2: tmux** ทำแบบเดียวกันใน `tmux -L kit-e2e new -s e2e "claude --name e2e"` (แบบ `cc` ที่ Claude เป็น process หลัก) Expected: `respawn-pane` ทำงาน, `remain-on-exit` ของ pane กลับไปไม่ได้ตั้งค่า
- [ ] **Step 3: Ctrl-C** รันใหม่โดยให้ Claude ทิ้งทำงานยาว ๆ อยู่ แล้วกด Ctrl-C ใน pane ของ worker Expected: worker จบ, lock หาย, Claude ทิ้งไม่ถูกแตะ
- [ ] **Step 4:** ปิด workspace, `tmux -L kit-e2e kill-server`, ลบ config ชั่วคราว บันทึกผลสั้น ๆ ลงหัวข้อผล spike ของ spec แล้ว commit `kit-update 0.2.0: end-to-end results`

---

### Task 10: PR และเว็บ (ขอกิตก่อน push ทุกครั้ง)

- [ ] **Step 1:** อ่าน `git diff main...kit-update-restart` ของ mods ทั้งหมด (repo public) หาชื่อส่วนตัวและ path ของเครื่อง แล้วขอกิตก่อน push และเปิด PR
- [ ] **Step 2:** เว็บ: อ่าน `phimee-and-kit-website/CLAUDE.md` หัวข้อ "Keeping the Tools section in sync with the mods" แล้วเพิ่ม `/kit-update:restart` ตาม checklist เป็น PR แยก (ขอกิตก่อน push)

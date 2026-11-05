# kit-update reload/restart บน herdr-core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/kit-update:reload` และ `/kit-update:restart` ใช้กับ Claude Code ที่รันใน terminal ของ herdr-core (`hc`) แทน herdr TUI โดยเช็กว่าว่างจากสถานะและหน้าจอที่มีสีเข้มเท่าฝั่ง tmux ฝั่ง tmux ไม่เปลี่ยน

**Architecture:** ตัวอ่านหน้าจอใหม่ `hc-screen.pl` (perl คุย `hc connect` แบบ framed แล้ว attach แบบ observe) ส่งหน้าจอแรกให้ `screen_tail` / `screen_state` เดิมใน `pane-lib.sh` ซึ่งได้ helper กลางสามตัว (`hc_call`, `hc_screen`, `hc_state`) ที่ reload และ worker ใช้ร่วมกัน `reload-all.sh`, `restart-all.sh`, `restart-worker.sh` แทนส่วน herdr ด้วย hc ทีละจุดตามตารางใน spec §4 test รันกับ fake `hc` และ fake ตัวอ่านหน้าจอ

**Tech Stack:** bash 3.2, `jq`, `/usr/bin/perl` 5.34 (core modules `IPC::Open2`, `JSON::PP`), hc 0.1.18, tmux 3.x, Claude Code 2.1.318

**Spec:** `docs/superpowers/specs/2026-11-05-kit-update-herdr-core-design.md` (อ้างเป็น "spec §N" / "ข้อเท็จจริงข้อ N") ส่วนที่ไม่ได้แก้ยังเป็นไปตาม `docs/superpowers/specs/2026-10-22-kit-update-restart-design.md` อ่านทั้งสองฉบับก่อนเริ่ม

## Global Constraints

- รันบน `/bin/bash` 3.2: ห้าม `declare -A`, `wait -n`, `mapfile`/`readarray`, `${x,,}`, `local -n` และใช้ `set -uo pipefail` (ไม่ใช้ `-e`) แบบไฟล์เดิม
- ทุกการเรียก `hc` จาก bash ผ่าน `hc_call` (Task 2) เท่านั้น ซึ่งรัน `env -u HC_TERMINAL_ID "${KIT_UPDATE_HC_BIN:-hc}"` ส่วน `hc-screen.pl` ลบ `HC_TERMINAL_ID` ออกจาก `%ENV` ก่อนเปิด `hc connect`
- `hc-screen.pl` ใช้แค่ perl core modules, attach ด้วย `observe: true` และห้ามส่ง DATA, RESIZE, FOCUS หรือ FACTS บน channel ของ attach (ส่งได้แค่ CREDIT และ CLOSE)
- ค่าคงที่: หมดเวลาอ่านหน้าจอ `5` วินาที, payload ของ frame เกิน `16777216` byte = ผิดรูป, header ของ frame `pack('VCV', channel, kind, len)` (9 byte), kind `0` DATA `1` CREDIT `2` CLOSE, ชื่อ worker `kit-update-restart-<HHMMSS>` ถ้าชนเติม `-2` ถึง `-9` (hc รับชื่อ 1–32 ตัว `a-z 0-9 - _`), exit code ของ `hc get` เมื่อไม่มี terminal = `3`
- ตัว override สำหรับ test มีแค่: `KIT_UPDATE_TMUX_BIN`, `KIT_UPDATE_HC_BIN`, `KIT_UPDATE_SCREEN_BIN`, `KIT_UPDATE_PS_BIN`, `KIT_UPDATE_CLOCK_BIN`, `KIT_UPDATE_SLEEP_BIN`, `CLAUDE_CONFIG_DIR` (`KIT_UPDATE_HERDR_BIN` หายไปพร้อม herdr)
- ห้ามเด็ดขาด (spec "สิ่งที่ต้องไม่เกิด"): `hc server stop`/`restart`, `hc kill`/`hc rm` terminal ที่ไม่ได้เปิดเอง, ส่งอะไรเข้า terminal จริงของกิตโดยกิตยังไม่สั่ง test ห้ามเรียก `hc` จริง
- การกดแป้นเข้า session ทุกครั้ง (`hc send`, tmux `send-keys`/`paste-buffer`/`respawn-pane`) ผ่าน `run_detached` และ worker ยังต้องผ่าน `identity_ok` + `pane_sendable` ก่อนทุกแป้นจนถึง `/exit` เหมือนเดิม
- tmux: test ฝั่ง tmux ทุกตัวที่มีอยู่ต้องผ่านโดยไม่แก้ assertion
- repo นี้ public: fixture ใช้ของสมมติ (`/x/alpha`, `t1`, `alpha work`) ห้ามมีชื่อ terminal, path หรือชื่องานจริงของเครื่อง
- version `0.3.0` (ตั้งใน Task 1) commit subject ขึ้นต้น `kit-update 0.3.0:` และปิด commit message ด้วยบรรทัด `Claude-Session:` ที่ session กำหนด
- **(Claude เลือก รอกิตยืนยัน)** บน macOS/Linux ทุกคำสั่ง `hc` รวม `hc server status` จะเปิด core เองถ้ายังไม่มี (`client.rs` `connect_or_start`, `platform/unix.rs` `status_may_start_core() -> true`) จึงไม่มีทางเช็กว่ามี server โดยไม่เปิด plan นี้ยอมรับพฤติกรรมนั้น: เครื่องที่ติดตั้ง `hc` ไว้จะได้ core ที่เปิดค้างหลังรันคำสั่งครั้งแรก และ README บอกไว้ (Task 5)

## Review Focus

1. หน้าจอใหญ่ที่ถูกแบ่งหลาย DATA frame และ frame สุดท้ายมีทั้งท้ายหน้าจอ เครื่องหมาย `\e[?9001` และ byte สดตามมา ต้องได้หน้าจอครบไม่มี byte สดปน → Task 1 `screen split over frames, live bytes after the mark`
2. `HC_TERMINAL_ID` หลุดไปถึง `hc` (ข้อความจะกลายเป็นแชต `<hc from>`) → Task 1 `connect runs without HC_TERMINAL_ID`, Task 2 `hc never sees HC_TERMINAL_ID`, Task 4 `worker: hc never sees HC_TERMINAL_ID`
3. แถวแรกของหน้าจอแรกมีชุด reset และ tab stop (`\e[?1l\e>\e(B\e[9G\eH…`) ติดอยู่ ต้องไม่เหลือ `HHH` และคำแนะนำตัวจางของ Claude ยังนับว่าช่องพิมพ์ว่าง → Task 2 `esc drops two-character escapes` และ `hc first paint with a dim suggestion counts as idle`
4. terminal ปิดไปหรือเป็น `finished` ระหว่าง `/exit` กับการเปิดใหม่ และ `hc get` ตอบผิดรูปหรือล้มชั่วคราว ต้องได้ gone เฉพาะเมื่อ not_found หรือ finished เท่านั้น → Task 4 `terminal finished after /exit: gone`, `hc get broken JSON after /exit: still relaunched`
5. worker ที่ `hc run` เปิดได้ environment ของ core ไม่ใช่ของคนสั่ง ถ้าไม่ส่ง `PATH`/`LANG` ไปจะหา `claude`/`jq` ไม่เจอหรือชื่อไทยเพี้ยน → Task 3 `launch in hc carries PATH and LANG` และ Task 6 ขั้น 3

---

## File Structure

```
plugins/kit-update/
  scripts/hc-screen.pl            ใหม่: พิมพ์หน้าจอปัจจุบันของ terminal แบบมี escape code (Task 1)
  scripts/hc-screen.test.sh       ใหม่: fake `hc connect` แบบ framed (Task 1)
  scripts/pane-lib.sh             esc() ตัด escape สองตัวอักษร + hc_call, hc_screen, hc_state (Task 2)
  scripts/reload-all.sh           ส่วน herdr → hc (Task 2)
  scripts/reload-all.test.sh      fake herdr → fake hc + fake screen (Task 2)
  scripts/restart-lib.sh          ku_paths: HC_BIN แทน HERDR_BIN (Task 4), helper สถานะ terminal (Task 4)
  scripts/restart-all.sh          snapshot และเปิด worker ผ่าน hc (Task 3)
  scripts/restart-worker.sh       ทุกจุดในตาราง spec §4 (Task 4)
  scripts/restart-all.test.sh     ส่วน snapshot (Task 3), ส่วน worker + ลบ fake herdr (Task 4)
  .claude-plugin/plugin.json      0.3.0 (Task 1), description (Task 5)
  commands/reload.md, restart.md, all.md, all-projects.md   (Task 5)
README.md, .claude-plugin/marketplace.json, CLAUDE.md, guides/tmux-remote-control.md   (Task 5)
```

---

### Task 1: ตัวอ่านหน้าจอ `hc-screen.pl`

**Files:**
- Create: `plugins/kit-update/scripts/hc-screen.pl`, `plugins/kit-update/scripts/hc-screen.test.sh`
- Modify: `plugins/kit-update/.claude-plugin/plugin.json` (version `0.3.0`)

**Interfaces:**
- Produces: `perl hc-screen.pl <terminal>` → stdout หน้าจอแถวละบรรทัด (escape code ครบ, ตัด `\r`, ปิดด้วย `\n`) exit 0 / ล้มเหลว: stdout ว่าง exit 1 อ่าน `KIT_UPDATE_HC_BIN` (default `hc`)

ลำดับการคุย (spec §1 + ข้อเท็จจริงข้อ 2–3) เป็นสิ่งที่ test ตรวจ ตัวโค้ดให้ builder เขียนเอง:
1. `delete $ENV{HC_TERMINAL_ID}` แล้ว `open2` กับ `$hc connect` ตั้ง `alarm 5` ไว้ก่อนอ่านอะไร (handler: ฆ่า child แล้ว exit 1 โดยไม่พิมพ์อะไร)
2. เขียน `{"jsonrpc":"2.0","id":0,"method":"hello","params":{"framed":true}}` + `\n` แล้วอ่านหนึ่งบรรทัด ต้องมี `result` (byte ที่เกินบรรทัดเก็บไว้เป็นต้น frame)
3. DATA channel 0: `terminal.get` (id 1, `{"terminal":T}`) แล้ว `terminal.attach` (id 2, `{"terminal":T,"cols":C,"rows":R,"observe":true}`) โดย C, R มาจาก result ของ get ข้อความบน channel 0 ที่ไม่มี id ที่รออยู่ (notification, heartbeat) ข้าม ถ้าคำตอบมี `error` = ล้มเหลว
4. DATA บน channel ของ attach ต่อเข้า buffer แล้วส่ง CREDIT (u32 LE ความยาว payload) ทุก frame frame ชนิดอื่นบน channel นั้น (เช่น RESIZE kind 3) ข้าม CLOSE บน channel ใดก็ตาม, len เกิน 16 MiB, EOF จาก `hc connect` = ล้มเหลว
5. เจอ `\e[?9001h` หรือ `\e[?9001l` ตัวแรกใน buffer: หน้าจอ = byte หลัง `\x18` ตัวแรกจนถึงก่อน `\e[?9001` (ไม่มี `\x18` ก่อนเครื่องหมาย = ล้มเหลว) ส่ง CLOSE บน channel นั้น ปิดฝั่งเขียน ฆ่าและ `waitpid` child แล้วพิมพ์หน้าจอ exit 0

- [ ] **Step 1: เขียน test ที่ล้ม** `hc-screen.test.sh` แบบเดียวกับ test อื่นใน `scripts/` (`check`, `FAKE=$(mktemp -d ...)`, `trap rm`, จบด้วย `all passed`) fake `$FAKE/hc` เป็น perl ที่ตอบ `connect` ตาม `$FAKE/scenario` และบันทึกลง `$FAKE/log`: แต่ละ JSON-RPC ที่ได้รับหนึ่งบรรทัด, `CREDIT <ch> <n>`, `CLOSE <ch>` และบรรทัด `env HC_TERMINAL_ID=<ค่าหรือ unset>` get ตอบ `cols` 123 `rows` 45 attach ตอบ `channel` 5 หน้าจอตัวอย่าง (`$FAKE/paint`) = `\x18` + `\e[?1l\e>\e(B\e[H\e[2J\e[9G\eH\e[17G\eH⏺ done\r\n\r\n❯\xc2\xa0\e[0m\e[2mคำรหัสของ session นี้คืออะไร\e[0m\r\n` แล้วตามด้วย `\e[?9001l` + `\e]7501;…\a` + `live bytes` รันด้วย `HC_TERMINAL_ID=t9 KIT_UPDATE_HC_BIN=$FAKE/hc perl hc-screen.pl t1` กรณี:
  - `ok: prints the screen without \r` stdout ตรงกับหน้าจอตัวอย่างที่ตัด `\r` ไม่มี `live bytes`, exit 0
  - `attach asks observe true with the size from terminal.get` log มี attach ที่ `observe` เป็น `true`, `cols` 123, `rows` 45, `terminal` `"t1"`
  - `connect runs without HC_TERMINAL_ID` log มี `env HC_TERMINAL_ID=unset`
  - `closes its channel when done` log มี `CLOSE 5` และไม่มี DATA ขาออกบน channel 5
  - `screen split over frames, live bytes after the mark` หน้าจอ 40 KiB (แถวยาว) ส่งเป็น DATA ทีละ 16 KiB frame สุดท้ายมีท้ายหน้าจอ + `\e[?9001h` + `live bytes` และมี RESIZE frame กับ notification บน channel 0 แทรกก่อนคำตอบ get → stdout ครบทุกแถว ไม่มี `live bytes`, log มี CREDIT รวมเท่าจำนวน byte ที่ส่ง
  - `rpc error: exit 1, no output` (get ตอบ `error` แบบ not_found)
  - `oversized frame header: exit 1, no output` (len = 16777217)
  - `CLOSE before the mark: exit 1, no output`
  - `connect exits at once: exit 1, no output`
  - `no end mark within 5 s: exit 1, no output` (fake ส่งหน้าจอแต่ไม่ส่งเครื่องหมายแล้วค้าง) ตรวจด้วยว่าจบภายใน 8 วินาทีและ fake ไม่ค้างอยู่ (`pgrep -f "$FAKE/hc"` ว่าง)
- [ ] **Step 2:** รัน `bash plugins/kit-update/scripts/hc-screen.test.sh` Expected: FAIL (ยังไม่มี `hc-screen.pl`)
- [ ] **Step 3:** เขียน `hc-screen.pl` ตามลำดับข้างบน หัวไฟล์อธิบายว่าทำอะไร ทำไมเป็น perl และว่าไม่เคยพิมพ์หน้าจอที่ไม่ครบ แล้วตั้ง `plugin.json` version `0.3.0`
- [ ] **Step 4:** รัน test Expected: `all passed` (ประมาณ 6 วินาทีเพราะกรณีหมดเวลา)
- [ ] **Step 5: Commit** `kit-update 0.3.0: hc-screen.pl reads a herdr-core screen with its colours`

---

### Task 2: `pane-lib.sh` + reload บน hc

**Files:**
- Modify: `plugins/kit-update/scripts/pane-lib.sh`, `plugins/kit-update/scripts/reload-all.sh`, `plugins/kit-update/scripts/reload-all.test.sh`

**Interfaces:**
- Consumes: `hc-screen.pl` (Task 1)
- Produces (ใน `pane-lib.sh` ทั้ง reload และ worker ใช้):
  - `esc(s)` ตัดเพิ่ม: ESC + intermediate `0x20–0x2F` ศูนย์ตัวขึ้นไป + final `0x30–0x7E` ยกเว้น `[` และ `]` (CSI กับ OSC ยังเป็นของ alternative เดิม)
  - `hc_call ARGS...` → `env -u HC_TERMINAL_ID "${KIT_UPDATE_HC_BIN:-hc}" ARGS...` (คืน status ของ hc)
  - `hc_screen T` → `"$KIT_UPDATE_SCREEN_BIN" T` ถ้าตั้งไว้ ไม่งั้น `perl <โฟลเดอร์ของ pane-lib.sh>/hc-screen.pl T` (หาโฟลเดอร์จาก `BASH_SOURCE` ตอน source)
  - `hc_state T STATUS` → echo `busy` | `question` | `draft` | `idle` | `unreadable` โดย STATUS คือคำสถานะของ terminal (`""` เมื่อไม่มี): `working` → busy, `blocked` → question, คำอื่นหรือว่าง → `hc_screen T | screen_tail` แล้ว `screen_state` ถ้า `hc_screen` ล้ม → unreadable
- `reload-all.sh` ส่วน hc ตาม spec §2 ข้อ 1–6: `hc_call ls --json` ได้ = มี server เลือก `agent == "claude-code"`, `state == "live"`, `address` ไม่มี `/` ชื่อที่แสดง `"<name // where // ชื่อโฟลเดอร์ของ cwd> (hc <address>)"` ตัวเองคือ `address == $HC_TERMINAL_ID` เหตุผลที่ข้ามใหม่: `screen unreadable`, `hc send failed` ส่งด้วย `hc_call send <t> /reload-plugins` ข้อความไม่มี server เปลี่ยนเป็น `No tmux or herdr-core server — ...`

- [ ] **Step 1: เขียน test ที่ล้ม** ใน `reload-all.test.sh` แทน fake herdr ด้วย fake `hc` (`ls`: `cat $FAKE/terms` ไม่มีไฟล์ = exit 1, `send T TEXT`: บันทึก `T TEXT` ลง `$FAKE/sent-hc` ยกเว้น T ที่มี `$FAKE/sendfail-T` ให้ exit 1, ทุกครั้งบันทึก `${HC_TERMINAL_ID-unset}` ลง `$FAKE/hc-env`) และ fake screen (`KIT_UPDATE_SCREEN_BIN`: `cat $FAKE/hscreen-T` ถ้าไม่มีไฟล์ exit 1) กรณี:
  - pane-lib: เปลี่ยนชื่อ `herdr suggestion` เป็น `hc suggestion` (byte เดิม) และเพิ่ม `esc drops two-character escapes`: `screen_awk '{ print esc($0) }'` ของ `\e[?1l\e>\e(B\e[9G\eH\e[17G\eHtext\e7\e8` ได้ `text` ทั้งใน locale นี้และ `LC_ALL=C`
  - `hc first paint with a dim suggestion counts as idle`: `hscreen` = หน้าจอตัวอย่างของ Task 1 (ตัด `\r` แล้ว, แถวแรกมีชุด reset) ได้ `/reload-plugins`
  - terminals: t1 `status` idle มี `name` "alpha" → ส่ง, แสดง `alpha (hc t1)` / t2 `done` ไม่มี name, `where` "beta / 1", จอ `❯ Try "…"` → ส่ง, แสดง `beta / 1 (hc t2)` / t3 `working` → `busy` / t4 `blocked` → `waiting on a question` / t5 จอพิมพ์ค้าง → `prompt not empty or not found` / t6 = `HC_TERMINAL_ID` → `this session` / t7 agent `zsh` → ไม่อยู่ในรายงาน / t8 `error` จอว่าง → ส่ง / t9 จอ first paint ข้างบน → ส่ง / t10 ไม่มี field `status` จอ `✻ Percolating… (esc to interrupt)` → `busy` / t11 ข้อความสี 2 ไม่จาง → draft / t12 ไม่มีไฟล์ hscreen → `screen unreadable` / t13 `state` finished และ `m1/t3` → ไม่อยู่ในรายงาน / t14 ไม่มี name, ไม่มี where, cwd `/x/gamma` → แสดง `gamma (hc t14)` และส่ง / t15 `sendfail` → `hc send failed`
  - `hc never sees HC_TERMINAL_ID` (รันด้วย `HC_TERMINAL_ID=t6` แล้ว `$FAKE/hc-env` มีแต่ `unset`) และ `hc summary counts`: `reloaded: 5 · skipped: 8` (ส่ง t1 t2 t8 t9 t14, ข้าม t3 t4 t5 t6 t10 t11 t12 t15)
  - `no server: says so` ข้อความ `No tmux or herdr-core server`
  - กรณี tmux ทั้งหมดคงเดิม
- [ ] **Step 2:** รัน `bash plugins/kit-update/scripts/reload-all.test.sh` Expected: FAIL ที่กรณี hc
- [ ] **Step 3:** แก้ `pane-lib.sh` (หัวไฟล์: เพิ่ม `hc-screen.pl` เป็นแหล่งหน้าจอแทน `herdr agent read`) และ `reload-all.sh` (หัวไฟล์ส่วน herdr เขียนใหม่เป็น herdr-core, ลบ `HERDR_BIN`, `HERDR_PANE_ID`)
- [ ] **Step 4:** รัน test Expected: `all passed` แล้วรัน `restart-all.test.sh` Expected: `all passed` (worker ยังใช้ herdr อยู่ แต่ `esc()` ใหม่ต้องไม่ทำให้อะไรพัง)
- [ ] **Step 5: Commit** `kit-update 0.3.0: reload through herdr-core`

---

### Task 3: `restart-all.sh` snapshot และเปิด worker ผ่าน hc

**Files:**
- Modify: `plugins/kit-update/scripts/restart-all.sh`, `plugins/kit-update/scripts/restart-all.test.sh` (ส่วน `# --- restart-all.sh`)

**Interfaces:**
- Consumes: `hc_call` (Task 2), `is_claude`, `tmux_above`, `shell_ok`, `add`, `pid_for_sid` (เดิม)
- Produces:
  - แถว state ของ hc: `pane<TAB>hc<TAB><address><TAB><label><TAB>PID…` LABEL = `where` ถ้าว่างใช้ชื่อโฟลเดอร์ของ cwd, SHELL_PID = `pid` ของ terminal, AGENT_NAME (คอลัมน์ 14) ว่างเสมอ (คงคอลัมน์ไว้ให้ worker อ่านตำแหน่งเดิม)
  - header `mux<TAB>hc` เมื่อ worker อยู่ใน herdr-core, `entry` แสดง `"<name> (hc <address>)"`
  - การเลือกที่เปิด worker: `HC_TERMINAL_ID` มีค่า → hc, `TMUX` มีค่า → tmux, มี hc server → hc, ไม่งั้น tmux
  - เปิด worker: ชื่อเริ่ม `kit-update-restart-<HHMMSS>` ถ้า `hc_call get <ชื่อ>` สำเร็จให้ลองชื่อ `-2`…`-9` แล้ว `run_detached hc_call run --bg --no-parent --name <ชื่อ> --cwd "$KU_DIR" -- env PATH=<PATH> [LANG=…] [LC_*=…] bash <restart-worker.sh> <state>` (ส่งเฉพาะ `LANG` และ `LC_*` ที่มีค่า) ล้มเหลว → `fail "hc run failed"` เพดาน 1024 byte ใช้กับคำสั่ง tmux เท่านั้น
  - output: `Worker: <ชื่อ> (watch: hc attach <ชื่อ> · stop: Ctrl-C there, or hc kill <ชื่อ>)` ฝั่ง tmux คง `Worker: <session>` เดิม ข้อความไม่มี server เป็น `No tmux or herdr-core server — ...`
- เลือก terminal จาก `hc_call ls --json` แบบเดียวกับ reload (`agent == "claude-code"`, `state == "live"`, address ไม่มี `/`) แล้ว snapshot ต่อ terminal ตาม spec §3 ข้อ 1–5: `hc_call get <t> --json` ล้ม → ข้าม `herdr-core does not answer`, `foreground` null หรือ `foreground.pid` ไม่ผ่าน `is_claude` → ข้ามพร้อมเหตุผล (ไม่เงียบ), `foreground.pid == pid` → `no shell to relaunch in`, `tmux_above` → แบบเดิม (SEEN), ppid ของ Claude ≠ `pid` หรือ `shell_ok` ไม่ผ่าน → ข้ามแบบเดิม ใช้ `\x1f` แยก field ตอนอ่านผล jq แบบเดิม (`read` รวม tab ว่าง)

- [ ] **Step 1: เขียน test ที่ล้ม** เพิ่ม fake `hc` ใน `$FAKE/bin/hc` (คง fake herdr ไว้ก่อน worker ยังใช้จนจบ Task 4): บันทึกทุกครั้งลง `$FAKE/hc-calls` และ `${HC_TERMINAL_ID-unset}` ลง `$FAKE/hc-env`, source `$FAKE/hook-hc-<cmd>` ถ้ามี, `ls` = `cat $FAKE/terms` (ไม่มี = exit 1), `get T --json` = `cat $FAKE/hget-T` (ไม่มี = พิมพ์ error not_found แล้ว exit 3), `run ...` = บันทึก `<name> <ส่วนหลัง -->` ลง `$FAKE/ran` (`fail-launch` = exit 1) helper `term ADDR WHERE SHELL_PID FG_PID|null [AGENT] [STATE]` เขียนทั้งแถวใน `terms` และ `hget-ADDR` แล้วแปลงโลก snapshot เดิม (w1:p1…p7) เป็น t1…t7 ตามเดิมทุกตัว แล้วเพิ่ม/แก้กรณี:
  - `hc: pid found through foreground and session file` / `hc: parent shell zsh -ic is skipped` / `hc: login shell -zsh is kept`
  - `tmux in hc: kept once, on the tmux side` / `hc terminal with tmux ancestor not in the tmux list: still dropped` / กรณี two live processes, no live process, missing status ในรูป hc
  - ใหม่: `Claude is the terminal's program: no shell to relaunch in` (t8, `foreground.pid == pid`) / `no foreground: skipped` (t9) / `foreground without a session file here: skipped, says so` (t7) / `Claude's parent is not the terminal's shell: skipped` (t12) / `hc get fails: skipped, herdr-core does not answer` / `zsh, finished and remote terminals are not listed`
  - `state rows carry every field` แถวของ t1 = `pane hc t1 'alpha work' 101 '<lstart>' ttys001 100 S1 alpha 2.1.309 /x/alpha 1 ''` + cmdline
  - `launch in hc carries PATH and LANG` (แทน `launch in herdr when HERDR_ENV is set`): รันด้วย `HC_TERMINAL_ID=t1 LANG=th_TH.UTF-8 LC_CTYPE=UTF-8` แล้ว `$FAKE/ran` = `kit-update-restart-<t> env PATH=$PATH LANG=th_TH.UTF-8 LC_CTYPE=UTF-8 bash $here/restart-worker.sh $(state)` (ลำดับ LC_* ตามที่ builder เลือกได้ ตรวจว่ามีครบ), `hc-calls` มี `run --bg --no-parent --name kit-update-restart-<t> --cwd $KU_DIR --`, state header `mux hc`, output มีบรรทัด `Worker: kit-update-restart-<t> (watch: hc attach …` และ `hc-env` มีแต่ `unset` และ log ไม่มี `{`
  - `second run while the previous worker terminal is there (hc)`: มี `hget-kit-update-restart-<t>` → ได้ `-2`
  - `neither HC_TERMINAL_ID nor TMUX: uses the multiplexer that has a server` (tmux อย่างเดียว → tmux เดิม, hc อย่างเดียว → hc)
  - `no server: says so` ข้อความใหม่, `launch fails: lock removed` ทั้ง hc และ tmux
  - กรณี lock ทั้งหมดและกรณี tmux คงเดิม
- [ ] **Step 2:** รัน `bash plugins/kit-update/scripts/restart-all.test.sh` Expected: FAIL ที่กรณี hc ของ snapshot
- [ ] **Step 3:** แก้ `restart-all.sh` ส่วน herdr ทั้งหมดเป็น hc (หัวไฟล์ข้อ 2–3 และย่อหน้า "Skipped at the snapshot" เขียนใหม่ตาม spec §3)
- [ ] **Step 4:** รัน test Expected: `all passed` และ `reload-all.test.sh` Expected: `all passed`
- [ ] **Step 5: Commit** `kit-update 0.3.0: restart snapshot and worker launch through herdr-core`

---

### Task 4: worker บน hc + ลบ herdr TUI

**Files:**
- Modify: `plugins/kit-update/scripts/restart-worker.sh`, `plugins/kit-update/scripts/restart-lib.sh`, `plugins/kit-update/scripts/restart-all.test.sh` (ส่วน `# --- restart-worker.sh` ทั้งสอง และ fake/หัวไฟล์)

**Interfaces:**
- Consumes: `hc_call`, `hc_state` (Task 2), state แถว hc (Task 3)
- Produces: ไม่มีอะไรใหม่ให้ task อื่น worker เปลี่ยนตามตาราง spec §4 ทุกแถว:
  - สถานะของ terminal จาก `hc_call get <t> --json`: exit 0 + `.state == "live"` = live (คำสถานะ = `.status.state // ""`), exit 3 หรือ `.state == "finished"` = gone, อย่างอื่น (exit อื่น, JSON ผิดรูป) = ไม่รู้ ตัวช่วยนี้อยู่ใน `restart-lib.sh` (ชื่อและการรวม get ต่อรอบให้ builder เลือก)
  - `identity_ok` gone → 1, ไม่รู้ → 2 พร้อม why `herdr-core does not answer`
  - `pane_sendable` ใช้ `hc_state` กับคำสถานะข้างบน: busy → `busy`, question → `waiting on a question`, draft → `prompt not empty or not found`, unreadable → `screen unreadable`
  - `not_scrolled` ฝั่ง hc ผ่านเสมอ, `confirm` ไม่มี rename
  - คำขอ handoff, `/exit`, บรรทัดเปิดใหม่: `run_detached hc_call send <t> <text>`
  - `relaunch`: gone (เฉพาะ not_found หรือ finished) → `relaunch it yourself: …` แล้ว `finish gone "gone: its terminal closed after /exit"`
  - owner file: `me=${HC_TERMINAL_ID:-?}` เมื่อ `mux` เป็น `hc`
  - SNAME = `NAME` ถ้าว่างใช้ LABEL, SHOWN = `"<SNAME> (hc <address>)"`
  - `ku_paths`: `HC_BIN` แทน `HERDR_BIN` (ถ้า `hc_call` ไม่ได้ใช้ ก็ลบทิ้งได้)

- [ ] **Step 1: เขียน test ที่ล้ม** ใน `restart-all.test.sh`:
  - fake `hc send T TEXT`: บันทึก `send T TEXT` ใน `hc-calls`; TEXT ขึ้นต้น `[kit-update restart ` → `prompted-T` + `asked-T` + `react` แบบ `agent prompt` เดิม; `/exit` → `fake_exit` (life `exit-fails`: exit 1 หลัง Claude ออก); อย่างอื่น → `fake_run` (life `slow-run`: `touch running; sleep 1` ก่อน) fake screen `KIT_UPDATE_SCREEN_BIN` = `cat $FAKE/screen-T` (ไม่มีไฟล์ = `❯ `; มี `$FAKE/noscreen-T` = exit 1)
  - `wworld` ใช้ `hc` เป็นค่าเริ่ม, `wpane` ฝั่ง hc เขียน `hget-T` (`state` live, `status.state` `done`), terminal ชื่อ `t1`… แทน `w1:p1`… และแปลงทุก assertion: `(herdr w1:pN)` → `(hc tN)`, ชื่อไฟล์ `alpha-w1_p1` → `alpha-t1`, `herdr-calls` → `hc-calls`, `agent prompt T X` / `pane run T X` → `send T X`
  - ลบ: `herdr pane scrolled up`, การ rename ใน `herdr full restart`, fake herdr ทั้งไฟล์, `KIT_UPDATE_HERDR_BIN`, `HERDR_*` ใน `unset`, คำอธิบาย `hpanes`/`pane-list`/`scroll-*` ในหัวไฟล์
  - แปลงเป็น hc: `hc full restart: handoff, /exit, relaunch, Summary restarted` (ไม่มี rename) / `unnamed session: label fallback` (NAME ว่าง → ใช้ LABEL `alpha work`) / `hc terminal gone (not_found): gone` และเพิ่ม `hc terminal finished: gone` / `hc get unreadable: waits, not gone` (hget เป็น JSON ขาด จนถึง T0+20) / `terminal closed after /exit: gone, no relaunch keys` (ลบ hget ที่ T0+30) / `terminal finished after /exit: gone` / `hc get broken JSON after /exit: still relaunched` / `hc get fails (exit 1) after /exit: still relaunched` / `blocked until the cap` ใช้ `status.state` blocked / `owner: token, pid, pane` รันด้วย `HC_TERMINAL_ID=t9` แล้ว owner = `TOK <pid> t9`
  - ใหม่: `status error with an idle screen: asked` / `screen unreadable: no keys until readable` (`held` กับ `noscreen-t1` ลบที่ T0+60) / `worker: hc never sees HC_TERMINAL_ID` (full restart รันด้วย `HC_TERMINAL_ID=t9` แล้ว `hc-env` มีแต่ `unset`)
  - กรณีสัญญาณ (INT/TERM/HUP), slot, issuer, cap, NOT-READY, hostile name, 1024 byte ใช้ fake hc แทนเหมือนเดิมทุกตัว กรณี tmux ไม่แตะ
- [ ] **Step 2:** รัน test Expected: FAIL ที่กรณี worker ฝั่ง hc
- [ ] **Step 3:** แก้ `restart-worker.sh` (หัวไฟล์และ comment ทุกจุดที่พูดถึง herdr) และ `restart-lib.sh`
- [ ] **Step 4:** รัน test Expected: `all passed` (~45 วินาที) แล้วรัน `reload-all.test.sh` และ `hc-screen.test.sh` Expected: `all passed` แล้ว `grep -rnE 'HERDR|herdr (agent|pane|workspace)|agent rename' plugins/kit-update/scripts` Expected: ไม่เจอ
- [ ] **Step 5: Commit** `kit-update 0.3.0: restart worker through herdr-core, herdr TUI removed`

---

### Task 5: คำสั่ง เอกสาร และ manifest

**Files:**
- Modify: `plugins/kit-update/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json:26`, `plugins/kit-update/commands/reload.md`, `restart.md`, `all.md:18`, `all-projects.md:18`, `README.md:66-79,117-119`, `guides/tmux-remote-control.md`, `CLAUDE.md:22-23`

- [ ] **Step 1:** แก้ตาม spec §6 ครบทุกข้อ:
  - `plugin.json` และ marketplace: "herdr" → "herdr-core"
  - `reload.md`, `restart.md`, `all.md`, `all-projects.md`: "tmux or herdr" → "tmux or herdr-core", "pane" → "pane or terminal" ตรงที่พูดถึงที่ของ session หรือ worker
  - README ส่วน kit-update: herdr → herdr-core (แอป Herdr), ลบบรรทัด `herdr integration install claude`, บอกว่าต้องมี `perl`, Claude ต้องรันจาก bash/zsh ใน terminal (แบบ tab ของแอป Herdr), worker เปิดเป็น terminal `kit-update-restart-<เวลา>` ดูด้วย `hc attach <ชื่อ>` หยุดด้วย Ctrl-C ใน attach หรือ `hc kill <ชื่อ>`, terminal บนเครื่องอื่นไม่นับ และถ้าเครื่องมี `hc` คำสั่งทั้งสองจะเปิด herdr-core ให้ถ้ายังไม่เปิด (ตามที่กิตยืนยันใน Global Constraints) วงเล็บเรื่อง "tmux อ่านจากหน้าจอ herdr ใช้สถานะ" เขียนใหม่: ทั้งสองดูหน้าจอ herdr-core ดูสถานะก่อน
  - README หัวข้อ "ใช้ Claude Code ผ่าน tmux หรือ herdr" และ guide: ลบข้อ 7 ทั้งข้อ (`herdr integration`, `_herdr_claude`, ตารางคีย์), บรรทัด "ข้อ 2–4 เป็นของ tmux ถ้าใช้ herdr ให้ทำข้อ 7 แทน", `(herdr: \`herdr\`)` ในข้อ 5 และ "หรือ herdr" ในหัวเรื่อง เหลือบรรทัดเดียวท้ายคู่มือว่า `/kit-update:reload` และ `/kit-update:restart` ใช้กับแอป Herdr (herdr-core) ได้ด้วย
  - `CLAUDE.md`: บรรทัด test ของ reload/restart เป็น "fake tmux and hc (`KIT_UPDATE_TMUX_BIN`, `KIT_UPDATE_HC_BIN`, `KIT_UPDATE_SCREEN_BIN`)" และเพิ่ม `bash plugins/kit-update/scripts/hc-screen.test.sh   # self-check for hc-screen.pl against a fake framed hc connect (~6 s)`
- [ ] **Step 2:** รัน `claude plugin validate ./plugins/kit-update` Expected: ผ่าน แล้วรัน test ทั้งสามไฟล์ Expected: `all passed`
- [ ] **Step 3:** `grep -rn -i 'herdr' plugins/kit-update README.md guides CLAUDE.md .claude-plugin` แล้วอ่านทุกบรรทัดที่เจอ Expected: เหลือแค่ herdr-core / แอป Herdr และ `grep -rn '/Users/' plugins/kit-update README.md guides CLAUDE.md` ไม่เจอ
- [ ] **Step 4: Commit** `kit-update 0.3.0: docs for herdr-core`

---

### Task 6: ลองกับ hc จริง (ทำใน main session ไม่ใช่ subagent)

ใช้ได้แค่ terminal ที่เปิดเอง (ชื่อขึ้นต้น `ku-e2e-`) กันไม่ให้แตะ session จริงของกิตด้วย wrapper `$SCRATCH/hc` (`KIT_UPDATE_HC_BIN`) ที่ส่งทุกอย่างให้ `hc` จริง ยกเว้น `ls` ที่กรอง `.terminals` ให้เหลือเฉพาะ address ที่อยู่ใน `$SCRATCH/mine` (address ของ terminal ที่เปิดเอง) ตรวจ wrapper ด้วย `KIT_UPDATE_HC_BIN=$SCRATCH/hc hc ls` ก่อนทุกขั้น Expected: เห็นแค่ของตัวเอง ถ้าข้อไหนต้องให้กิตดูหรือกดอะไร บอกกิตก่อน

- [ ] **Step 1: หน้าจอ** เปิด `hc run --bg --no-parent --name ku-e2e-1 --cwd $SCRATCH/a` (login shell) แล้ว `hc send ku-e2e-1 'claude --name e2e1'` ผ่าน dialog trust folder ด้วย `hc keys` คุยหนึ่งรอบจนมีคำแนะนำขึ้น แล้วรัน `perl hc-screen.pl <address>` Expected: แถว `❯` มี `\e[2m` และผ่าน `screen_state` ได้ `idle` (spec "ต้องเช็ค" ข้อ 1) ถ้าไม่มีคำแนะนำขึ้นเลย จดไว้
- [ ] **Step 2: reload** เปิด ku-e2e-2 แบบเดียวกัน พิมพ์ค้างด้วย `hc keys` (ไม่กด enter) รัน `KIT_UPDATE_HC_BIN=$SCRATCH/hc bash reload-all.sh` Expected: ku-e2e-1 ได้ `/reload-plugins`, ku-e2e-2 ถูกข้าม `prompt not empty`, ไม่มี `<hc from` บนจอไหน
- [ ] **Step 3: restart** ลบข้อความค้างของ ku-e2e-2 แล้วรัน `restart-all.sh` ด้วย wrapper จาก shell ใน terminal ทิ้ง ku-e2e-3 (`hc send` บรรทัดคำสั่ง) Expected: worker ขึ้นเป็น `kit-update-restart-<เวลา>`, ทั้งสองตัวได้ handoff และเปิดใหม่ด้วยชื่อเดิม, Summary `restarted: 2` ใน log ระหว่างนั้นถามกิตว่า worker ขึ้นในแอป Herdr ไหม แล้ว `hc kill ku-e2e-3` ก่อน worker จบ Expected: worker ทำต่อจนจบ (spec "ต้องเช็ค" ข้อ 2–3)
- [ ] **Step 4: หยุด worker** รัน restart อีกรอบโดยให้ ku-e2e-1 ทำงานยาวอยู่ แล้ว `hc kill <worker>` Expected: log มี Summary ที่ ku-e2e-1 เป็น `stopped`, lock หาย ถ้ากิตสะดวก ให้ลอง Ctrl-C ผ่าน `hc attach` อีกรอบ
- [ ] **Step 5: `hc send` ระหว่างมีคนพิมพ์** ขอกิต attach ku-e2e-1 แล้วพิมพ์ช้า ๆ ขณะรัน reload Expected: reload ข้ามเพราะ draft หรือ `hc send` จบภายในไม่กี่วินาที จดเวลาไว้ (ข้ามได้ถ้ากิตไม่สะดวก)
- [ ] **Step 6:** `hc kill` + `hc rm` เฉพาะ ku-e2e-* และ kit-update-restart-* ที่เปิดเอง ลบ `$SCRATCH` และ handoff ทดลอง แล้วเพิ่มผลเป็นข้อเท็จจริงข้อ 14 ขึ้นไปใน spec (ไม่ใส่ชื่อ terminal จริง) commit `kit-update 0.3.0: herdr-core end-to-end results`

---

### Task 7: PR, เว็บ และ pointer (ขอกิตก่อน push ทุกครั้ง)

- [ ] **Step 1:** อ่าน `git diff main...kit-update-herdr-core` ทั้งหมด (repo public) หาชื่อ terminal, path ของเครื่อง และของจาก repo private แล้วขอกิตก่อน push และเปิด PR
- [ ] **Step 2:** เว็บ: อ่าน `phimee-and-kit-website/CLAUDE.md` หัวข้อ "Keeping the Tools section in sync with the mods" แล้วแก้ `src/components/Tools.astro:73` ("tmux หรือ herdr" → herdr-core) เป็น PR แยก (ขอกิตก่อน push)
- [ ] **Step 3:** หลังทั้งสอง PR merge: `git -C <submodule> pull` แล้ว `git add` + commit pointer ใน root

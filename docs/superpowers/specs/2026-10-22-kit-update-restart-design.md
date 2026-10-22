# kit-update restart: design

> 22 ต.ค. 2569 · ที่มา: คุยกับกิตใน session นี้ + builder check + scrutinize รอบ 1–8
> ข้อที่เขียนว่า **(Claude เลือก)** เป็นการตัดสินใจของ Claude ไม่ใช่ของกิต เปลี่ยนได้

## เจตนา

Claude Code อัปเดตบ่อย แต่ session ที่เปิดค้างไว้ (ของกิตมีประมาณ 10 ตัวใน herdr) จะยังรันเวอร์ชันเก่าจนกว่าจะปิดแล้วเปิดใหม่ ทุกวันนี้กิตต้องเข้าไปปิดเปิดทีละ session

กิตอยากได้คำสั่งเดียวที่ restart ทุก session และให้แต่ละ session **เริ่ม context ใหม่** ไปพร้อมกัน ไม่ใช่กลับไปที่บทสนทนาเดิม งานที่ค้างอยู่จะต่อได้ด้วย handoff ที่ session เก่าเขียนไว้ก่อนปิด

## เป้าหมาย

- `/kit-update:restart` สั่งครั้งเดียวจาก session ไหนก็ได้
- ครอบคลุมทุก Claude Code session ที่รันอยู่ใน herdr และ tmux **รวมถึง session ที่เป็นคนสั่ง**
- แต่ละ session จะ restart **ตอนว่าง**: ตัวที่ว่างอยู่ทำทันที ตัวที่กำลังทำงานรอจนงานจบ ตัวที่รอคำตอบรอจนกิตตอบและงานรอบนั้นจบ
- ก่อนปิด Claude ใน session นั้นเขียน handoff ด้วยหัวข้อเดียวกับ kit-checkpoint: เป้าหมาย / ทำเสร็จแล้ว / ค้างอยู่ตรงไหน / ตัดสินใจอะไรไปแล้วและเพราะอะไร / ไฟล์ที่เกี่ยวข้อง / ขั้นต่อไป
- เปิด Claude ตัวใหม่ใน pane เดิม ชื่อเดิม ได้เวอร์ชันล่าสุด handoff เป็นข้อความแรก แล้ว Claude สรุปสั้น ๆ ว่าค้างอะไรอยู่และรอกิต ไม่ลงมือทำต่อเอง

## ไม่ทำ (v1)

- เลือก restart เฉพาะ session ที่ยังเป็นเวอร์ชันเก่า: restart ทุกตัว เพราะกิตต้องการ context ใหม่ด้วย
- กลับไปที่บทสนทนาเดิม (`claude --resume <id>`)
- ใช้ `/restart` ที่มีอยู่ใน Claude Code (ดู "ทางที่พิจารณาแล้วไม่เลือก")
- คำสั่งดูสถานะหรือยกเลิกแยกต่างหาก **(Claude เลือก)**: worker รันอยู่ใน pane ของตัวเอง ดูความคืบหน้าได้ที่นั่น และหยุดได้ด้วย Ctrl-C (ข้อ 2)
- session ที่ไม่ได้อยู่ใน herdr หรือ tmux: บอกให้ผู้ใช้ปิดเปิดเอง เหมือนที่ reload ทำ
- teammate ของ agent team ใน Claude Code: ไม่ใช่ session เดี่ยว ข้ามไป
- shell ที่ไม่ใช่ bash หรือ zsh ใน pane (เช่น fish): คำสั่งเปิดใหม่ใช้ quote แบบ bash/zsh README บอกไว้
- ลบ handoff เก่า: เก็บไว้เป็นบันทึก ไฟล์เล็ก
- รับ argument ใด ๆ (เหมือน reload)

## สิ่งที่ต้องไม่เกิดเด็ดขาด

- **ห้ามปิด Claude ใน session ไหน ถ้ายังไม่ได้ handoff ที่ผ่านเกณฑ์ในข้อ 3** และ worker เขียนลงไฟล์สำเร็จแล้ว ไม่งั้นงานที่ค้างใน session นั้นจะหายไป
- **ห้ามปิด Claude ขณะที่ยังมีงานเบื้องหลังที่ตรวจเจอได้** คือ process ลูกของ Claude ที่เป็น shell ของ background Bash หรือ Monitor (`/exit` จะฆ่ามัน) ส่วน subagent, teammate และ `/loop` อยู่ใน process ของ Claude เอง ตรวจจากข้างนอกไม่ได้ ใช้คำตอบ `NOT-READY` ของ Claude แทน ซึ่งเป็น**แค่ best effort** README ต้องบอกตรง ๆ
- **ห้าม restart session ที่ข้อความสุดท้ายของ Claude ถามกิตไว้และยังไม่ได้คำตอบ** กิตเลือกให้รอจนตอบ คำถามแบบนี้ไม่ทำให้ herdr ขึ้น `blocked` (ขึ้นแค่ตอนมี dialog) ตรวจได้ทางเดียวคือ Claude ตอบ `NOT-READY` จึงเป็น**แค่ best effort** เหมือนงานเบื้องหลังข้างบน README ต้องบอกตรง ๆ
- ห้ามทำให้ขั้น handoff ต้องรอกิตกด permission: กิตไม่อยู่หน้าจอ 10 session ก็จะค้างหมด
- ห้ามพิมพ์อะไรลง pane ที่ไม่ว่าง: กำลังทำงาน, มีคำถามหรือ dialog เปิดอยู่ (Enter จะไปตอบมันแทน), หรือช่องพิมพ์มีข้อความที่กิตพิมพ์ค้างไว้ เกณฑ์เดียวกับ `reload-all.sh`
- **ห้ามพิมพ์ลงหรือเปิดใหม่ใน pane ที่ไม่ใช่ Claude ตัวเดิมที่เห็นตอน snapshot แล้ว** เช่นกิตปิด Claude เองระหว่างรอ (ข้อความจะไปลง shell) หรือเปิด Claude ตัวใหม่เอง
- ห้ามแตะ pane ที่ไม่ใช่ Claude Code และห้ามส่งแป้นผ่าน pane ของ herdr ที่ข้างในเป็น tmux (แป้นจะไปลง pane ไหนของ tmux ก็ไม่รู้)
- ห้ามเปิด Claude ซ้อนใน pane ที่ Claude ตัวเก่ายังไม่ออก หรือพิมพ์คำสั่งเปิดใหม่ลงในอะไรที่ไม่ใช่ shell ตัวเดิมของ pane
- ห้ามมี worker สองตัวทำงานพร้อมกัน
- ห้ามเขียนอะไรลงใน repo ของผู้ใช้: handoff, log, lock อยู่นอก repo ทั้งหมด
- ถ้าไม่แน่ใจว่าสถานะของ pane เป็นยังไง ให้ข้ามและบันทึกลง log ห้ามเดา

## ข้อเท็จจริงที่ยืนยันแล้ว (22 ต.ค. 2569)

- Claude Code แบบ native: `~/.local/bin/claude` ชี้ไปที่ `~/.local/share/claude/versions/<version>` ตัวอัปเดตเปลี่ยนลิงก์นี้ การเปิด `claude` ใหม่จึงได้เวอร์ชันล่าสุดเสมอ ยืนยันแล้วว่า session ทั้ง 6 ตัวที่เปิดด้วย `claude --continue` หลังอัปเดตรันไฟล์ `2.1.308` ทุกตัว (ดูจาก `lsof -d txt`)
- Claude Code 2.1.308 มีคำสั่ง `/restart` (alias `/update`) คำอธิบาย "Restart on <version> and keep this session" แต่จะเปิดหรือซ่อนขึ้นกับ feature flag เครื่องของกิตแสดง "Restart to update" ซึ่งเป็นข้อความตอนที่ flag ปิด
- **session file (สถานะภายในของ Claude Code ไม่มีในเอกสาร)**: `~/.claude/sessions/<pid>.json` หนึ่งไฟล์ต่อหนึ่ง process ที่รันอยู่ มี `pid`, `sessionId`, `name` (ชื่อ session ของ Claude เอง ซึ่งไม่จำเป็นต้องตรงกับชื่อ workspace), `version`, `status` (`idle` / `busy` / `shell` ที่เจอค้างอยู่หลายชั่วโมง ยังไม่รู้ว่าหมายถึงอะไร), `statusUpdatedAt` (ms), `kind` (`interactive`), `procStart` (เวลาที่ process เริ่ม) และ `cwd` (โฟลเดอร์ที่เปิด) `sessionId` ตรงกับ `agent_session.value` ของ herdr (ยืนยันกับ session นี้)
- herdr 0.9.5 มีคำสั่งที่ใช้ได้ตรง ๆ:
  - `herdr agent list`: แต่ละ agent มี `pane_id`, `agent` (`claude`), `agent_status` (`idle` / `working` / `blocked` / `done` / `unknown`), `cwd`, `workspace_id`, `agent_session.value` (session id) แต่ไม่มี pid
  - `herdr agent wait <target> --until <status> --timeout <ms>`
  - `herdr agent prompt <target> <text> [--wait --until <status> --timeout <ms>]` ส่งข้อความพร้อม Enter และปฏิเสธถ้า agent อยู่ใน `blocked`
  - `herdr agent start <name> --kind claude --pane <id> [--timeout <ms>] -- <args>` เปิด agent ใน pane ที่**อยู่ที่ shell prompt** (herdr เช็กให้) สำเร็จเมื่อ herdr เห็น agent และมันพร้อมรับ input
  - `herdr workspace list` มี `label` ของ workspace, `herdr workspace create --label --no-focus`, `herdr pane run <pane> <command>` พิมพ์คำสั่งลง shell ของ pane
  - ชื่อ agent ใน `agent list` (ตั้งด้วย `herdr agent rename`) ต่างจาก label ของ workspace ได้ และ herdr ล้างชื่อ agent ทิ้งตอน Claude ออก ชื่อต้องตรงกับ `[a-z][a-z0-9_-]{0,31}` (คู่มือ herdr skill)
  - บน macOS `pane run` และ `agent start` ปฏิเสธคำสั่งที่ยาวเกิน canonical line limit ของ terminal (1024 byte) และ `pane run` แค่ queue ข้อความพร้อม Enter ไม่ได้เช็กว่า shell อยู่หน้าสุด (คู่มือ herdr skill)
  - `idle` / `done` ไม่ได้รับประกันว่า agent อยู่หน้าสุด: หลัง Ctrl+Z agent ยังขึ้น idle ได้ขณะที่ shell อยู่หน้าสุด และ `herdr pane move` เปลี่ยน pane id (คู่มือ herdr skill)
- macOS: `ps -o pgid=,tpgid= -p <pid>` บอกได้ว่า process อยู่หน้าสุดของ terminal หรือเปล่า (`pgid` เท่ากับ `tpgid`) ยืนยันกับ Claude ตัวนี้แล้ว
- `plugins/kit-update/scripts/reload-all.sh` มีโค้ดหา Claude pane และตรวจว่าว่างอยู่แล้วทั้งฝั่ง tmux (ชื่อ process เป็นเลขเวอร์ชันหรือ `claude` + อ่านจอ) และ herdr (`agent_status` + ช่องพิมพ์ว่าง) และ test ด้วย fake tmux/herdr ผ่าน `KIT_UPDATE_TMUX_BIN` / `KIT_UPDATE_HERDR_BIN` แต่ `prompt_empty` (`reload-all.sh:33`) ดูแค่ว่าบรรทัดสุดท้ายขึ้นต้นด้วย `❯` ซึ่ง shell prompt บางแบบ (starship, pure) ก็ขึ้นต้นแบบนั้น จึงใช้แยก Claude ออกจาก shell ไม่ได้
- transcript ของแต่ละ session อยู่ที่ `~/.claude/projects/<path ของโฟลเดอร์ที่เปิด claude โดยแทน / _ . ด้วย ->/<session id>.jsonl` หนึ่งบรรทัดต่อหนึ่ง entry
  - ข้อความที่พิมพ์เข้าไปเป็น `type: "user"` (content เป็น string) แต่ข้อความที่เข้ามาระหว่างที่ Claude ทำงานอยู่ (กิตพิมพ์ตอน busy หรือ task notification) ถูกรวมเข้า turn นั้นเป็น `type: "attachment"` ที่ `attachment.type` เป็น `"queued_command"` (มี `prompt`, ของที่กิตพิมพ์มี `commandMode: "prompt"` และ `humanTurn: true`, task notification มี `commandMode: "task-notification"` และ `isMeta: true`) ไม่ใช่ `type: "user"`
  - ตอน process เริ่ม (รวม `--continue`) หรือหลัง `/clear` Claude Code queue task notification ไว้ (เช่นข้อความว่า hook ของ mod ถูกข้าม) แล้วมันถูกรวมเข้าเป็น `queued_command` ต่อจาก prompt แรกของ session ใน turn เดียวกัน
  - คำตอบของ Claude เป็น `type: "assistant"` ที่ `message.content` มีส่วน `type: "text"` / `"tool_use"` / `"thinking"` และมี `message.stop_reason` (`end_turn`, `tool_use`, ...) หนึ่ง message ถูกแยกเป็นหลาย entry ที่มี `message.id` และ `stop_reason` เดียวกัน `stop_reason` เป็น null ได้เมื่อ turn ถูกขัด (กิตกด Esc) ซึ่งตามด้วย `type: "user"` ที่ content เป็น array มีข้อความ `[Request interrupted by user]`
  - API error ถูกบันทึกเป็น `type: "assistant"` ที่ `message.model` เป็น `"<synthetic>"`, มี `isApiErrorMessage: true` และ text ขึ้นต้นด้วย `API Error:` (เจอ 20 entry ใน 14 ไฟล์บนเครื่องของกิต)
  - ไฟล์อยู่ใต้โฟลเดอร์ที่เปิด claude ตอนแรก ถึง Claude จะ `cd` ไปที่อื่นภายหลัง
- kit-checkpoint (mod ใน marketplace เดียวกัน) เตือนให้เรียก tool `handoff` ตอน context ข้าม 400K, ทุก +25K หลังจากนั้น และตอนข้าม 500K (`kit-checkpoint/hooks/logic.ts:62-68`, `register.ts:317-323`) ถ้า Claude เรียก tool นั้น kit-checkpoint จะ `/clear` แล้วส่งข้อความเริ่มของมันเอง session id จึงเปลี่ยน และ tool นี้ปฏิเสธเมื่อ context <400K (`logic.ts:88`)
- tmux: `cc` ใน `guides/tmux-remote-control.md` เปิด Claude เป็น process หลักของ pane (`tmux new ... claude --name ...`) พอ Claude ออก pane และ session จะปิดไปด้วย ไม่มี shell ให้พิมพ์คำสั่งต่อ ส่วน `cc` ของ herdr เปิด Claude ผ่าน `pane run` ใน shell
- ข้อความท้าย handoff ของ kit-checkpoint ตอนรอผู้ใช้: `ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร แล้วรอ` (`MSG.stay('')` ใน `plugins/kit-checkpoint/hooks/logic.ts`)
- macOS ใช้ `/bin/bash` 3.2 ไม่มี `declare -A`, `wait -n`, `mapfile`

## Design

### 1. อยู่ใน kit-update อย่างเดียว (Claude เลือก)

งานเกือบทั้งหมดคือไล่ดู pane ใน herdr หรือ tmux แล้วพิมพ์ลงไป ซึ่ง kit-update ทำอยู่แล้วใน reload handoff สั่งผ่านข้อความที่พิมพ์ลงไป ไม่ใช้ tool ของ kit-checkpoint (ซึ่งปฏิเสธเมื่อ context <400K อยู่แล้ว) คนที่ใช้ restart จึงไม่ต้องติดตั้ง mod อื่น และไม่ต้องแก้ kit-checkpoint

รองรับทั้ง herdr และ tmux เหมือน reload เพราะ mod นี้เป็น public และเส้นทางหลักใน guide ยังเป็น tmux สคริปต์ทั้งหมดต้องรันได้บน `/bin/bash` 3.2

### 2. คำสั่ง `/kit-update:restart`

`commands/restart.md` รัน `scripts/restart-all.sh` ครั้งเดียวด้วย Bash tool ตัวสคริปต์:

1. **lock**: `mkdir ~/.claude/kit-update/restart.lock` (atomic, macOS ไม่มี `flock`) แล้วเขียน `starting <token สุ่ม>` ลงในนั้น ส่ง token ให้ worker worker ตรวจว่า token ใน lock ยังเป็นของตัวเอง แล้วเขียนทับด้วย token, pid, command line และ pane ของตัวเอง ถ้า token ไม่ตรง worker จบทันทีโดยไม่แตะ pane ไหน ไฟล์ใน lock เขียนลงไฟล์ชั่วคราวแล้ว `mv` ทับ ไม่ให้ใครอ่านเจอไฟล์ที่เขียนไม่ครบ ถ้า `mkdir` ไม่ผ่าน:
   - มี pid และ process นั้นยังเป็น worker ตัวนี้ (command line ตรงกัน): บอกว่ากำลังทำอยู่ที่ pane ไหน แล้วจบ
   - เป็น `starting` หรือโฟลเดอร์ว่างหรืออ่านไม่ได้ (ช่วงระหว่าง `mkdir` กับเขียนไฟล์) ที่ mtime ของโฟลเดอร์ยังไม่ถึง 60 วินาที: บอกว่ากำลังเริ่มอยู่ แล้วจบ
   - นอกนั้น (pid ตายแล้ว หรือค้างเกิน 60 วินาที): lock ค้าง ย้ายทิ้งด้วย `mv` ไปเป็นชื่อที่ไม่ซ้ำ แล้วลอง `mkdir` ใหม่ ถ้ายังไม่ผ่าน (อีกตัวได้ไปก่อน) ให้บอกว่ากำลังเริ่มอยู่ แล้วจบ
   - ถ้าขั้นไหนข้างล่างล้มเหลวก่อน worker จะเริ่ม ให้ลบ lock
   - **ลบ lock เฉพาะเมื่อ token ในนั้นเป็นของตัวเอง** ทั้งตัวเรียกและ worker (รวมทางออกและ trap) กัน worker ที่แพ้ไปลบ lock ของตัวที่ชนะ
2. **snapshot**: หา Claude pane ทั้งหมดในตอนนั้น pane ที่เปิดทีหลังไม่นับ **(Claude เลือก)** แต่ละ pane จดไว้:
   - **pid ของ Claude** — tmux: process ใน pane (`#{pane_pid}` หรือลูกของมัน) / herdr: `agent_session.value` → หา session file ที่ `sessionId` ตรงกัน → `pid` ถ้ามีหลายไฟล์ที่ `sessionId` ซ้ำกัน (ไฟล์ค้างของ process ที่ตายไป) ให้เลือกไฟล์ที่ process ยังอยู่และ `procStart` ตรงกับเวลาเริ่มของ process นั้น ถ้ายังไม่ชัดหรือหาไม่เจอให้ข้าม pane นั้น
   - `procStart`, `sessionId`, `name`, `version`, `cwd` จาก session file ของ pid นั้น (กัน pid ถูกใช้ซ้ำ และใช้ตอนเปิดใหม่)
   - tty ของ Claude (`ps -o tty= -p <pid>`) ใช้ผูก pid กับ pane ในการตรวจตัวตนทุกรอบ
   - tmux: Claude ต้องเป็น `#{pane_pid}` เอง หรือเป็นลูกโดยตรงของ `#{pane_pid}` (shell แบบ interactive หรือ `sh -c` ก็ได้ เพราะขั้น 4–5 จัดการกรณีที่ pane ตายตาม Claude ไว้แล้ว) ถ้าเป็นอย่างอื่น (เช่นเปิดผ่าน wrapper) ให้ข้าม pane นั้น
   - herdr: แม่ของ Claude (`ps -o args= -p <ppid>`) ต้องเป็น bash หรือ zsh ที่ไม่มี `-c` (รวม option ที่รวมกันอย่าง `-lc`, `-ic`: กลุ่ม option ไหนก่อน operand ตัวแรกที่มี `c` นับเป็น `-c`) เทียบ basename ของ argv[0] หลังตัด `-` นำหน้าออก (login shell ขึ้นเป็น `-zsh` และอาจเป็น path เต็มอย่าง `/opt/homebrew/bin/zsh`) (shell ที่ยังอยู่หลัง Claude ออก) ไม่งั้นข้าม เพราะ herdr ไม่มีทาง respawn pane
   - command line ตอนเปิด (เพื่อบันทึก)
   - **session ที่เป็นคนสั่ง**: หาจาก process ที่เป็นแม่ของ `restart-all.sh` ไล่ขึ้นไปจนเจอ pid ของ Claude ไม่ใช้ `$TMUX_PANE` / `$HERDR_PANE_ID` (tmux ใน herdr มีทั้งสองตัว)

   แล้วกรอง:
   - pane ซ้ำ (pid ของ Claude เดียวกัน): **เก็บฝั่ง tmux** และตัด agent ของ herdr ที่ Claude มี tmux เป็นบรรพบุรุษทิ้งเสมอ ถึงฝั่ง tmux จะไม่ได้อยู่ในรายการก็ตาม
   - process ที่ยังอยู่สองตัวใช้ `sessionId` เดียวกัน (เช่นสอง pane รัน `claude --continue` บน session เดียวกัน): ข้ามทั้งคู่ ทั้ง tmux และ herdr เพราะเขียน transcript ไฟล์เดียวกัน
   - teammate ของ agent team: ข้าม
   - session file ที่ `kind` ไม่ใช่ `interactive` (เช่น `claude -p`): ข้าม
   - session file ที่ไม่มี `status`, `statusUpdatedAt` หรือ `procStart` (เวอร์ชันเก่าอาจไม่มี ยืนยันแค่ 2.1.308): ข้ามพร้อมเหตุผล
   - herdr: ผูก pane กับ Claude ตอน snapshot ด้วย `agent_session.value` = `sessionId` แล้วใช้ pid จากนั้นตลอด ถ้า pane id หายไปจาก `agent list` (เช่นถูก `pane move`) ถือว่า "gone"
   - ถ้าไม่มี tmux หรือ herdr server ให้บอกว่าต้องปิดเปิดเองทีละ session แล้วปล่อย lock และจบ
   - พิมพ์บอกด้วยว่าเจอ session ที่เป็นคนสั่งใน snapshot หรือเปล่า
3. **เปิด worker ใน pane ของตัวเอง** **(Claude เลือก: ไม่ใช้ `nohup` เพราะ worker ที่เป็นลูกของ Bash tool อาจตายไปพร้อม Claude ที่สั่ง)** ใช้ multiplexer เดียวกับ session ที่สั่ง (herdr ถ้ามี `HERDR_ENV` ไม่งั้น tmux ถ้ามี `TMUX` ไม่งั้นตัวที่มี server):
   - herdr: `herdr workspace create --label "kit-update restart <HHMMSS>" --no-focus` แล้ว `pane run` ตัว worker ใน shell ของ pane นั้น
   - tmux: `tmux new-session -d -s kit-update-restart-<HHMMSS>` เสมอ ไม่เปิดเป็น window ใน session ของคนสั่ง เพราะ `cc` แบบ tmux อาศัยว่า session ปิดเองตอน Claude ออก window ของ worker ที่ค้างอยู่จะทำให้ session นั้นไม่ปิด รัน worker ผ่าน shell เพื่อให้ pane ไม่ปิดตอน worker จบ
   - ใส่เวลาในชื่อ เพราะ pane ของ worker รอบก่อนยังเปิดค้างอยู่ได้ (ชื่อซ้ำจะทำให้ `new-session` ล้ม)
   - คำสั่งที่เปิด worker ส่งแค่ token (worker อ่าน state จาก `restart.lock/state.<token>`) ไม่ส่งรายการ pane ทั้งหมด เพื่อให้สั้นกว่า 1024 byte ใส่ token ในชื่อไฟล์เพราะตัวที่แพ้แย่ง lock ค้างอาจเขียนลงโฟลเดอร์ lock ของตัวที่ชนะได้ หลังเขียน state ตัวเรียกตรวจ token ใน lock อีกครั้งก่อนเปิด worker ถ้าไม่ตรง ให้บอกว่าแพ้แย่ง lock แล้วจบโดยไม่เปิด worker
   - state เก็บ socket ของ tmux (ช่องแรกของ `$TMUX` ของตัวเรียก) ด้วย ให้ worker สั่ง `tmux -S <socket>` เพราะ worker ที่เปิดใน herdr ไม่มี `$TMUX` ถ้าตัวเรียกไม่มี `$TMUX` ใช้ socket ปกติเหมือน reload
   - worker ไม่ปิด pane ตัวเองตอนจบ ให้เหลือ `Summary` ไว้ให้อ่าน กิตปิดเอง
4. พิมพ์รายชื่อ session ที่จะ restart, pane ของ worker และ path ของ log

`restart.md` ให้ Claude รายงานสั้น ๆ ตามภาษาของผู้ใช้: จำนวนและชื่อ session, บอกว่าแต่ละตัวจะ restart ตอนว่าง, session นี้จะไปหลังตัวอื่น (ถ้าสคริปต์บอกว่าไม่เจอ session นี้ใน snapshot ให้บอกว่า session นี้ต้องปิดเปิดเอง), pane ของ worker, path ของ log และ handoff แล้วจบรายงานโดยไม่ถามอะไร (คำถามท้ายรายงานจะทำให้ session นี้ตอบ `NOT-READY` ตามข้อ 2 ของคำขอ handoff) กฎเหมือน reload: ไม่พิมพ์ลง pane เอง ไม่รับ argument

**หยุด worker**: Ctrl-C ใน pane ของมัน หรือปิด pane นั้น worker ดัก `INT` / `TERM` / `HUP`: ไม่เริ่ม pane ใหม่ ปล่อยให้ pane ที่ `/exit` ไปแล้วเปิดใหม่จนเสร็จ คืนค่า `remain-on-exit` ของทุก pane ที่ตั้งไว้แล้ว แล้วปล่อย lock สัญญาณพวกนี้ส่งไปทั้ง process group ของ pane ถ้าคำสั่งที่ส่งแป้น (`herdr agent prompt`, `herdr pane run`, `tmux paste-buffer` / `send-keys`, `tmux respawn-pane`) ตายกลางทาง worker จะไม่รู้ว่าแป้นไปถึงแล้วหรือยัง (คู่มือ herdr: call ที่ล้มเหลวไม่ได้แปลว่าไม่ได้ส่ง) และถ้าส่งซ้ำ คำสั่งเปิดใหม่ชุดที่สองจะกลายเป็นข้อความที่พิมพ์ลงใน Claude ตัวใหม่ จึง:
- รันคำสั่งที่ส่งแป้นใน process group ของตัวเอง โดยเปิด job control เฉพาะตอนเริ่มคำสั่ง (`set -m; cmd </dev/null >>"$log" 2>&1 & pid=$!; set +m` แล้ว `wait "$pid"` ถ้า trap ขัด `wait` ให้ `wait` ซ้ำ) สัญญาณจาก terminal จึงไม่ถึงคำสั่งพวกนี้ ห้ามเปิด `set -m` ค้างไว้ เพราะ bash จะให้คำสั่งที่รันหน้าสุด (`sleep`, `ps`) อยู่คนละ process group กับ worker แล้ว Ctrl-C จะฆ่าแค่ `sleep` ไม่ถึง trap ของ worker (ลองบน `/bin/bash` 3.2 แล้ว: job ที่เริ่มตอน `set -m` ได้ pgid ใหม่ คำสั่งหลัง `set +m` ได้ pgid เดียวกับ worker)
- ไม่ส่งแป้นซ้ำ: ถ้าคำสั่งล้มเหลว บันทึกคำสั่งเปิดใหม่ลง log แล้วเลิกแตะ pane นั้น ยกเว้นสามกรณี: คำขอ handoff ไม่ดูผลของคำสั่ง ให้ nonce entry เป็นตัวตัดสินตามขั้น 2, `/exit` ที่ส่งไม่สำเร็จยังเดินขั้น 4 ต่อ (รอดูว่า pid หายไปไหม ถ้าหายก็เปิดใหม่ตามปกติ ถ้าไม่หายก็ "did not exit") และ `respawn-pane` (ไม่ใส่ `-k`) ลองซ้ำได้หนึ่งครั้ง เพราะมันปฏิเสธ pane ที่ยังมี process อยู่

ตอนได้ `HUP` (pane ของ worker ถูกปิด) ให้ ignore `PIPE` และเปลี่ยน stdout กับ stderr ไปที่ `/dev/null` ก่อน เพราะ terminal ปิดไปแล้ว การเขียนออกจอจะฆ่า worker กลางขั้นเปิดใหม่ ก่อน `/exit` ทุกครั้ง worker บันทึกคำสั่งเปิดใหม่ของ pane นั้นลง log ไว้ก่อน ถ้า worker ตายกลางทางจริง ๆ กิตยังเปิดเองได้

### 3. worker

กติกาที่ใช้ทุกขั้น:

- เช็กทุก 10 วินาที **(Claude เลือก)**
- **ตรวจตัวตนทุกรอบและก่อนกดแป้นทุกครั้ง จนถึงตอนส่ง `/exit`**: pid เดิมยังอยู่, session file ของ pid นั้นยังมี `procStart` เดิมและตรงกับเวลาเริ่มของ process ที่รันอยู่ (`LC_ALL=C ps -o lstart= -p <pid>` ยุบช่องว่างก่อนเทียบ เพราะ `lstart` เติมช่องว่างหน้าวันที่หลักเดียว), tty ของ pid ยังเป็นตัวเดิม, ยังเป็น process ที่ทำงานอยู่ใน pane นั้น (herdr: pane id ยังอยู่) และ**ต้องอยู่หน้าสุดของ terminal** (`pgid` ของ Claude เท่ากับ `tpgid`) ถ้า pid หรือ pane หายไป หรือ `procStart` / tty ไม่ตรง ให้บันทึก "gone" แล้วเลิกแตะ pane นั้นถาวร ถ้าแค่ไม่อยู่หน้าสุด (เช่นถูก Ctrl+Z) ให้รอ ไม่กดแป้น หลังส่ง `/exit` แล้ว pid หายไปคือสิ่งที่ขั้น 4 รออยู่ ไม่ใช่ "gone" ตั้งแต่ตรงนั้นใช้กติกาของขั้น 4–6 (herdr: Claude ออกแล้ว pane จะหายจาก `agent list` ให้ดูว่า pane ยังอยู่จาก `herdr pane list` แทน)
- **tmux: pane ต้องไม่อยู่ใน mode** (`#{pane_in_mode}` เป็น `0`) ก่อนกดแป้นทุกครั้ง ถ้ากิตกำลัง scroll ใน copy mode แป้นจะไปลง copy mode แทน Claude (Enter จะ copy แล้วออกจาก mode) ถ้าอยู่ใน mode ให้รอ ไม่ข้าม
- **ช่องขอ handoff มี 2 ช่อง** **(Claude เลือก)** เพราะทุก pane ต้องส่ง context ทั้งก้อนไปพร้อมกัน อาจชน rate limit pane ถือช่องเฉพาะตั้งแต่ส่งคำขอจนอ่านคำตอบเสร็จ pane ที่รออยู่ (busy, มีงานเบื้องหลัง, `NOT-READY`, รอขอใหม่) ไม่ถือช่อง
- **session ที่เป็นคนสั่งไปหลังตัวอื่น**: เริ่มได้เมื่อไม่มี pane อื่นถือช่องขอ handoff อยู่ ไม่มี pane อื่นที่พร้อมแล้วและรอช่องอยู่ และไม่มี pane อื่นที่ส่ง `/exit` ไปแล้วแต่ยังไม่ถึงตอนจบขั้น 6 pane ที่ยังไม่พร้อม (ขั้น 1, รอหลัง `NOT-READY`, รอขอใหม่, ขั้น 4 ที่ยังรอก่อนส่ง `/exit`) ไม่กั้น pane ที่ค้างนานจึงไม่ทำให้ session ที่กิตใช้อยู่ไม่ได้ restart
- เพดาน 4 ชั่วโมง **(Claude เลือก)** ใช้กับขั้น 1–3 และขั้น 4 ก่อนส่ง `/exit` เท่านั้น (pane ที่ค้างอยู่ใน copy mode หรือถูก Ctrl+Z หลังได้ handoff แล้วจึงไม่ทำให้ worker รอไม่จบ) นับจากตอนเริ่ม worker สำหรับ pane อื่น และนับจากตอนที่ session ที่เป็นคนสั่งเริ่มได้ สำหรับ session นั้น pane ที่ยังไม่ได้ส่ง `/exit` ตอนครบเวลาจะถูกข้ามพร้อมเหตุผลใน log (แยกเหตุผลว่าค้างเพราะอะไร เช่น "background process still running") ส่วน pane ที่ `/exit` ไปแล้วต้องเปิดใหม่ให้เสร็จเสมอ
- **มีความเคลื่อนไหว** ดูเฉพาะ session ของ pane นั้นเอง: `sessionId` หรือ `statusUpdatedAt` ใน session file ของ pid นั้นเปลี่ยนจากจุดเทียบ (ข้อ 3) หรือมี prompt entry หรือ message ใหม่ของ Claude ใน transcript ของ `sessionId` ปัจจุบันหลังจุดเทียบ **prompt entry** คือ `type: "user"` ที่ content เป็น string และไม่ใช่ `isMeta` (ไม่นับ `tool_result` ที่เป็น `type: "user"` เหมือนกัน) หรือ `type: "attachment"` ที่ `attachment.type` เป็น `"queued_command"` (ข้อความที่เข้ามาตอน Claude ทำงานอยู่ ซึ่งถูกรวมเข้า turn นั้น) ไม่ดู session อื่นในโฟลเดอร์เดียวกัน เพราะหลาย session ใช้โฟลเดอร์ transcript เดียวกันได้ และ path ต่างกันก็อาจได้ชื่อโฟลเดอร์เดียวกัน (`/a/b_c`, `/a/b.c`, `/a/b/c` เป็น `-a-b-c` ทั้งหมด)
- **ถามซ้ำได้ไม่ถี่กว่า 30 นาทีต่อ pane** **(Claude เลือก)** ไม่ว่าจะเพราะ `NOT-READY` หรือ handoff ตกรุ่น กัน `/loop` หรือ session ที่คุยต่อเนื่องทำให้ส่ง context ทั้งก้อนซ้ำ ๆ

แต่ละ pane:

1. **รอว่าง**: ทุกข้อต้องจริง
   - session file `status` เป็น `idle` (ค่าอื่นทั้งหมด เช่น `busy`, `shell` ถือว่าไม่ว่าง)
   - เกณฑ์เดียวกับ reload (herdr: `idle` หรือ `done` และช่องพิมพ์ว่าง / tmux: อ่านจอแล้วไม่ busy ไม่มีคำถาม ช่องพิมพ์ว่าง)
   - ไม่มี process ลูกของ Claude ที่เป็น shell ของ background Bash หรือ Monitor ถ้ามี ให้รอต่อโดยไม่ต้องถาม
2. **ขอ handoff**: พิมพ์ข้อความบรรทัดเดียวที่มีรหัสสุ่มของรอบนั้น (`<nonce>`) ประมาณนี้

   `[kit-update restart <nonce>] ตอบเป็น handoff ของงานใน session นี้ในแชทเลย ห้ามเขียนไฟล์และห้ามเรียก tool ใด ๆ รวมถึง handoff ของ kit-checkpoint ใช้หัวข้อตามนี้ตรงตัว: เป้าหมาย / ทำเสร็จแล้ว / ค้างอยู่ตรงไหน / ตัดสินใจอะไรไปแล้วและเพราะอะไร / ไฟล์ที่เกี่ยวข้อง / ขั้นต่อไป ยกเว้นสองกรณีให้ตอบ NOT-READY: <เหตุผลหนึ่งบรรทัด> แล้วจบ turn (1) ยังมีงานเบื้องหลังที่ยังไม่จบ (background Bash, subagent, teammate ของ agent team, Monitor, /loop) ไม่นับ worker ของ kit-update restart (2) หลังคำถามล่าสุดที่คุณถามผู้ใช้ ยังไม่มีข้อความจากผู้ใช้เข้ามาเลย (ข้อความ [kit-update restart ...], คำตอบ NOT-READY ของคุณเอง, task notification และรอบของ /loop ไม่นับเป็นข้อความจากผู้ใช้) ไม่นับคำถามในสรุปที่คุณตอบกลับ handoff ที่ส่งมาเป็นข้อความแรก เช่นจาก [kit-update restart] หรือ [kit-checkpoint #...] (เรื่องที่ค้างอยู่ใน handoff แล้ว)`

   (ข้อ 2 เขียนแบบนี้เพราะถ้าถามแค่ว่า "คำตอบล่าสุดถามผู้ใช้ไว้ไหม" พอถามรอบสอง คำตอบล่าสุดจะเป็น NOT-READY รอบแรกหรือรายงานของ task notification แทนคำถาม แล้ว Claude จะตอบ handoff ทั้งที่กิตยังไม่ได้ตอบ)

   ส่งข้อความด้วยวิธีที่ Claude Code รับเป็นข้อความเดียว: herdr ใช้ `agent prompt` แบบไม่มี `--wait` (stall หรือ timeout ของ herdr ไม่ได้แปลว่าข้อความไม่ถึง) tmux ใช้ buffer ที่ตั้งชื่อเอง `load-buffer -b kit-update-<nonce> <path เต็มของไฟล์ข้อความ>` (อ่านจากไฟล์ ไม่ใช่ `-` เพราะ stdin ของคำสั่งที่ส่งแป้นมาจาก `/dev/null`) + `paste-buffer -b kit-update-<nonce> -p -d` (bracketed paste; ตั้งชื่อเพื่อไม่ให้ไปหยิบ buffer ที่กิต copy ไว้) แล้วตามด้วย Enter ใน tmux ครั้งเดียวกัน (`\;`) ตัวตัดสินเดียวว่าส่งเข้าคือ nonce entry ใน transcript ถ้าภายใน 30 วินาทีไม่เห็น และ `status` ไม่ได้เปลี่ยนเป็น `busy` หลังส่ง ให้บันทึก "request not submitted" (ถ้าเป็น `busy` แล้ว เช่นกำลัง auto-compact ก่อนเขียน prompt ให้รอ nonce entry ต่อจนครบ 15 นาทีของขั้น 3) แล้วเลิกแตะ pane นั้น (ข้อความอาจค้างในช่องพิมพ์ กิตลบเองได้)

   Claude ตอบเป็นข้อความ ไม่ได้เขียนไฟล์ จึงไม่มี permission prompt **(Claude เลือก: เพราะกิตไม่ได้อยู่หน้าจอทุก session)** และให้ Claude บอกเองว่ายังมีงานเบื้องหลังที่ตรวจจากข้างนอกไม่ได้หรือคำถามค้างอยู่ **(Claude เลือก)**
3. **อ่านคำตอบ**: จดตำแหน่งท้ายไฟล์ (byte offset) ของ transcript ของ `sessionId` ปัจจุบัน (`~/.claude/projects/*/<sessionId>.jsonl`) ไว้**ก่อนส่ง**คำขอ ถ้ายังไม่มีไฟล์ (session ที่ยังไม่เคยคุย) ใช้ offset 0 ไม่นับเป็น "ไม่เจอ transcript" ทุกรอบเช็กอ่านเฉพาะส่วนที่ต่อท้ายหลัง offset นั้น **(Claude เลือก: ไม่สแกนไฟล์หลาย MB ทุก 10 วินาที)** ด้วย `jq -R 'fromjson?'` เพื่อข้ามบรรทัดท้ายที่ยังเขียนไม่ครบ ไม่ต้องรอ pane ว่างก่อนอ่าน (prompt ที่ queue ไว้อาจทำให้ pane ไม่ว่างอีกนาน)
   - ถ้า `sessionId` ใน session file เปลี่ยนไปแล้ว (เช่นถูก `/clear`): handoff ใช้ไม่ได้ กลับไปขั้น 1 โดยไม่นับเป็นครั้งที่ล้มเหลว
   - หา **nonce entry**: prompt entry ที่ขึ้นต้นด้วย `[kit-update restart <nonce>]` เท่านั้น (nonce อาจไปโผล่ใน log หรือในที่อื่น) สำหรับ `queued_command` เทียบที่ `attachment.prompt` ถ้า nonce entry เป็น `queued_command` (มีอะไรปลุก Claude ระหว่างเช็กว่าว่างกับตอนกดแป้น คำขอจึงถูกรวมเข้า turn ที่กำลังทำงาน) ถือว่าตกรุ่น ไม่ใช่ล้มเหลว
   - **คำตอบ** = entry ของ Claude หลัง nonce entry จนจบ message แรกที่ `stop_reason` ไม่ใช่ `tool_use` (`end_turn`, `max_tokens`, API error) หนึ่ง message ถูกแยกเป็นหลาย entry ที่มี `message.id` และ `stop_reason` เดียวกัน (เช่น `thinking` แล้วตามด้วย `text`) จึงต้องเอาทุก entry ของ message นั้น ไม่ใช่ตัดที่ entry แรก คำตอบถือว่าจบเมื่อ pane กลับมาว่าง หรือมี prompt entry หรือ message ใหม่ของ Claude ตามมา ถ้าเจอ `tool_use` ในคำตอบ นับว่าไม่ผ่านทันทีโดยไม่ต้องรอให้จบ
   - **ตกรุ่น**: มี prompt entry (รวม `queued_command`) หลัง nonce entry ไม่ว่าจะมาก่อนหรือหลังคำตอบจบ (กิตพิมพ์ตอน Claude กำลังตอบ, ข้อความที่ queue ไว้, Remote Control, task notification), มี message ใหม่ของ Claude หลังคำตอบ หรือคำตอบถูกขัด (`stop_reason` เป็น null หรือมี `[Request interrupted by user]` ตามมา) กลับไปขั้น 1 โดยไม่นับเป็นครั้งที่ล้มเหลว และถามใหม่ได้เมื่อ pane ว่างและครบ 30 นาทีตามกติกาถามซ้ำ ไม่ต้องรอความเคลื่อนไหว (ต่างจาก `NOT-READY`) ยกเว้นหนึ่งกรณีที่ไม่นับว่าตกรุ่น: `queued_command` ที่ `commandMode` เป็น `"task-notification"` ซึ่งอยู่ระหว่าง nonce entry กับ entry แรกของคำตอบ Claude อ่านมันใน turn เดียวกันก่อนตอบแล้ว (ตอน process เริ่มหรือหลัง `/clear` จะมีแบบนี้ต่อท้าย prompt แรกเสมอ ถ้านับว่าตกรุ่น session ที่ยังไม่มีใครพิมพ์อะไรจะไม่ได้ restart เลย) ส่วน `commandMode: "prompt"` ตกรุ่นเสมอไม่ว่าอยู่ตรงไหน entry อื่นที่ต่อท้าย turn ปกติ (`system`, `attachment` ที่ไม่ใช่ `queued_command`, `file-history-snapshot`, `last-prompt`, `custom-title` ที่เห็นในเครื่องของกิต) ไม่นับ
   - **จุดเทียบ** ของความเคลื่อนไหวหลังคำตอบ (ใช้ทั้งกับ `NOT-READY` และ handoff): offset ท้ายคำตอบ และ `statusUpdatedAt` ตอนที่เช็กแล้วเจอ pane ว่างครั้งแรกหลังคำตอบจบ
   - **คำตอบขึ้นต้นด้วย `NOT-READY`** (ข้ามช่องว่าง, `**` และ backtick ที่นำหน้า): ยังไม่พร้อม รอจน**มีความเคลื่อนไหว**หลังจุดเทียบและ pane กลับมาว่าง แล้วค่อยกลับไปขั้น 1 ด้วย nonce ใหม่ (ตามกติกาถามซ้ำไม่ถี่กว่า 30 นาที)
   - **เป็น handoff ที่ใช้ได้** เมื่อครบทุกข้อ:
     - ไม่มี `tool_use` ในคำตอบ
     - ไม่มี entry ที่ `message.model` เป็น `"<synthetic>"` หรือมี `isApiErrorMessage`
     - message สุดท้ายของคำตอบมี `stop_reason` เป็น `end_turn`
     - มีหัวข้อครบทั้ง 6 หัวข้อ เทียบด้วยคำสั้นหนึ่งคำต่อหัวข้อ (`เป้าหมาย`, `ทำเสร็จ`, `ค้าง`, `ตัดสินใจ`, `ไฟล์`, `ขั้นต่อไป`) ไม่เทียบทั้งประโยค (handoff ที่แค่พูดถึงคำว่า NOT-READY ข้างในยังนับว่าใช้ได้)
     worker เอา `text` ทุกส่วนของคำตอบมาต่อกันแล้วเขียนลงไฟล์เอง
   - **อย่างอื่นทั้งหมด** (API error, เรียก tool, ถูกตัดที่ `max_tokens`, หัวข้อไม่ครบ, ไม่เจอ transcript หรือคำตอบไม่จบภายใน 15 นาทีหลังขอ **(Claude เลือก)**): ไม่ใช่ handoff บันทึกเหตุผล **ไม่ปิด Claude** แล้วขอใหม่หลัง 5 นาที รวมไม่เกิน 3 ครั้ง **(Claude เลือก)** ครบแล้วข้าม pane นั้นด้วยเหตุผล "no valid handoff"
4. **ปิด**: ก่อน `/exit` เช็กอีกครั้งว่าว่าง, ตัวตนตรง, ไม่มี shell ลูกของ background Bash หรือ Monitor และไม่มีความเคลื่อนไหวหลังจุดเทียบตอนรับ handoff (ถ้ามี กิตพิมพ์อะไรเข้าไประหว่างนั้น handoff ตกรุ่นแล้ว ให้กลับไปขั้น 1 และขอใหม่ตามกติกาถามซ้ำ **(Claude เลือก)**) บันทึกคำสั่งเปิดใหม่ลง log และเช็กว่าบรรทัดคำสั่งเปิดใหม่ยาวไม่เกิน 1024 byte (ชื่อภาษาไทยใช้ 3 byte ต่อตัวอักษร และ `%q` เพิ่มความยาวอีก) ถ้าเกิน ให้ข้าม pane นั้นตั้งแต่ตอนนี้ด้วยเหตุผล "relaunch command too long" เพราะถ้า `/exit` ไปแล้วจะเหลือแค่ shell เปล่า
   - tmux **(Claude เลือก)**: ตั้ง `remain-on-exit on` ให้**ทุก** pane ก่อน `/exit` (pane ที่ shell เป็น `sh -c` ก็ตายตาม Claude ได้) และคืนค่าเดิมทุกทาง (เปิดใหม่สำเร็จ, did not exit, เปิดใหม่ไม่สำเร็จ, worker ถูกหยุดระหว่างตั้งค่ากับ `/exit`) ถ้าเดิม pane ไม่ได้ตั้งค่านี้ไว้เอง ให้คืนด้วย `set-option -pu` (กลับไปใช้ค่าของ window) ไม่ใช่ตั้งเป็น `off`
   - พิมพ์ `/exit` รอจน pid ของ Claude หายไป ถ้าเกิน 60 วินาทีให้ข้ามด้วยเหตุผล "did not exit"
5. **เปิดใหม่**: worker ประกอบไฟล์ข้อความแรก (`.start.md` ข้างไฟล์ handoff) = บรรทัดหัว + เนื้อหา handoff + บรรทัดท้าย แล้วสั่ง

   `claude --name <ชื่อ> "$(cat <ไฟล์ start>)"`

   - **ก่อนพิมพ์**: shell ตัวเดิมที่เป็นแม่ของ Claude ตัวเก่าต้องอยู่หน้าสุดของ terminal (`pgid` ของ shell เท่ากับ `tpgid`) worker เช็กเองทั้ง tmux และ herdr เช็กซ้ำทุกวินาทีได้นานสุด 10 วินาที เพราะหลัง Claude ออก shell อาจยังไม่ได้ terminal คืนทันที หรือกำลังรัน prompt hook อยู่ ถ้าครบ 10 วินาทีแล้วยังเป็นอย่างอื่น (`vim`, Claude ที่กิตเปิดเอง, ...) ให้ข้ามและบันทึกคำสั่งให้กิตเปิดเอง ข้อความที่พิมพ์ค้างใน shell เช็กไม่ได้ ช่วงระหว่าง Claude ออกกับเปิดใหม่สั้นแค่ไม่กี่วินาที จึงยอมรับความเสี่ยงนี้ **(Claude เลือก)**
   - ส่งคำสั่ง: tmux ใช้ `send-keys -l <คำสั่ง>` กับ `send-keys Enter` ใน tmux ครั้งเดียวกัน (`\;`) / herdr ใช้ `herdr pane run <pane> "claude --name <ชื่อ> \"\$(cat <ไฟล์ start>)\""` ให้ shell ของ pane เป็นคน expand `$(cat ...)` เนื้อหา handoff จึงไม่อยู่ในบรรทัดคำสั่ง บรรทัดสั้นกว่า 1024 byte ไม่ใช้ `herdr agent start` เพราะมันรับ argument เอง (`$(cat ...)` จะไม่ถูก expand) และใส่ handoff ทั้งก้อนจะเกิน 1024 byte
   - herdr: ถ้าเดิม pane มีชื่อ agent ให้ตั้งคืนด้วย `herdr agent rename` หลัง Claude ตัวใหม่ขึ้น (ชื่อเดิมผ่านรูปแบบของ herdr อยู่แล้ว) ถ้าเดิมไม่มีก็ไม่ตั้ง
   - ใส่ quote ชื่อและ path ด้วย `printf %q`
   - บรรทัดหัว: `[kit-update restart] handoff จาก session ก่อน restart (Claude Code <version จาก session file> → <เวอร์ชันใหม่>)`
   - บรรทัดท้าย: `ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร แล้วรอ` (ข้อความเดียวกับ kit-checkpoint)
   - `<ชื่อ>` **(Claude เลือก)**: `name` จาก session file (ชื่อ session ของ Claude เอง) ถ้าว่าง herdr ใช้ชื่อ agent หรือ `label` ของ workspace / tmux ใช้ชื่อ session herdr ตั้งชื่อ agent กลับคืนให้ด้วยถ้าเดิมมี
   - เปิดด้วย `claude` เปล่า ๆ บวก `--name` เท่านั้น ไม่เอา flag ของตัวเก่ามาด้วย **(Claude เลือก)** เพราะการแยก flag ออกจาก `--continue`/`--resume`/ข้อความแรกจาก command line เดิมเปราะเกินไป worker บันทึกลง log ว่าตัวเก่าเปิดด้วย command line อะไร และ README เตือนว่า flag อย่าง `--plugin-dir`, `--model`, `--permission-mode` จะไม่ตามมา
   - tmux หลัง `/exit`: ถ้า pane ตายแล้ว (Claude เป็น process ของ pane หรือ shell แบบ `sh -c` ออกตาม) ใช้ `respawn-pane` แบบส่ง argv ซึ่งไม่ผ่าน `default-shell` ของ tmux และไม่ต้อง quote: `tmux respawn-pane -t <pane> -c <cwd จาก session file> /bin/sh -c 'exec claude --name "$1" "$(cat "$2")"' sh <ชื่อ> <ไฟล์ start>` (`exec` ให้ Claude แทนที่ shell `/exit` ครั้งต่อไปจะปิด pane ตามปกติ และ pane แบบ `cc` ไม่มี shell ของผู้ใช้ จึงพึ่ง `default-shell` ซึ่งอาจเป็น fish ไม่ได้) ถ้า shell ตัวเดิมอยู่หน้าสุด ใช้ `send-keys` ถ้าเป็นอย่างอื่น ข้ามและบันทึกคำสั่งไว้ แล้วคืนค่า `remain-on-exit`
6. **ยืนยัน**: รอจนมี session file ใหม่ที่ pid เป็นลูกของ shell ใน pane นั้น (หรือเป็น process ของ pane หรือลูกของมัน สำหรับ respawn) ภายใน 60 วินาที ถ้ายังไม่มี session file แต่มี process `claude` ใหม่ใน pane แล้ว (เปิดครั้งแรกหลังอัปเดตอาจติด dialog อยู่) ให้บันทึกว่า "started, waiting on screen" ถ้าไม่มีทั้งสองอย่างให้บันทึกว่า "relaunch failed" พร้อมคำสั่งที่ผู้ใช้เปิดเองได้

### 4. ไฟล์

ทั้งหมดอยู่ใน `~/.claude/kit-update/` **(Claude เลือก)**

ทุกที่ใน spec นี้ที่เขียนว่า `~/.claude` (session file, transcript, ไฟล์ของ restart) สคริปต์ใช้ `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` จาก environment ของ session ที่สั่ง และส่งให้ worker ผ่าน state เพราะผู้ใช้ที่ตั้ง `CLAUDE_CONFIG_DIR` ไว้จะไม่มีไฟล์ใน `~/.claude`

- `restart.lock/`: โฟลเดอร์ lock มี `starting <token>` หรือ token, pid, command line และ pane ของ worker ลบตอน worker จบหรือถูกหยุด (เฉพาะเจ้าของ token)
- `restart.lock/state.<token>`: snapshot ที่ตัวเรียกส่งให้ worker
- `restart.log`: หนึ่งบรรทัดต่อเหตุการณ์ พร้อมเวลาและชื่อ pane ตอนจบมีบรรทัด `Summary` แบบเดียวกับ reload (restarted / skipped พร้อมเหตุผล) worker พิมพ์บรรทัดเดียวกันลง pane ของตัวเองด้วย
- `handoffs/<YYYYMMDD-HHMMSS>-<ชื่อ>-<pane id>.md` และ `.start.md`: ชื่อและ pane id แทนอักขระที่ไม่ใช่ตัวอักษร ตัวเลข `-` `_` ด้วย `_` กันชื่อที่มี `/` และกันสอง pane ชื่อซ้ำในวินาทีเดียวกัน ตัดส่วนของชื่อไว้ไม่เกิน 40 byte (path ของไฟล์ start อยู่ในบรรทัดคำสั่งเปิดใหม่) ไม่ลบ

### 5. เอกสารและเวอร์ชัน

- README:
  - ส่วนของ kit-update เพิ่ม `/kit-update:restart` อธิบายว่ารอว่าง, เขียน handoff, เปิดใหม่, worker อยู่ที่ไหนและหยุดด้วย Ctrl-C (pane ของ worker ไม่ปิดเอง), ไฟล์อยู่ที่ไหน, token ที่ใช้เขียน handoff, การตรวจที่เป็น best effort สำหรับ subagent, teammate, `/loop` และคำถามที่ยังไม่ได้ตอบ, **session ที่มี process เบื้องหลังรันตลอด (dev server, watcher) จะไม่ถูก restart** และถูกข้ามหลัง 4 ชั่วโมง, flag ตอนเปิดที่ไม่ตามมา และ shell ใน pane ต้องเป็น bash หรือ zsh
  - "command ทั้งห้า" เปลี่ยนเป็น "ทั้งหก"
- `plugin.json`: bump เป็น `0.2.0` **(Claude เลือก: เพิ่มคำสั่งใหม่)** และแก้ description ให้พูดถึง restart
- `.claude-plugin/marketplace.json`: แก้ description ของ kit-update
- `CLAUDE.md` ของ repo: บรรทัดสรุป plugin (kit-update รัน `scripts/restart-all.sh` ด้วย) และบรรทัดคำสั่ง test
- `guides/tmux-remote-control.md`: ตรงที่พูดถึง `/kit-update:reload` เพิ่ม `/kit-update:restart`
- เว็บ: หน้า Tools ต้องเพิ่มคำสั่งนี้ตาม checklist ใน `phimee-and-kit-website/CLAUDE.md` เป็น PR แยกในเว็บ

## ทางที่พิจารณาแล้วไม่เลือก

- **`/restart` ที่มีใน Claude Code**: เปิดปิดด้วย feature flag ฝั่ง Anthropic เครื่องของกิตยังไม่เปิด และมันเก็บบทสนทนาเดิมไว้ ซึ่งไม่ใช่สิ่งที่กิตต้องการ
- **`claude --resume <session id>`**: ได้เวอร์ชันใหม่โดยไม่ต้องเขียน handoff ไม่เสีย token แต่ context ไม่ได้เริ่มใหม่
- **ใส่ไว้ใน kit-checkpoint หรือใช้ tool `handoff` ของมัน**: kit-checkpoint เป็น hooks module ไม่มี script ส่วนการไล่ pane ต้องใช้ script และ tool `handoff` ปฏิเสธเมื่อ context <400K
- **ข้าม session ที่ไม่ว่าง**: กิตเลือกให้รอจนว่าง
- **ให้ Claude เขียน handoff ลงไฟล์เอง**: ไฟล์นอกโฟลเดอร์งานต้องขอ permission ถ้ากิตไม่อยู่ ทุก session จะค้าง ส่วนในโฟลเดอร์งานก็เขียนไม่ได้ เพราะห้ามแตะ repo ของผู้ใช้
- **ดูจาก herdr `done` กับ `idle` ว่ากิตเห็นคำตอบล่าสุดแล้วหรือยัง**: แยกไม่ออกว่าข้อความสุดท้ายเป็นคำถามหรือแค่รายงาน และ tmux ไม่มีสถานะนี้ ให้ Claude ตอบ `NOT-READY` เองแทน
- **อ่านหน้าจอหาสัญญาณงานเบื้องหลัง**: ข้อความใน footer ของ Claude Code เปลี่ยนได้ทุกเวอร์ชัน และ `/loop` ไม่ขึ้นที่ footer ใช้ process ลูกกับ `NOT-READY` แทน
- **worker แบบ `nohup` + `disown`**: ไม่รู้ว่าจะรอดตอน Claude ที่สั่งออกหรือเปล่า และต้องมี pidfile กับวิธี kill แยก pane ของตัวเองรอดแน่ ดูความคืบหน้าได้ และหยุดด้วย Ctrl-C ได้
- **v1 รองรับแค่ herdr**: ตัดงานฝั่ง tmux ได้สามส่วน แต่คนที่ทำตาม guide (เส้นทางหลักเป็น tmux) จะใช้ไม่ได้เลย
- **ให้ session ที่สั่งรอจนทุก pane เสร็จหรือถูกข้าม**: pane ที่มี dev server รันอยู่จะดึงให้ session ที่กิตใช้อยู่ไม่ได้ restart ไปด้วย
- **ค้น nonce ในทุก `.jsonl` ใต้ `~/.claude/projects`** (แบบรอบแรก): หนักเมื่อสแกนทุก 10 วินาที และไม่จำเป็นแล้ว เพราะ session file บอก `sessionId` ปัจจุบัน ถ้ามันเปลี่ยนก็ถือว่าตกรุ่น
- **ดูความเคลื่อนไหวจากทั้งโฟลเดอร์ transcript**: session อื่นในโฟลเดอร์เดียวกันจะทำให้ pane ตกรุ่นวนไม่จบ

## ให้ builder ตัดสินใจเอง

- โครงของ worker (loop เดียวไล่ทุก pane หรือ job แยกต่อ pane) ภายใต้ bash 3.2
- จะแยกฟังก์ชันตรวจว่าว่างออกจาก `reload-all.sh` มาใช้ร่วมกัน หรือทำซ้ำในไฟล์ใหม่
- วิธีแยก shell ลูกของ background Bash หรือ Monitor ออกจาก process ลูกอื่นของ Claude เช่น MCP server
- ถ้อยคำใน log และในข้อความรายงาน

## ต้องเช็คระหว่างทำ

- `claude --name <ชื่อ> "<ข้อความยาวหลายบรรทัด>"` เปิดแบบ interactive แล้วส่งข้อความแรกจริง
- `herdr agent prompt` กับข้อความภาษาไทยบรรทัดเดียว และ `tmux load-buffer` + `paste-buffer -p -d` + Enter กับข้อความเดียวกัน ส่งเข้าจริงเป็นข้อความเดียว
- transcript เก็บข้อความที่ paste เข้าไปเต็ม ๆ (ไม่ใช่ `[Pasted text #1]`) เพราะการหา nonce entry อาศัยข้อนี้
- herdr ให้ pid หรือ tty ของ pane ได้ทางไหน (ใช้ยืนยันว่า shell ตัวเดิมยังอยู่หน้าสุด)
- กับ Claude จริง: session ที่เปิดจาก restart รอบก่อนแล้วไม่มีใครแตะ ตอบ handoff ไม่ใช่ `NOT-READY` และ session ที่เป็นคนสั่ง (ที่มี worker รันอยู่) ก็ตอบ handoff
- ขีดจำกัด 1024 byte ของ `herdr pane run` และรูปแบบชื่อ agent ตรงกับ `herdr pane run --help` / `herdr agent rename --help` ของเวอร์ชันที่ใช้
- `/exit` ที่พิมพ์เข้าไปทำให้ Claude ออกจริง และ session file ของมันหายไปตอนออก
- session file: `sessionId` เปลี่ยนหลัง `/clear` หรือเปล่า, `status` / `statusUpdatedAt` เปลี่ยนทุก turn หรือเปล่า, **`statusUpdatedAt` นิ่งตอน idle หรือเปล่า** (เจอแล้วหนึ่งตัวที่เปิด Remote Control และ idle มาราวหนึ่งวันโดย `statusUpdatedAt` ไม่เปลี่ยน ถ้าเจอว่า heartbeat ทำให้มันเปลี่ยน ต้องเปลี่ยนไปดูแค่ `status` กับ prompt entry) และไฟล์ของ process ที่ตายไปค้างอยู่ไหม
- herdr อัปเดต `agent_session.value` หลัง `/clear` หรือเปล่า
- Remote Control เปิดเองใน session ใหม่ ถ้าผู้ใช้ตั้ง `remoteControlAtStartup` ไว้
- รูปแบบ transcript: ข้อความที่พิมพ์ผ่าน `herdr agent prompt` / `tmux send-keys` ถูกบันทึกเป็น `type: "user"` ที่มี `<nonce>` ครบ, ผลจากงานเบื้องหลัง (task notification) และรอบของ `/loop` เข้ามาเป็น `type: "user"` ด้วยหรือเปล่า, และ `stop_reason` เมื่อถูกตัดที่ `max_tokens`
- Claude ขึ้นต้นด้วย `NOT-READY` ถูกจริงเมื่อมีงานเบื้องหลัง, teammate หรือ `/loop` และเมื่อข้อความก่อนหน้าเป็นคำถาม (ลองกับ session จริงทั้งสองแบบ) รวมถึงตอนถามรอบสองหลังมี task notification เข้ามาโดยกิตยังไม่ได้ตอบ และทำตามคำสั่ง "ห้ามเรียก tool" แม้ kit-checkpoint จะเตือนให้เรียก `handoff`
- process ลูกของ Claude: background Bash, Monitor และ MCP server หน้าตาเป็นยังไง แยกกันได้ไหม
- teammate ของ agent team ใน tmux แยกออกจาก session เดี่ยวได้ยังไง
- tmux ที่รันอยู่ใน pane ของ herdr: ยืนยันว่าตัด agent ฝั่ง herdr ออกได้จากการหา tmux ใน process ที่เป็นบรรพบุรุษของ Claude
- `tmux set-option -p remain-on-exit on` / `set-option -pu`, `respawn-pane -c` แบบส่ง argv และ `#{pane_in_mode}` ใช้ได้กับ tmux เวอร์ชันที่ใช้อยู่
- worker ใน pane หรือ window ของตัวเองรอดหลัง Claude ที่สั่งออก (ควรรอดเพราะไม่ใช่ process ลูกของมัน)
- ปิด pane ของ herdr หรือ `tmux kill-pane` ส่งแค่ `HUP` หรือตามด้วย `SIGKILL` (การดัก `HUP` ทั้งหมดอาศัยว่าได้แค่ `HUP`)
- ใน pane จริง (มี tty): คำสั่งที่เริ่มตอน `set -m` ไม่โดน Ctrl-C / `HUP` และ Ctrl-C ระหว่างที่ worker `sleep` อยู่ทำให้ trap `INT` ของ worker ทำงานจริง (ลองแบบไม่มี tty แล้วแค่เรื่อง pgid)
- `status: "shell"` ใน session file หมายถึงอะไร (Ctrl+Z, `!` bash mode, ...)
- `/exit` ใน session ที่เปิดด้วย `claude --worktree` ขึ้น dialog ถามว่าจะเก็บ worktree ไหม (จะจบที่ "did not exit")
- Claude Code ที่เปิด `/vim` แล้วอยู่ใน NORMAL mode: ข้อความที่พิมพ์เข้าไป (`/exit`, คำขอ handoff) กลายเป็นคำสั่ง vim หรือเปล่า
- herdr: pane ที่กิตกำลัง scroll อยู่ แป้นจาก `agent prompt` ไปถึง Claude หรือไปลงที่ scroll
- entry ที่ต่อท้าย turn ปกติ (`system`, `attachment`, ...) ไม่มี message ใหม่ของ Claude ปนมา และ task notification ที่ปลุก turn ใหม่บันทึกเป็น `attachment` ตามด้วย message ใหม่ของ Claude

## วิธีทดสอบ

- `scripts/restart-all.test.sh` ใช้ fake tmux และ fake herdr แบบเดียวกับ `reload-all.test.sh` และให้ override ได้ด้วย env: ช่วงเวลาเช็ก, timeout, โฟลเดอร์ state, โฟลเดอร์ transcript, โฟลเดอร์ session file และตัวดู process **รวมถึงการเช็กว่า pid ยังอยู่** (ห้ามเรียก `kill -0` กับ pid จริงตรง ๆ) เพื่อไม่ให้ test แตะ `~/.claude` หรือ process จริง รันบน `/bin/bash` 3.2 กรณีที่ต้องมี:
  - session ที่สั่งยังได้ restart แม้มี pane อื่นตอบ `NOT-READY` ตลอด
  - สอง pane กับ session ที่สั่งอยู่ในโฟลเดอร์ transcript เดียวกันและทำงานอยู่: แต่ละ pane ถูกถามซ้ำไม่ถี่กว่า 30 นาที ความเคลื่อนไหวของ session อื่นไม่ทำให้ pane ตกรุ่น
  - มี prompt entry ต่อท้ายหลัง handoff turn (ข้อความที่ queue ไว้): ไม่ `/exit` และ handoff ไม่ปนกับคำตอบของ turn ถัดไป
  - `sessionId` เปลี่ยนระหว่างรอคำตอบ: ไม่ `/exit`
  - nonce โผล่ในที่อื่นที่ไม่ใช่ nonce entry: ไม่นับ
  - ตอบ `**NOT-READY**` หรือมีช่องว่างนำหน้า: นับเป็น NOT-READY
  - lock: โฟลเดอร์ lock ว่าง (ช่วงหลัง `mkdir`) นับเป็น `starting` / สองตัวเจอ lock ค้างพร้อมกัน: เริ่มได้ตัวเดียว / token ไม่ตรง: worker จบโดยไม่แตะ pane
  - เปิดใหม่หลังอัปเดตแล้วติด dialog: บันทึก "started, waiting on screen" ไม่ใช่ "relaunch failed"
  - Claude ที่เปิดผ่าน wrapper ใน tmux: ข้าม
  - Claude ไม่อยู่หน้าสุด (ถูก Ctrl+Z แต่ herdr ยังขึ้น idle และ shell prompt ขึ้นต้นด้วย `❯`): ไม่พิมพ์อะไรลงไป
  - fake herdr ปฏิเสธคำสั่งที่ยาวเกิน 1024 byte (เฉพาะ `pane run` / `agent start` ไม่ใช่ `agent prompt`) และชื่อที่ไม่ตรงรูปแบบ: คำสั่งเปิดใหม่และคำสั่งเปิด worker ผ่าน
  - tmux pane ที่แม่ของ Claude เป็น `sh -c`: `remain-on-exit` → pane ตาย → `respawn-pane` ด้วย `exec claude` → คืนค่า
  - herdr pane ที่แม่ของ Claude ไม่ใช่ bash/zsh แบบ interactive: ข้ามตั้งแต่ snapshot
  - สอง process ใช้ `sessionId` เดียวกันใน tmux: ข้ามทั้งคู่
  - session ใหม่ที่ยังไม่มีไฟล์ transcript: offset 0 และอ่านคำตอบได้
  - session ที่สั่งไม่แทรกก่อน pane อื่นที่พร้อมและรอช่องอยู่
  - `HUP` พร้อมปิด stdout ของ worker: worker ไม่ตาย และเปิดใหม่ให้เสร็จ
  - ข้อความขอ handoff ส่งไม่เข้า (ไม่มี nonce entry ใน 30 วินาที): บันทึก "request not submitted" แล้วไม่แตะ pane นั้นอีก
  - `NOT-READY: <เหตุผล>`: นับเป็น NOT-READY และบันทึกเหตุผล
  - session file ที่ `kind` ไม่ใช่ `interactive` หรือไม่มี field ที่ต้องใช้: ข้ามตั้งแต่ snapshot
  - worker ที่แพ้ตอนแย่ง lock ค้าง: ไม่ลบ lock ของตัวที่ชนะ
  - session ที่สั่งไม่ได้อยู่ใน herdr หรือ tmux: สคริปต์บอกว่าไม่เจอ
  - ว่างอยู่: ขอ handoff → คำตอบใน transcript → เขียนไฟล์ → `/exit` → เปิดใหม่ด้วยข้อความแรกและชื่อจาก session file
  - busy แล้วค่อยว่าง
  - `blocked` จนครบเวลา: ข้าม ไม่พิมพ์อะไรลงไป
  - ตอบ `NOT-READY` (ทั้งแบบคำเดียวและแบบมีข้อความต่อท้าย): ไม่ `/exit` ไม่ถามซ้ำจนกว่าจะมีความเคลื่อนไหว แม้ turn ถัดไปจะสั้นกว่าช่วงเช็ก หรือย้ายไปไฟล์ใหม่หลัง `/clear` พอพร้อมแล้วจึง restart
  - `/loop` ที่มีความเคลื่อนไหวทุกไม่กี่นาที: ถามซ้ำไม่ถี่กว่า 30 นาที
  - handoff ที่ใช้ได้แต่มีคำว่า NOT-READY อยู่ข้างใน: ยอมรับ
  - คำตอบไม่ผ่านเกณฑ์: API error (`<synthetic>`), มี `tool_use`, `stop_reason` เป็น `max_tokens`, หัวข้อไม่ครบ, ไม่มีคำตอบ: ทุกกรณี**ไม่มี** `/exit` ขอใหม่ตามรอบ แล้วข้ามเมื่อครบ 3 ครั้ง
  - มี shell ลูกของ background Bash: รอโดยไม่ถาม
  - pane ไม่ใช่ Claude ตัวเดิมแล้ว (ปิดเอง, เปิดใหม่เอง, pid ถูกใช้ซ้ำ): ไม่พิมพ์อะไรลงไปอีก
  - หลัง `/exit` หน้าสุดของ pane ไม่ใช่ shell ตัวเดิม: ไม่พิมพ์คำสั่งเปิดใหม่ บันทึกคำสั่งไว้
  - session ที่สั่งไปหลังตัวอื่น และยังได้ restart แม้มี pane อื่นค้างด้วย background process ตลอด
  - ขอ handoff พร้อมกันไม่เกิน 2 pane และ pane ที่รออยู่ไม่ถือช่อง
  - ครบ 4 ชั่วโมงตอนที่ pane หนึ่ง `/exit` ไปแล้ว: pane นั้นยังเปิดใหม่จนเสร็จ
  - worker ได้ `HUP` ระหว่าง `/exit` กับเปิดใหม่ โดยส่งให้ทั้ง process group (`kill -HUP -<pgid>`): เปิดใหม่ให้เสร็จก่อน
  - ชื่อที่มีช่องว่างหรือ `/`: คำสั่งเปิดใหม่และชื่อไฟล์ถูกต้อง
  - tmux ที่รันใน pane ของ herdr: restart ครั้งเดียว และแป้นไปลง pane ของ tmux ไม่ใช่ pane ของ herdr
  - tmux pane ที่ Claude เป็น process หลัก: `remain-on-exit` → `respawn-pane` → ปิด `remain-on-exit`
  - lock: สั่งซ้ำตอน worker ยังทำงาน / ช่วงที่ worker ยังไม่เริ่ม (`starting`): ไม่เริ่มตัวที่สอง / lock ค้างจาก worker ที่ตาย หรือ `starting` เกิน 60 วินาที: เริ่มได้ / เปิด worker ไม่สำเร็จ: lock ถูกลบ
  - ไม่มี server เลย
  - tmux pane อยู่ใน copy mode: ไม่กดแป้นจนกว่าจะออกจาก mode แล้วจึง restart
  - คำขอ handoff ใช้ buffer ที่ตั้งชื่อเอง: buffer อื่นที่ผู้ใช้ copy ไว้ไม่ถูก paste
  - หลัง handoff turn มี message ใหม่ของ Claude ที่ task notification ปลุกขึ้นมา: handoff ตกรุ่น ไม่นับเป็นครั้งที่ล้มเหลว และ text ของ turn นั้นไม่ปนเข้าไปใน handoff
  - คำตอบที่ message เดียวแยกเป็น entry `thinking` + `text` ที่มี `end_turn` ทั้งคู่: ได้ text ครบ
  - prompt ที่ queue ไว้ทำให้ pane ไม่ว่างหลัง handoff turn: นับเป็นตกรุ่นภายในรอบเช็ก ไม่ใช่รอ 15 นาทีแล้วนับว่าล้มเหลว
  - Ctrl-C ระหว่าง `pane run` / `send-keys` ของคำสั่งเปิดใหม่: คำสั่งนั้นไม่ตาย และไม่มีการส่งซ้ำ
  - คำสั่งเปิดใหม่ล้มเหลว: บันทึกคำสั่งไว้ ไม่ส่งซ้ำ
  - `/exit` ที่คำสั่งส่งรายงานว่าล้มเหลวแต่ Claude ออกจริง: ยังเปิดใหม่ให้
  - `remain-on-exit` ที่เดิมไม่ได้ตั้งที่ระดับ pane: คืนด้วย `set-option -pu`
  - ตัวเรียกแพ้แย่ง lock ค้างหลังเขียน state ไปแล้ว: ไม่เปิด worker และ worker ของตัวที่ชนะอ่าน state ของตัวเอง
  - ส่ง `INT` ให้ process group ของ worker ระหว่าง `sleep` (แบบที่ Ctrl-C ทำ): trap ทำงานและ worker หยุดเริ่ม pane ใหม่
  - `queued_command` หลัง nonce entry ใน handoff turn: ตกรุ่น ไม่ `/exit`
  - คำตอบถูกขัด (`stop_reason` null แล้วตามด้วย `[Request interrupted by user]`): ตกรุ่น ไม่นับเป็นครั้งที่ล้มเหลว
  - herdr pane ที่แม่ของ Claude เป็น `-zsh` หรือ `/opt/homebrew/bin/zsh`: ไม่ข้าม
  - ตอบ `` `NOT-READY` `` ใน backtick: นับเป็น NOT-READY
  - หลัง `/exit` shell ได้ terminal คืนช้าไม่กี่วินาที: ยังเปิดใหม่ได้
  - หลัง `/exit` pid หายและ herdr pane หายจาก `agent list`: ไม่บันทึก "gone" และเปิดใหม่ตามปกติ
  - คำขอเป็น prompt แรกหลังเปิด, `--continue` หรือ `/clear` และมี `queued_command` แบบ `task-notification` สองตัวตามหลัง nonce entry ก่อนคำตอบ: รับ handoff และ `/exit`
  - `queued_command` แบบ `prompt` (`humanTurn`) ที่ตำแหน่งเดียวกัน: ตกรุ่น และถามใหม่หลัง 30 นาทีโดยไม่ต้องมีความเคลื่อนไหว
  - nonce entry เป็น `queued_command`: ตกรุ่น ไม่นับเป็นครั้งที่ล้มเหลว
  - ไม่เห็น nonce entry ใน 30 วินาทีแต่ `status` เป็น `busy`: รอต่อ ไม่บันทึก "request not submitted"
  - herdr pane ที่แม่ของ Claude เป็น `bash -lc ...` หรือ `zsh -ic ...`: ข้ามตั้งแต่ snapshot
  - ชื่อยาวจนบรรทัดคำสั่งเปิดใหม่เกิน 1024 byte: ข้ามก่อน `/exit`
  - pane ค้างใน copy mode หลังได้ handoff แล้ว: ไม่กั้น session ที่สั่ง และถูกข้ามเมื่อครบ 4 ชั่วโมง
  - ตัวเรียกอยู่ใน tmux ที่ใช้ socket อื่น แต่ worker เปิดใน herdr: worker ใช้ `tmux -S` กับ socket จาก state
  - `CLAUDE_CONFIG_DIR` ถูกตั้งไว้: อ่าน session file และ transcript จากโฟลเดอร์นั้น
- ทดสอบกับ herdr จริงใน workspace ทิ้งที่สร้างขึ้นเอง กับ Claude จริงหนึ่งตัว แล้วปิด workspace นั้น

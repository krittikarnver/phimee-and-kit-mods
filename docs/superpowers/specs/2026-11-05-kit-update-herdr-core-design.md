# kit-update reload/restart บน herdr-core: design

> 5 พ.ย. 2569 · ที่มา: คุยกับกิตใน session นี้ + probe กับ hc 0.1.18, Claude Code 2.1.318
> ข้อที่เขียนว่า **(Claude เลือก)** เป็นการตัดสินใจของ Claude ไม่ใช่ของกิต เปลี่ยนได้
> spec นี้แก้เฉพาะส่วนที่ต่างจาก [kit-update restart: design](2026-10-22-kit-update-restart-design.md) ส่วนอื่นยังเป็นไปตามฉบับนั้นทั้งหมด (ลำดับขั้นของ worker, lock, คำขอ handoff, การอ่านคำตอบ, tmux)

## เจตนา

`/kit-update:reload` และ `/kit-update:restart` ใช้กับ tmux หรือ herdr TUI (`herdr`) ได้เท่านั้น ส่วนกิตย้ายไปใช้แอป Herdr ซึ่งรัน terminal ผ่าน herdr-core (`hc`) แล้ว ทั้งสองคำสั่งเลยตอบ "No tmux or herdr server" ทุกครั้ง งานนี้ทำให้มันใช้กับ herdr-core ได้

กิตห่วงคนอื่นที่ติดตั้ง mod นี้ด้วย โดยเฉพาะคนที่เปิดคำแนะนำ prompt ของ Claude Code (prompt suggestions) ไว้ จึงต้องแยกคำแนะนำตัวจางออกจากข้อความที่ผู้ใช้พิมพ์ค้างได้เหมือนกับฝั่ง tmux ไม่ใช่ข้ามทุก session ที่มีข้อความในช่องพิมพ์

## เป้าหมาย

- reload และ restart ครอบคลุม Claude Code ที่รันใน terminal ของ herdr-core บนเครื่องนี้ เหมือนที่เคยทำกับ herdr TUI
- การเช็กว่าว่างเข้มเท่าฝั่ง tmux: ดูทั้งสถานะ และหน้าจอที่มีสี (busy / question / draft / idle) ด้วย `screen_state` ตัวเดิม
- tmux ทำงานเหมือนเดิมทุกอย่าง

## ไม่ทำ

- **herdr TUI: ตัดออกทั้งหมด** (กิตเลือก) ทั้งโค้ด, fake ใน test และเอกสาร คนที่ยังใช้ herdr TUI จะได้ "ไม่มี server" เหมือนไม่ได้ใช้ multiplexer
- terminal บนเครื่องอื่นที่ herdr-core ต่อไว้ (address แบบ `machine/t7`) **(Claude เลือก)**: session file ของมันไม่อยู่ในเครื่องนี้ ข้ามเงียบ ๆ ทั้ง reload และ restart
- rename agent หลังเปิดใหม่: herdr-core ไม่มีชื่อ agent แยกจาก terminal และ terminal เดิมยังอยู่ ชื่อกับ label (`where`) จึงคงเดิม
- เช็ก scroll: herdr-core ไม่มีสถานะนี้ การ scroll เกิดที่ฝั่งคนดู ส่วน `hc send` เขียนเข้า program ตรง ๆ
- เขียนคู่มือตั้งค่าแอป Herdr ใน guide

## สิ่งที่ต้องไม่เกิดเด็ดขาด

- พิมพ์เข้า session ที่กำลังทำงาน มีคำถามค้าง หรือมีข้อความที่ผู้ใช้พิมพ์ค้าง หรืออ่านหน้าจอไม่ได้แล้วเดาว่าว่าง (อ่านไม่ได้ = ข้าม/รอ)
- ส่งข้อความผ่าน `hc send` โดยยังมี `HC_TERMINAL_ID` อยู่ใน environment: hc จะห่อข้อความเป็น `<hc from="…">…</hc>` แล้ว Claude จะรับเป็นแชต ส่วน shell จะได้ข้อความขยะ ทุกการเรียก `hc` ต้องผ่าน `env -u HC_TERMINAL_ID`
- ตัวอ่านหน้าจอพิมพ์อะไรเข้า terminal หรือ resize terminal: ต้อง attach แบบ `observe: true` เท่านั้น
- worker ตายตาม session ที่สั่ง: ต้องเปิดด้วย `--no-parent`
- `hc server stop/restart` หรือ `hc kill`/`hc rm` terminal ที่ไม่ได้เปิดเอง

## ข้อเท็จจริงที่ยืนยันแล้ว (probe 5 พ.ย. 2569, hc 0.1.18, Claude Code 2.1.318)

1. `hc read` ให้แค่ข้อความเปล่า ไม่มี escape code จึงแยกตัวจางไม่ได้ (`terminal.read` ใน API ก็ไม่มีตัวเลือก)
2. รูปแบบ frame มีเอกสารใน `schema/README.md` ของ repo herdr-core: `[channel u32 LE][kind u8][len u32 LE][payload]`, kind 0 DATA, 1 CREDIT, 2 CLOSE ส่วน `hc connect` คุย protocol นี้ผ่าน stdin/stdout ส่ง `hello` ด้วย `{"framed": true}` เป็นบรรทัด JSON แล้วรอคำตอบหนึ่งบรรทัด จากนั้นเป็น frame (channel 0 = JSON-RPC)
3. `terminal.attach` ด้วย `{terminal, cols, rows, observe: true}` ตอบ `channel` แล้วส่งหน้าจอแรกตามด้วย byte สดของ program ใน stream เดียวกัน แต่ละแถวคั่นด้วย `\r\n` มี SGR ครบ ข้อความจางมาเป็น `\e[2m` หน้าจอแรกขึ้นต้นด้วยชุด reset mode และ tab stop (`\e[?…l`, `\e[H\e[2J`, `\e[9G\eH` …) ติดอยู่กับแถวแรก
   - จาก source (`crates/herdr-core/src/viewers.rs` `first_paint`/`paint_state`, `wire.rs` `CHUNK`): หน้าจอแรก = `0x18` + หน้าจอ + `\e[?9001h` หรือ `\e[?9001l` + รายงาน OSC 7501 แล้ว stream ถูกส่งเป็น DATA frame ทีละไม่เกิน 16 KiB หน้าจอใหญ่จึงถูกแบ่งหลาย frame และ frame หนึ่งอาจมีทั้งท้ายหน้าจอและ byte สด ที่ probe เห็นเป็น frame เดียว (5–7 KB) เพราะเล็กกว่า 16 KiB
   - channel เดียวกันอาจมี frame ชนิดอื่น (RESIZE) ด้วย
4. หน้าจอแรกของ Claude ที่ idle เมื่อตัด `\r` แล้วผ่าน `screen_tail` + `screen_state` เดิมได้ `idle` และแถว `❯ \e[0m\e[2mdim suggestion\e[0m` ผ่าน `prompt_empty` ว่าว่าง ส่วน `❯ typed` ไม่ว่าง
5. `perl` (`/usr/bin/perl`) มากับ macOS มี `IPC::Open2`, `IO::Select`, `pack`/`unpack`
6. `hc ls --json`: `terminals[]` มี `address`, `agent` (`"claude-code"`, `"zsh"`, …), `cwd`, `state`, `status` (ไม่มี field เมื่อไม่มีสถานะ), `turn`, `where` (label ของแอป เช่น `"my-repo / 1"`), `name`
7. `hc get <t> --json`: `pid` และ `argv` ของ program ของ terminal (shell เช่น `["/bin/zsh","-l"]`), `foreground` (`{pid, argv, cwd, name}` ของ process หน้าสุด หรือ `null`), `status` (`{state, app, msg}` หรือ `null`), `state`, `cols`, `rows`
8. `env -u HC_TERMINAL_ID hc send <t> <text>`: เข้า Claude เป็นคำสั่งจริง (`/reload-plugins`, `/exit`) ส่วนใน zsh เปล่า (status `null`) ก็รันเป็นคำสั่ง หลัง `/exit` ภายใน 1 วินาที `foreground.argv` กลับเป็น zsh และ `status` เป็น `null`
9. บรรทัด `claude --name X "$(cat F)"` ที่ส่งด้วยวิธีนี้ เปิด Claude ขึ้นมาโดยมีข้อความแรกตรงตามไฟล์ (ภาษาไทย, `"`, `$HOME`)
10. ส่ง `REQUEST` ตัวจริง (1,743 byte) ผ่าน `hc send` แล้ว `answer_state` เดิมอ่านได้ `handoff`
11. `hc send` ไม่มี `--if done` (`--if idle` ปฏิเสธเมื่อสถานะเป็น `done` ซึ่งเป็นสถานะหลังจบ turn) จึงเช็กสถานะเอง ส่วน `hc send` ปฏิเสธเองเมื่อ `blocked` (exit 9)
12. `hc run --bg --no-parent --name N --cwd D` ไม่ใส่คำสั่ง จะได้ login shell ไม่มี label ของแอป
13. session จริงของกิตที่เปิดจากแอป (สามตัวตอน probe) เป็น terminal ที่ program คือ `/bin/zsh -l` และ Claude เป็นลูกของ shell นั้น จึงไม่โดนข้อ "no shell to relaunch in"

## Design

### 1. ตัวอ่านหน้าจอ `scripts/hc-screen.pl` (ใหม่)

`perl hc-screen.pl <terminal>` พิมพ์หน้าจอปัจจุบันของ terminal แบบมี escape code ลง stdout แถวละบรรทัด (ตัด `\r` ออก) exit 0 ถ้าล้มเหลวไม่พิมพ์อะไรแล้ว exit 1

1. เปิด `env -u HC_TERMINAL_ID $HC_BIN connect` (`HC_BIN` = `KIT_UPDATE_HC_BIN`, default `hc`) ส่ง `hello` แบบ framed
2. channel 0: `terminal.get` เอา `cols`, `rows` แล้ว `terminal.attach` ด้วย `observe: true` ขนาดนั้น
3. ต่อ DATA frame บน channel นั้นเข้าด้วยกันจนเจอ `\e[?9001h` หรือ `\e[?9001l` ตัวแรก หน้าจอคือ byte หลัง `0x18` ตัวแรกจนถึงก่อน `\e[?9001` ส่วนที่ตามมาทิ้ง frame ชนิดอื่นบน channel นั้นข้าม ส่ง CREDIT ตามที่อ่าน (เริ่มที่ 256 KiB จึงแทบไม่ต้องใช้) แล้วส่ง CLOSE และปิด
4. หมดเวลารวม 5 วินาทีก่อนเจอจุดจบ, ได้ error จาก JSON-RPC, CLOSE จาก core หรือ header ของ frame ผิดรูป (len เกิน 16 MiB) = ล้มเหลว ห้ามพิมพ์หน้าจอที่ยังไม่ครบ

ทำเป็น perl **(Claude เลือก)** เพราะ bash ทำ pipe สองทางที่อ่าน binary ไม่ได้ ส่วน perl มากับ macOS และ Linux ทั่วไป ไม่ต้องลงอะไรเพิ่ม

`pane-lib.sh`: `esc()` ต้องตัด escape แบบสองตัวอักษร (`\eH`, `\e(B`, `\e=` …) ด้วย ไม่งั้นชุด reset ที่ติดแถวแรกจะเหลือตัวอักษรค้าง (`HHH…`) ฝั่ง tmux ไม่มี sequence พวกนี้ ผลจึงไม่เปลี่ยน

### 2. reload (`reload-all.sh`)

ส่วน herdr แทนด้วย herdr-core:

1. `hc ls --json` ได้ = มี server เลือก `agent == "claude-code"`, `state == "live"`, address ไม่มี `/`
2. ชื่อที่แสดง: `"<name หรือ where หรือชื่อโฟลเดอร์ของ cwd> (hc <address>)"`
3. ข้าม terminal ของตัวเอง (`address == $HC_TERMINAL_ID`)
4. `status` เป็น `working` = busy, `blocked` = waiting on a question, นอกนั้น (`idle`, `done`, `error`, ไม่มีสถานะ) ไปต่อที่หน้าจอ **(Claude เลือก)**: `error` คือจบ turn ด้วย error (เช่นติด rate limit) และ Claude ที่ไม่รายงานสถานะเลยก็ยังเช็กได้ด้วยหน้าจอแบบ tmux ซึ่งแยก busy / question / draft เองอยู่แล้ว
5. หน้าจอจาก `hc-screen.pl` → `screen_tail` → `screen_state` ตัดสินแบบเดียวกับ tmux อ่านไม่ได้ = ข้ามพร้อมเหตุผล "screen unreadable"
6. `env -u HC_TERMINAL_ID hc send <t> /reload-plugins` ถ้าล้มเหลวให้ข้ามพร้อมเหตุผล "hc send failed"

### 3. restart: snapshot (`restart-all.sh`)

ส่วน herdr แทนด้วย herdr-core เลือก terminal แบบเดียวกับ reload ข้อ 1 แล้วแต่ละตัว:

1. `hc get <t> --json` ได้ Claude pid = `foreground.pid` และ shell pid = `pid` ถ้า `foreground` เป็น `null` หรือ pid นั้นไม่ใช่ Claude ที่มี session file (`is_claude`) ให้ข้าม
2. ถ้า Claude คือ program ของ terminal เอง (`foreground.pid == pid`) ให้ข้ามด้วยเหตุผล "no shell to relaunch in"
3. ถ้ามี tmux อยู่เหนือ Claude ทำแบบเดิม (tmux_above / SEEN)
4. parent ของ Claude ต้องเป็น shell pid และ `shell_ok` ผ่าน ไม่งั้นข้ามแบบเดิม
5. `add hc <address> <where> …` label ใช้ `where` ถ้าไม่มีใช้ชื่อโฟลเดอร์ของ cwd

worker เปิดใน herdr-core เมื่อ `HC_TERMINAL_ID` มีค่า หรือไม่ได้อยู่ใน tmux แต่มี herdr-core server ไม่งั้นเปิดใน tmux (ลำดับเดิม แค่แทน herdr ด้วย hc)

```
env -u HC_TERMINAL_ID hc run --bg --no-parent --name kit-update-restart-<HHMMSS> --cwd <KU_DIR> -- env PATH=<PATH> LANG=<LANG> bash <restart-worker.sh> <state>
```

- program ที่ `hc run` เปิดได้ environment ของ core ไม่ใช่ของคนสั่ง จึงต้องส่ง `PATH` (หา `claude`, `jq`, `hc`, `perl`) และ `LANG`/`LC_*` ที่มีค่าตามไปเอง **(Claude เลือก)** ส่วน `CLAUDE_CONFIG_DIR` ไปทาง state อยู่แล้ว
- เพดาน 1024 byte ของบรรทัดคำสั่ง worker เป็นของ tmux `send-keys` ใช้เฉพาะฝั่ง tmux

- รัน worker เป็น program ของ terminal ตรง ๆ **(Claude เลือก)** ไม่ได้พิมพ์เข้า shell เพราะ `hc send` เข้า shell ที่เพิ่งเปิดอาจหล่น ("a send to a booting agent can be dropped") เมื่อ worker จบ terminal จะเป็น `finished` แต่ยัง `hc read` ได้จนกว่าจะ `hc rm`
- ชื่อซ้ำกับ terminal ที่ยังอยู่ ให้เติม `-2` … `-9` แบบที่ฝั่ง tmux ทำ
- `Worker:` ในรายงานบอกชื่อนี้ พร้อมวิธีดู (`hc attach <ชื่อ>`) และวิธีหยุด (Ctrl-C ใน attach หรือ `hc kill <ชื่อ>`) **(Claude เลือก)** ไม่ใส่ label ของแอปเพื่อให้ขึ้นเป็น tab เพราะแอปไม่ได้บอกรูปแบบ label ไว้ ถ้าตอนเช็กพบว่า worker ไม่ขึ้นในแอป ก็ใช้ `hc attach` อย่างเดียว
- ค่า `mux` ใน state เป็น `tmux` หรือ `hc` และ pane ของ worker ใน owner file ใช้ `$HC_TERMINAL_ID`

### 4. restart: worker (`restart-worker.sh`)

ลำดับขั้นทั้งหมดเหมือนเดิม เปลี่ยนเฉพาะจุดที่ herdr ถูกเรียก:

| จุด | herdr TUI (เดิม) | herdr-core |
|---|---|---|
| `identity_ok`: terminal ยังอยู่ | `agent list` มี pane | `hc get <t> --json` ได้ `state == "live"` ถ้าได้ not_found (exit 3) หรือ `finished` = gone ถ้า error อื่น = รอ ("herdr-core does not answer") |
| `pane_sendable`: สถานะ | `agent_status` | `status.state` ของ `hc get` ใช้ map เดียวกับ reload ข้อ 4 |
| `pane_sendable`: หน้าจอ | `agent read` + `prompt_empty` | `hc-screen.pl` + `screen_state` (busy / question / draft) แบบ tmux |
| `not_scrolled` | scroll offset | ผ่านเสมอ |
| คำขอ handoff, `/exit`, บรรทัดเปิดใหม่ | `agent prompt` / `pane run` | `env -u HC_TERMINAL_ID hc send <t> <text>` ผ่าน `run_detached` |
| `relaunch`: terminal ปิดไปแล้ว | `pane list` ไม่มี pane | `hc get` ได้ not_found หรือ `finished` |
| `confirm` | `agent rename` | ตัดออก |

`shell_ready` (`proc_foreground` ของ shell pid), `new_claude` และการเช็ก pid / start / tty ด้วย `ps` ยังเหมือนเดิม

### 5. test

- fake `hc` แทน fake `herdr` ใน `reload-all.test.sh` และ `restart-all.test.sh` (`KIT_UPDATE_HC_BIN`) โดยตอบ `ls`, `get`, `send`, `run` และบันทึกสิ่งที่ถูกส่ง
- หน้าจอใน test ของสองไฟล์นี้มาจาก `KIT_UPDATE_SCREEN_BIN` (fake ของ `hc-screen.pl`) ไม่ต้องจำลอง frame
- `hc-screen.test.sh` ใหม่: fake `hc connect` ที่ตอบเป็น frame แล้วเช็กว่า (1) ได้หน้าจอที่ตัด `\r` แล้ว (2) ส่ง `observe: true` และขนาดจาก `terminal.get` (3) error, frame ผิดรูป และค้างเกิน 5 วินาทีต้อง exit 1 โดยไม่มี stdout
- test ทุกตัวที่เคยครอบคลุมเส้นทาง herdr ต้องมีตัวคู่ที่ครอบคลุมเส้นทาง hc ส่วน test ที่เฉพาะ herdr (rename, scroll, workspace label) ให้ลบ

### 6. เอกสารและเวอร์ชัน

- `plugin.json`: `0.3.0` และ description เปลี่ยน "herdr" เป็น "herdr-core"
- `.claude-plugin/marketplace.json`: description ของ kit-update แบบเดียวกัน
- `commands/reload.md`, `commands/restart.md`: "tmux or herdr" เป็น "tmux or herdr-core" และ "pane" เป็น "pane or terminal" ตามความเหมาะสม
- README ส่วน kit-update: แทน herdr ด้วย herdr-core (แอป Herdr), ลบบรรทัด `herdr integration install claude`, เพิ่มว่าต้องมี `perl`, Claude ต้องรันจาก bash/zsh ใน terminal (แบบ tab ของแอป Herdr) และวิธีดู/หยุด worker
- README หัวข้อ "ใช้ Claude Code ผ่าน tmux หรือ herdr" และ `guides/tmux-remote-control.md`: ลบส่วน herdr TUI (ข้อ 7, ตารางคีย์, ฟังก์ชัน `_herdr_claude`) เหลือบรรทัดเดียวว่า reload/restart ใช้กับแอป Herdr (herdr-core) ได้ด้วย
- `CLAUDE.md` ของ repo: บรรทัดคำสั่ง test (fake hc, `hc-screen.test.sh`)
- เว็บ: หน้า Tools บรรทัดที่พูดถึง "tmux หรือ herdr" เป็น PR แยกตาม checklist ใน `phimee-and-kit-website/CLAUDE.md`

## ทางที่พิจารณาแล้วไม่เลือก

- **ถือว่ามีข้อความในช่องพิมพ์ = พิมพ์ค้าง (อ่านด้วย `hc read`)**: โค้ดน้อยกว่า แต่ session ที่ขึ้นคำแนะนำจะถูกข้ามทุกครั้ง กิตไม่เอาเพราะห่วงคนที่เปิดคำแนะนำไว้
- **เก็บ herdr TUI ไว้คู่กับ herdr-core**: กิตเลือกตัดออก
- **ตัวอ่านหน้าจอเป็น python หรือ Go**: python ไม่ได้มากับ macOS ทุกเครื่อง ส่วน Go ต้อง build และแจก binary
- **ต่อ socket ของ herdr-core ตรง ๆ**: path ของ socket ต่างกันตาม OS และการตั้งค่า ส่วน `hc connect` จัดการให้แล้ว
- **เปิด worker เป็น shell แล้ว `hc send` คำสั่งเข้าไป** (แบบที่ herdr ทำ): เสี่ยงที่ข้อความจะหล่นตอน shell ยังบูตไม่เสร็จ

## ให้ builder ตัดสินใจเอง

- โครงของ `hc-screen.pl` และจะเก็บ JSON-RPC id/ลำดับคำตอบยังไง (channel 0 อาจมีหลายคำตอบ)
- จะรวมการเรียก `hc get` ต่อรอบของ worker ให้เหลือครั้งเดียวต่อ terminal หรือไม่
- จะลบคอลัมน์ AGENT_NAME ใน state หรือปล่อยว่าง
- ถ้อยคำใน log, เหตุผลที่ข้าม และเอกสาร

## ต้องเช็คระหว่างทำ

- คำแนะนำตัวจางจาก Claude Code จริง (ไม่ใช่ข้อความจางที่สร้างเอง) มาเป็น `\e[2m` ในหน้าจอแรก ตอน probe ยังไม่มีคำแนะนำขึ้นเลย
- worker ที่เปิดด้วย `hc run --bg --no-parent` ขึ้นในแอป Herdr ไหม และ Ctrl-C ผ่าน `hc attach` กับ `hc kill` ส่ง signal อะไรให้ worker (trap INT/TERM/HUP ต้องทำงาน)
- worker รอดหลัง Claude ที่สั่งออก (ไม่มี parent)
- `hc send` ไม่ติดค้างนานตอนมีคนพิมพ์อยู่ใน terminal นั้น ("waits for a person to pause") และ `run_detached` ไม่ค้าง worker
- end-to-end กับ terminal ทดลองที่เปิดเองอย่างน้อยสองตัว + worker จริง ก่อนจะลองกับ session จริงของกิต (ต้องให้กิตสั่ง)

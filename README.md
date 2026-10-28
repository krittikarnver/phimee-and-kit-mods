# phimee-and-kit-mods

Claude Code mods ที่พี่หมีกับกิตทำด้วยกัน ทำขึ้นจากปัญหาที่เจอจริงตอนใช้ Claude ทุกวัน

## ติดตั้ง

พิมพ์ใน Claude Code (terminal):

```
/plugin marketplace add krittikarnver/phimee-and-kit-mods
/plugin install kit-time@phimee-and-kit-mods
/plugin install kit-usage@phimee-and-kit-mods
/plugin install kit-scrutinize@phimee-and-kit-mods
/plugin install kit-update@phimee-and-kit-mods
/plugin install kit-checkpoint@phimee-and-kit-mods
```

เลือกติดตั้งเฉพาะตัวที่อยากใช้ก็ได้ แต่ละตัวทำงานแยกกัน

## Mods

### kit-time

ให้ Claude รู้ว่าตอนนี้วันอะไร กี่โมงตามเวลาไทย และห่างจากข้อความก่อนหน้านานแค่ไหน เกิดจากที่คุยกันอยู่ดีๆ แล้ว Claude ไม่รู้ว่าผ่านไปข้ามคืนแล้ว

- ทุกครั้งที่ส่งข้อความ แนบเวลาไทย (พ.ศ./ค.ศ.) และระยะห่างจากข้อความก่อนหน้าไปให้ Claude แบบที่คนไม่เห็น
- แถบเหนือช่องพิมพ์: `🕰 ข้อความล่าสุด 18:24 · 5 นาทีที่แล้ว · ตอนนี้ 18:29`

### kit-usage

ให้ Claude รู้ว่า context ของ session ใช้ไปเท่าไหร่ และ rate limit ถึงไหนแล้ว พอใกล้โดน compact ก็เตือนให้จดเรื่องสำคัญไว้ก่อน จะได้ไม่ลืมกลางทาง

- ทุกครั้งที่ส่งข้อความ แนบให้ Claude ว่า context ใช้ไปกี่ % และ rate limit (5 ชม. / 7 วัน) ถึงไหนแล้ว พร้อมเวลารีเซ็ต (เวลาไทย)
- ถ้า context เกิน 85% บอก Claude ให้เตือนก่อนโดน compact และเด้ง toast เตือนหนึ่งครั้ง
- แถบเหนือช่องพิมพ์: `📊 context 72% (144k/200k) · 5 ชม. 41% รีเซ็ต 15:00`

### kit-scrutinize

คำสั่งเดียวแทน prompt ยาวที่ต้องพิมพ์ทุกครั้งหลังเขียน spec หรือ plan

- `/scrutinize-loop <ไฟล์ spec หรือ plan>` รีวิวด้วย subagent `scrutinizer` แล้วแก้ไฟล์ตาม feedback ทันที
- ทำอย่างน้อย 3 รอบ ถ้ารอบล่าสุดยังมี blocker หรือ major ทำต่อทีละรอบจนไม่เหลือ ทางแก้ของรอบสุดท้ายจะได้ถูกตรวจด้วย (หยุดที่รอบ 8 แล้วถามผู้ใช้)
- เปิด subagent ใหม่ทุกรอบ รอบแรกรีวิวเต็ม รอบต่อไปข้ามข้อ "มีทางที่ง่ายกว่านี้ไหม"
- ถ้า verdict เป็น `rework` หรือ `reject` หยุดแล้วถามผู้ใช้ก่อน ไม่ออกแบบใหม่เอง
- subagent อ่านไฟล์ได้อย่างเดียว แก้ไฟล์ไม่ได้
- จบแล้วสรุปไฟล์ให้อ่านต่อด้วย `/kit-scrutinize:explain`

`/kit-scrutinize:explain [ไฟล์ spec หรือ plan]` สรุป spec หรือ plan ที่ยาวจนอ่านแล้วเออออไปหมด ให้จบในหน้าจอเดียว อ่านอย่างเดียว ไม่แก้ไฟล์ ไม่ใส่ไฟล์ก็ได้ จะใช้ไฟล์ที่เพิ่งเขียนในแชทนั้น

- เล่าว่าไฟล์นี้ทำอะไร ทำไปเพื่ออะไร มีขั้นไหนบ้าง
- เทียบสิ่งที่ผู้ใช้ตัดสินใจไว้กับไฟล์: ตรง / ตรงแต่มีเงื่อนไข / ไม่ตรง / ไม่มีในไฟล์ นับเฉพาะที่ผู้ใช้พิมพ์เองใน transcript ของ Claude Code (`~/.claude/projects/`) ไม่เชื่อที่ spec หรือ handoff เขียนว่าผู้ใช้เลือก เพราะนั่นคือ Claude ตรวจงานตัวเอง ถ้า transcript ถูกลบไปแล้วตาม `cleanupPeriodDays` จะใช้ handoff ของ kit-checkpoint แทนและบอกไว้
- ยกเรื่องที่ Claude เลือกเองมาไม่เกิน 4 ข้อ เอาข้อที่เปลี่ยนสิ่งที่ผู้ใช้จะเห็นหรือได้ใช้ ข้อที่เหลือขอดูต่อได้
- ต้องมี `jq`

ตัวรีวิวใช้ [scrutinize skill ของ 9arm](https://github.com/thananon/9arm-skills/tree/main/skills/engineering/scrutinize) ติดตั้ง kit-scrutinize แล้ว plugin `9arm-skills` จะถูกติดตั้งให้อัตโนมัติ ดึงจาก [repo ของ 9arm](https://github.com/thananon/9arm-skills) ตรงๆ และอัปเดตตามต้นฉบับ ขอบคุณที่แบ่งปันครับ

### kit-update

`claude plugin update` อัปเดตได้ทีละตัว ไม่มี `--all` ตัวนี้เลยทำให้จบในคำสั่งเดียว

- `/kit-update:check` dry-run ดูก่อนว่าจะไล่เช็คตัวไหนบ้าง ไม่แตะอะไร (ยังบอกไม่ได้ว่าตัวไหนมี version ใหม่ ต้องรัน `/kit-update:all` ถึงจะรู้)
- `/kit-update:all` refresh marketplace ทั้งหมด → อัปเดตทุก install ตาม scope ของมัน → สรุปว่าตัวไหนเปลี่ยนจาก version ไหนเป็นอะไร (diff จาก `plugin list --json` ก่อน-หลัง ไม่ได้เชื่อแค่ว่าคำสั่งตอบ ok)
- `/kit-update:check-all-projects` และ `/kit-update:all-projects` ทำเหมือนกัน แต่รวม install ระดับ project/local ของ project อื่นด้วย (สองตัวแรกทำเฉพาะของ project ปัจจุบัน)
- เสร็จแล้วพิมพ์ `/reload-plugins` เอง Claude สั่งแทนไม่ได้
- `/kit-update:reload` พิมพ์ `/reload-plugins` ให้ทุก Claude session อื่นที่รันใน tmux หรือ [herdr](https://herdr.dev) และว่างอยู่ ข้าม session ที่กำลังทำงาน มีคำถามค้าง หรือพิมพ์ค้างไว้ (tmux อ่านจากหน้าจอทั้งหมด herdr ใช้สถานะที่ herdr รู้ แล้วอ่านหน้าจอแค่ช่องพิมพ์ ไม่แน่ใจก็ข้าม) session ที่สั่งต้องพิมพ์เอง ไม่ได้ใช้ tmux หรือ herdr ก็ทำอะไรไม่ได้
- `/kit-update:restart` ปิดแล้วเปิด Claude session ทุกตัวที่รันใน tmux หรือ herdr ใหม่ รวม session ที่สั่งด้วย (เช่นหลังอัปเดต Claude Code) โดยพก handoff ไปเป็นข้อความแรก
  - สคริปต์ถ่าย snapshot ของ session ที่มีตอนนั้น (ตัวที่เปิดทีหลังไม่นับ) แล้วเปิด worker ใน pane ของมันเอง (herdr: workspace ใหม่ / tmux: session `kit-update-restart-<เวลา>`) ที่เช็กทุก 10 วินาที
  - session ไหนว่าง worker จะพิมพ์คำขอ handoff ให้ Claude ตอบในแชท (ไม่เขียนไฟล์ ไม่เรียก tool) เก็บคำตอบลง `~/.claude/kit-update/handoffs/` แล้วพิมพ์ `/exit` และเปิด `claude --name <ชื่อเดิม> "<handoff>"` ใหม่ใน pane เดิม session นี้ไปหลังตัวอื่น
  - ทุก session ต้องส่ง context ทั้งก้อนเพื่อเขียน handoff จึงใช้ token (ขอพร้อมกันไม่เกิน 2 session)
  - log อยู่ที่ `~/.claude/kit-update/restart.log` และมี `Summary` ปิดท้ายทั้งใน log และใน pane ของ worker pane นั้นไม่ปิดเอง ต้องปิดเอง
  - หยุดได้ด้วย Ctrl-C ใน pane ของ worker (หรือปิด pane นั้น) session ที่ได้รับ `/exit` ไปแล้วจะถูกเปิดใหม่ให้จบ ที่เหลือไม่ถูกแตะ
  - session ที่ทำงานอยู่ มีคำถามค้าง พิมพ์ค้างไว้ scroll ค้าง หรืออยู่ใน copy mode จะรอจนพร้อม และถูกข้ามถ้าครบ 4 ชั่วโมงแล้วยังไม่พร้อม การตรวจ subagent, teammate, `/loop` และคำถามที่ยังไม่ได้ตอบเป็น best effort ไม่การันตี
  - session ที่มี process เบื้องหลังรันตลอด (dev server, watcher) จะไม่ถูก restart และถูกข้ามหลัง 4 ชั่วโมง
  - session ที่ตอบว่า `NOT-READY` หรือไม่ได้ handoff ที่ใช้ได้ จะไม่ถูกปิด
  - flag ที่ใช้ตอนเปิด session เดิม (เช่น `--model`, `--dangerously-skip-permissions`) ไม่ตามไปด้วย log มีคำสั่งเดิมไว้ให้ ถ้า session เปิดไม่ขึ้น log มีบรรทัด `relaunch it yourself: <คำสั่ง>`
  - shell ใน pane ต้องเป็น bash หรือ zsh (คำสั่งเปิดใหม่ใช้ quoting ของสองตัวนี้)
  - Claude ใน herdr ต้องรันด้วย config ที่มี hook จาก `herdr integration install claude` (ลงไว้ใน `~/.claude/settings.json`) ไม่งั้น herdr ไม่รู้ session id และ session นั้นถูกข้ามด้วยเหตุผล `herdr shows no session id` เช่น Claude ที่เปิดด้วย `CLAUDE_CONFIG_DIR` อื่น
  - ถ้าสคริปต์บอกว่าไม่เจอ session ที่สั่ง หรือไม่มี tmux/herdr server ต้องปิดเปิดเอง
- command ทั้งหกไม่รับ argument ข้อความที่พิมพ์ต่อท้ายไม่ถูกใส่ลงในคำสั่ง shell และ Claude ถูกสั่งให้ไม่ทำตาม ถ้าต้องใช้ flag อื่น (`--only '<regex>'`, `--scope user,project`, `--no-marketplaces`, `-y`) ให้รัน script ตรงจาก terminal
- install ของ project ที่ไม่มีโฟลเดอร์แล้วจะถูกข้ามพร้อมบอกเหตุผล
- ข้าม plugin ที่ไม่ได้มาจาก marketplace (`@synced`, `@inline`, `@skills-dir`) แล้วบอกรายชื่อไว้ท้ายสรุป
  - `@synced` คือ plugin ที่ sync มาจาก claude.ai (เช่นใน cloud session) ตัวพวกนี้อัปเดตผ่าน claude.ai ไม่ใช่ที่นี่
  - ถ้าใช้ kit-scrutinize แบบ sync ต้อง sync `9arm-skills` ไปด้วย ไม่งั้น kit-scrutinize จะถูกปิดเพราะหา dependency ไม่เจอ
- ถ้า plugin ที่ใช้ command source เปลี่ยน install command, Claude Code ไม่ให้ accept จากใน session จะได้คำสั่ง `--accept-command <sha256>` ไว้ review แล้วรันเองใน terminal

ต้องใช้ Claude Code v2.1.268 ขึ้นไป (`/kit-update:restart` ต้องใช้ v2.1.308 ขึ้นไป เพราะอ่าน `status` และ `procStart` จาก session file ของ Claude Code) และต้องมี `jq` รันจาก terminal ตรงๆ ก็ได้: `bash plugins/kit-update/scripts/update-all.sh --help` (`/kit-update:reload` คือ `scripts/reload-all.sh`, `/kit-update:restart` คือ `scripts/restart-all.sh`)

### kit-checkpoint

limit หมดเร็วเพราะขนาดของ context ไม่ใช่ output ทุกข้อความต้องส่ง context ทั้งก้อนไปใหม่ ตัวนี้ทำแทนสิ่งที่เคยทำมือ คือ copy handoff → `/clear` → paste แล้วทำงานต่อใน session เดิมที่ context เหลือนิดเดียว ไม่ต้องคอยดู statusline

- context ของ session หลักเกิน **400K**: บอก Claude ว่าใช้ไปเท่าไหร่ เหลือเท่าไหร่ก่อนถึง 500K และโตเร็วแค่ไหน ให้หาจุดหยุดที่ checkpoint ถัดไป (เตือนซ้ำทุก +25K)
- เกิน **500K**: บอกให้หยุดทันทีที่หยุดได้อย่างปลอดภัย
- พิมพ์ `/kit-checkpoint` เพื่อสั่งเองได้ทุกเมื่อ ไม่ต้องรอ 400K: mod ส่งข้อความให้ Claude เรียก `handoff` แล้วที่เหลือเหมือนตอน context เกิน ถ้าพิมพ์ตอน Claude ทำงานอยู่ คำสั่งจะรอจนจบ turn ก่อน กันชนข้ออื่นด้านล่างยังอยู่ครบ
- ไม่ขวาง tool call ใดๆ แค่เตือน
- Claude เรียก tool `handoff` → mod เขียนไฟล์ลง `.git/kit-handoff/` (ไม่ถูก commit ไม่เขียนทับไฟล์เดิม) → พอจบ turn ก็ `/clear` → ส่ง handoff เป็นข้อความแรกของบทสนทนาใหม่
- ไม่ส่ง notification เอง ข้อความแรกหลัง clear ขึ้นในแชท ตอนต้องรอผู้ใช้ Claude จะจบ turn แล้วแอป Claude (Remote Control) หรือ Claude Code แจ้งเตือนตามปกติ
- ถ้ามีข้อความ, Esc, tool call หรือ subagent เข้ามาหลังเขียน handoff จะยกเลิก clear อัตโนมัติ ถ้าเขียนไฟล์ไม่ได้ (เช่นไม่ใช่ git repo) จะไม่ clear
- ทำต่อเองได้เมื่อ Claude บอกว่าขั้นต่อไปชัดแล้ว, ยังทำต่อเองไม่ถึง 5 รอบติดกันหลังข้อความล่าสุดของผู้ใช้หรือ `/clear` ที่ผู้ใช้พิมพ์เอง (รอบที่ 6 จะรอผู้ใช้ ตอบอะไรก็ได้ เช่นจากมือถือ ก็เริ่มนับใหม่), และมีตัวเลข limit 5 ชม. < 90% กับ 7 วัน < 85% ไม่ผ่านข้อไหนก็ยัง clear แต่รอผู้ใช้
- ใช้กับ model ที่มี context window 1M (window 200K ไม่มีวันถึงเกณฑ์ จึงไม่เตือนเอง แต่ `/kit-checkpoint` ยังใช้ได้) เกณฑ์ทั้งหมดตั้งค่าไม่ได้
- ใน worktree ไฟล์อยู่ใต้ `.git/worktrees/<ชื่อ>/kit-handoff/` จึงหายไปพร้อม `git worktree remove`
- Workflow, Bash background และ Monitor ยังทำงานต่อหลัง `/clear` ผลหรือ event ของพวกนี้จะเข้ามาในบทสนทนาใหม่ Claude จะรายงานให้รู้แต่ไม่ลงมือทำตาม ถ้า event เข้ามาหลังเขียน handoff แล้วจะยกเลิก clear และ Claude จะเรียก handoff ใหม่
- agent ที่ตั้งชื่อไว้และรอข้อความอยู่ (idle) จะถูกปิดตอน `/clear` และส่ง SendMessage หาไม่ได้อีก

## ใช้ Claude Code ผ่าน tmux หรือ herdr + Remote Control

ให้ Claude ของแต่ละ repo รันค้างใน tmux หรือ herdr แล้วคุยต่อจากมือถือหรือ Claude desktop ได้ ดูขั้นตอนตั้งค่า (`settings.json`, `~/.tmux.conf` หรือ herdr, `~/.zshrc`, ssh ผ่าน Tailscale) ที่ [guides/tmux-remote-control.md](guides/tmux-remote-control.md) เป็นคำแนะนำ ไม่มี script ติดตั้งให้

## พัฒนา

```
claude --plugin-dir ./plugins/kit-time
claude plugin validate ./plugins/kit-time
claude plugin test ./plugins/kit-time
```

## License

[MIT](LICENSE) ยกเว้น 9arm-skills ซึ่งไม่ได้อยู่ใน repo นี้ เป็นของเจ้าของ repo ต้นฉบับ

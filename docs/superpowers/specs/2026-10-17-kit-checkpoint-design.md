# kit-checkpoint: design

> 17 ต.ค. 2569 · ที่มา: `docs/kit-checkpoint-handoff.md` + คุยกับกิตใน session นี้ + spike 4 ตัว
> ข้อที่เขียนว่า **(Claude เลือก)** เป็นการตัดสินใจของ Claude ไม่ใช่ของกิต เปลี่ยนได้

## เจตนา

ตัวที่ทำให้ limit หมดเร็วคือ**ขนาดของ context** ไม่ใช่ output (cache read กินไป 97.6% ของ token ทั้งหมด) เพราะทุกข้อความต้องส่ง context ทั้งก้อนไปใหม่ ถ้า session หลักไม่โตเกิน ~500K แต่ละข้อความก็ถูกลง

โจทย์คือให้ **Claude รู้ตัวเองว่า context ใกล้เต็ม** แล้วหยุดที่จุดที่หยุดได้โดยงานไม่พัง เขียน handoff แล้วให้ mod ทำแทนกิตในสิ่งที่กิตทำมือทุกวันนี้: **copy handoff → `/clear` → paste** แล้วทำงานต่อใน session เดิมที่ context เหลือนิดเดียว ไม่ต้องให้กิตคอยดู statusline (บนมือถือใช้ไม่ได้) และไม่ต้องรอกิตกลับมาหน้าคอม

## เป้าหมาย

- session หลักเกิน **400K** (soft): Claude ทำงานชิ้นปัจจุบันต่อได้ แต่ต้องหาจุดหยุดที่ checkpoint ถัดไป
- session หลักเกิน **500K** (hard): หยุดทันทีที่หยุดได้อย่างปลอดภัย
- ให้ข้อมูลพอให้ Claude **ประเมินล่วงหน้าเอง** ว่างานชิ้นถัดไปจะทำทันหรือเปล่า: ใช้ไปแล้วเท่าไหร่ เหลืออีกเท่าไหร่กว่าจะถึง 500K และ burn rate
- ตอนหยุด: Claude เรียก tool `handoff` แล้ว mod จะเขียนไฟล์ลง `.git` → พอจบ turn ก็ `/clear` → ส่ง handoff เป็นข้อความแรกของบทสนทนาใหม่ ถ้าผ่านกันชนก็ทำต่อเอง ถ้าไม่ผ่านก็รอผู้ใช้
- แจ้งผู้ใช้ทุกครั้งที่ handoff เกิดขึ้น

## ไม่ทำ (v1)

- spawn session ใหม่ใน Orca (ยกเลิกไปแล้ว เปลี่ยนมาใช้ clear + paste ดู "ทางที่พิจารณาแล้วไม่เลือก")
- โหลด handoff อัตโนมัติตอนเปิด session ใหม่ (clear + paste ส่ง handoff ให้ตรง ๆ อยู่แล้ว ไฟล์ใน `.git` เก็บไว้เป็นบันทึก)
- handoff ตามสั่งตอน context ยังไม่ถึง 400K (tool จะปฏิเสธ ดูข้อ 3)
- เรื่อง limit ที่ไม่เกี่ยวกับกันชน เช่น หยุดตอน 5 ชม. เกิน 90% โดยไม่เขียน handoff หรือเสนอ task ให้ Sonnet ตอน 7 วันเกิน 85%
- route model ที่ขอบ subagent
- ทำให้ตั้งค่าได้: เกณฑ์ทุกตัวเป็นค่าคงที่ในโค้ด (model ที่มี window 200K จะไม่มีวันถึงเกณฑ์ แต่ก็ไม่มีอะไรพัง ให้เขียนไว้ใน README)
- เกณฑ์ของ subagent: subagent มี context ของตัวเอง ไม่ต้องเฝ้า
- แก้ kit-usage: คำเตือน 85% ก่อน compact ยังอยู่เหมือนเดิม

## สิ่งที่ต้องไม่เกิดเด็ดขาด

- **ห้าม deny หรือขวาง tool call** เพราะถ้าตัดตอน Claude แก้ไฟล์อยู่ครึ่งทาง โค้ดจะพัง ให้เตือนอย่างเดียว
- **ห้าม `/clear` ทั้งที่ handoff ยังไม่ถูกเขียนลงไฟล์สำเร็จ** ไม่งั้นงานจะหายไปทั้งก้อน
- **ห้าม `/clear` ทับสิ่งที่เกิดขึ้นหลังเขียน handoff** ไม่ว่าจะเป็นข้อความของผู้ใช้, Esc, ผลจาก subagent หรือ tool call อื่น ถ้ามีอะไรเกิดขึ้น handoff นั้นถือว่าเก่าแล้ว ให้ยกเลิก clear อัตโนมัติ (ข้อ 3)
- ห้ามไฟล์ handoff ถูก commit (เลยเก็บไว้ใน git-dir) และห้ามลบหรือเขียนทับไฟล์ handoff
- ห้าม clear แล้วทำต่อเองวนไม่รู้จบ และ**ถ้าไม่แน่ใจต้องไม่ทำต่อเอง** (ถ้ากันชนขาดข้อมูลหรือ error ให้ถือว่า "รอผู้ใช้")
- ห้าม `/clear` ตอนที่ subagent ที่ `$.agent.list()` มองเห็นยังทำงานอยู่ (agent ของ Workflow, Bash background และ Monitor มองไม่เห็น ให้เขียนไว้ใน README และในข้อความเริ่มต้น ดูข้อ 5)

## ข้อจำกัดและข้อเท็จจริงที่ยืนยันแล้ว

สภาพแวดล้อมของกิต: dev บน Orca ADE ต่อจากมือถือ ใช้ Superpowers แบบ subagent-driven (Claude รัน tool ต่อกันยาว ๆ ได้โดยไม่มีข้อความจากกิตคั่น) ใช้ git worktree บ่อย บัญชีเป็น **Team plan** (`claude auth status`: `subscriptionType: "team"`) และกิตตั้งใจส่ง mod นี้ต่อให้ทีมถ้าใช้ได้ดี ข้อความที่ส่งถึง model จึงต้องเรียก "ผู้ใช้" ไม่ใช่ "กิต"

**spike 1 (เฝ้า context)** Claude Code 2.1.302 ใน session หลัก + subagent background:
- `on('tool.call')` แล้ว `await next(e)` คืน `{ ...result, context: [...] }` ได้ ข้อความไปถึง Claude ทันทีหลังผลของ tool ระหว่าง turn
- `(await $.session.usage()).context.tokens` อัปเดตทุก model call ของ session หลัก (ช้ากว่าจริงหนึ่งจังหวะ คือผลของ tool ที่เพิ่งรันยังไม่ถูกนับ)
- tool call ของ subagent มี `e.agentId` และ `usage()` ตอนนั้นยังเป็นตัวเลขของ session หลัก subagent ไม่ทำให้ตัวเลขเพี้ยน context ของ session หลักโตตอนที่ subagent ส่งรายงานกลับมาและตอนที่ Opus รีวิว
- `session.measure` ยิงตอนจบ turn เท่านั้น ใช้เฝ้าระหว่าง turn ไม่ได้

**spike 2 (compact + ยัด handoff)** ไม่ผ่าน:
- hook `session.compact` ของ plugin ที่ผู้ใช้ติดตั้งเองไม่ถูกเรียกเลย ทั้งตอน plugin สั่ง compact เองและตอนคนพิมพ์ `/compact` สาเหตุคือ plugin `sec-default@builtin` ที่ถูกวางไว้ชั้นนอกสุดของทุกองค์กร Team/Enterprise จะข้าม hook นี้ของระดับ user (ตาม README ของ sec-default)
- compact ของ engine เองใช้ model สรุป (~12 วินาที) และ**อ่านไฟล์ที่เพิ่งเปิดกลับเข้ามาใหม่ทั้งไฟล์**

**spike 3 (clear + paste)** ผ่าน (รัน 2 รอบ ภายใต้ `sec-default` ของบัญชี Team):
- จาก timer: `await $.command.run({ command: 'clear' })` รอจนจบ turn แล้วค่อยรัน resolve ภายใน ~2.5 วินาที `startedAt` ถูกตั้งใหม่ (นับเป็นบทสนทนาใหม่)
- ต่อด้วย `await $.prompt.submit({ text, asUser: true })` เข้าคิวถัดไป เริ่ม turn ใหม่ทันที บนจอแสดงเป็น `/clear` → "Prompt from the <plugin> plugin" → ข้อความ handoff
- model ใน turn ใหม่เห็นแค่ handoff + ของที่ engine ใส่ให้ใหม่ตอนเริ่ม session (CLAUDE.md, git status, SessionStart hook ของ ponytail/superpowers, context ของ kit-time/kit-usage) ไม่เห็นบทสนทนาเก่าเลย
- `context.tokens` ของ response แรกหลัง clear อ่านได้ 21K ขณะที่ statusline แสดง 49K (ค่าเพี้ยนชั่วคราว ไม่ได้มีอะไรหายไป)
- `$.ui.notify(text, { title })` คืน `{ isSent: true, channel: "ghostty" }` และวิ่งผ่าน hook `Notification` ของ Claude Code ซึ่ง Orca ดักไว้อยู่ (ยังไม่ได้ยืนยันว่า push ไปถึงมือถือ)

**spike 4 (hook ที่ design พึ่ง ภายใต้ `sec-default`)** ผ่าน:
- `turn.start`, `turn.step` (generator), `turn.complete` ยิงครบ มี `turnId` ตรงกัน `turn.complete` ของ turn ปกติได้ `reason: 'answer'`, `isAborted: false`
- **hook ของ plugin ไม่เห็นคำสั่งของ plugin เอง**: hook `command.run` ไม่ยิงกับ `$.command.run({ command: 'clear' })` ของตัวเอง และ hook `prompt.submit` ไม่ยิงกับ `$.prompt.submit` ของตัวเอง `$.command.run` ไม่ทำให้เกิด `prompt.submit`
- `/clear` ที่สั่งจาก timer ระหว่าง turn รันประมาณ 0.1 วินาทีหลัง `turn.complete` แล้ว `session.end` (`reason: 'clear'`) ยิง session id **และ** `startedAt` เปลี่ยนทั้งคู่
- `$.process.run(['git', 'rev-parse', '--absolute-git-dir'])` และ `$.fs.write` ลงใต้ `.git/` ใช้ได้ (checkout หลัก)
- tool ที่ลงทะเบียนไว้ยังเรียกได้หลัง `/clear`
- Claude ทำตามข้อความเริ่มต้นแบบมีกรอบ (ไม่ใช้ `asUser`)

**ข้อเท็จจริงอื่นจาก API:**
- `$.command.run` และ `$.prompt.submit` จะเข้าคิว รอจน session ว่างก่อนค่อยรัน `$.command.run` จะ reject ถ้าเรียกใน hook ที่ turn กำลังรออยู่ เลยต้องเรียกจาก `$.clock.after`
- `CommandRunResult` ไม่มี field บอกว่าสำเร็จหรือไม่ ต้องเทียบ `$.session.id()` ก่อนและหลังเอง
- input ของ tool MCP อยู่บน `e` ตรง ๆ (`e.content`) ไม่ได้อยู่ใน `e.input`
- `prompt.submit` ของ plugin มี `origin.kind === 'plugin'` และ `origin.name` เป็นชื่อ plugin
- `next(e)` ของ `tool.call` อาจ resolve เป็น `{ deny }` ซึ่งแนบ `context` ไม่ได้
- `rateLimits` คือค่าที่ "API response ล่าสุดรายงานมา" และว่างได้ ส่วนสาเหตุที่ตัวเลข 5 ชม./7 วันใน kit-usage หายเป็นช่วง ๆ (คำถามข้อ 3 ใน handoff note) **ยังหาไม่เจอ** กันชนข้อ 4.3 จึงต้องทนต่อค่าที่ว่างได้
- `$.agent.list()` คืน subagent/teammate และ skill ที่ fork ออกไป พร้อม status (`pending|running|waiting|idle|completed|failed|killed`) แต่ไม่นับ fork ของ engine (compaction, memory) และไม่นับ agent ของ Workflow teammate ที่ `idle` อยู่ระหว่าง turn ไม่ถือว่ากำลังทำงาน
- `turn.complete` มี `isAborted` เมื่อผู้ใช้กด Esc
- `$.prompt.submit` อาจ resolve เป็น `{ drop }` แทนที่จะ reject, `$.command.run` reject ได้, `$.ui.notify` reject ได้

- `$.fs.write` เขียนทับไฟล์เดิมโดยไม่เตือน
- `session.start` ไม่ยิงใหม่หลัง `/clear`
- helper ที่รับ `$` ต้องประกาศไว้ระดับบนสุดของไฟล์ (`claude plugin validate` บังคับ)

## Design

### 1. เป็น plugin ใหม่ `kit-checkpoint` (Claude เลือก)

แยกจาก kit-usage เพราะ kit-usage แค่บอกตัวเลข แต่ตัวนี้ลงมือทำ คือเขียนไฟล์และสั่ง `/clear` hooks module ใช้โครงเดียวกับ kit-usage: `hooks/register.tsx` สำหรับ hook, logic ล้วน ๆ แยกไว้ไฟล์ที่ test import ได้, มี `types/index.d.ts` สำหรับ `$.state` เพิ่มลงใน `.claude-plugin/marketplace.json` และ README (บรรทัดติดตั้ง + section ภาษาไทย ระบุว่าใช้กับ model ที่มี window 1M) เริ่มที่ version 0.1.0 เป็น plugin ระดับ user ธรรมดา ไม่ต้องตั้ง managed settings

### 2. เฝ้าดู context

- เช็คใน `tool.call` เฉพาะ session หลัก (`e.agentId === undefined`) หลัง `next(e)` resolve แล้ว ใช้ `context.tokens` ของ `usage()` แนบคำเตือนเฉพาะเมื่อผลเป็น result (ไม่ใช่ `{ deny }`) **ยกเว้น call ของ tool `handoff` เอง** ใส่ `.catch` ที่คืน `next(e)` ไว้ด้วย ถ้าการอ่าน usage พัง ผลของ tool จะได้ไม่หายและ tool ไม่ถูกรันซ้ำ hook เดียวกันนี้เก็บ `rateLimits` ล่าสุดที่ไม่ว่างพร้อมเวลาไว้ใช้กับกันชน (ข้อ 4.3)
- เช็คใน `prompt.submit` ด้วย ใช้ logic และ state dedupe ชุดเดียวกัน
- **งดเตือนหลัง clear:** ตั้งแต่ตั้งสถานะ `committed` (ข้อ 3) หรือตั้งแต่เห็น `usage().startedAt` เปลี่ยน (ครอบคลุม `/clear` ที่ผู้ใช้พิมพ์เองด้วย) ห้ามเตือนจนกว่าจะได้ค่าที่ต่ำกว่า 400K หรือจนกว่า model จะตอบกลับมาหนึ่ง request ของ session หลัก (ตัวเลขหลังจากนั้นเป็นของบทสนทนาใหม่แล้ว กันกรณี `/resume` เข้าบทสนทนาใหญ่แล้ว mod เงียบไปตลอด) เพราะ `usage()` อาจยังเป็นตัวเลขก่อน clear อยู่ ถ้า clear ล้มเหลว ให้เลิกงดเตือน
- **dedupe**: เตือนครั้งแรกตอนข้าม 400K แล้วเตือนซ้ำทุก +25K จากครั้งที่เตือนล่าสุด ตอนข้าม 500K ต้องเตือนทันทีเสมอ ขยับจุดที่เตือนล่าสุดเฉพาะเมื่อแนบคำเตือนได้จริง (ถ้าผลเป็น `{ deny }` ให้รอแนบที่ครั้งถัดไป) ถ้าตัวเลขลดลงต่ำกว่า 400K (หลัง clear หรือ compact) ให้ล้าง state
- **ข้อความ soft** (ภาษาไทย ขึ้นต้นด้วย `[kit-checkpoint]`) มี: ใช้ไปแล้วกี่ token, เหลืออีกเท่าไหร่กว่าจะถึง 500K, burn rate, คำสั่ง "ทำชิ้นปัจจุบันต่อได้ ประเมินว่างานชิ้นถัดไปจะทำทันก่อน 500K ไหม ถ้าไม่ทันให้หยุดที่ checkpoint ถัดไป (จุดที่ถ้าหยุดแล้วเริ่มใหม่ งานไม่พัง) แล้วเรียก tool handoff"
- **ข้อความ hard**: "หยุดทันทีที่หยุดได้อย่างปลอดภัย ถ้ากำลังแก้ไฟล์อยู่ให้ทำให้เสร็จจนอยู่ในสภาพที่ใช้ได้ก่อน แล้วเรียก tool handoff"
- **burn rate**: context โตไปเท่าไหร่ใน 10 tool call ล่าสุดของ session หลัก เก็บประวัติในหน่วยความจำของ module (ถ้า reload แล้วหายก็ไม่เป็นไร)

### 3. tool `handoff` (`mcp__kit-checkpoint__handoff`)

ลงทะเบียนด้วย `$.tool.register` ใน `session.start` ตั้ง `isDeferred: false` แล้วตอบใน hook `tool.call` ที่ match ชื่อ tool นี้ (อ่าน input จาก `e.content`, `e.mode`, `e.reason`) description ของ tool บอกว่าให้เรียก**เฉพาะหลังได้คำเตือน `[kit-checkpoint]`** ให้เรียกเป็น tool call **เดียวของข้อความนั้น** และหลังเรียกแล้วให้จบ turn ทันที

input:
- `content` (markdown): ต้องมี เป้าหมาย · ทำเสร็จอะไรไปแล้ว · ค้างอยู่ตรงไหน · ตัดสินใจอะไรไปบ้างและเพราะอะไร · ไฟล์ที่เกี่ยวข้อง · ขั้นต่อไป (description ของ tool บอกหัวข้อเหล่านี้ ส่วน mod ไม่ต้องตรวจโครงสร้าง **(Claude เลือก)**)
- `mode`: `"auto"` (ขั้นต่อไปมีอยู่ใน plan ชัดแล้ว ไปต่อเองได้) หรือ `"wait"` (ต้องให้ผู้ใช้ตัดสินใจ)
- `reason`: บรรทัดเดียว บอกว่าทำไมหยุด หรือทำไมต้องรอ

ไม่ต้องสั่งให้ Claude สรุปในแชทก่อนเรียก เพราะจอจะถูกล้างภายใน ~2.5 วินาที สิ่งที่ผู้ใช้จะเห็นบนมือถือคือข้อความเริ่มต้นที่มี handoff ทั้งก้อน (ข้อ 5) และถ้าเป็นแบบรอ ก็จะมีสรุปจากบทสนทนาใหม่ตามมา ข้อนี้ทำหน้าที่แทน "สรุปลงในแชท" ใน handoff note **(Claude เลือก)**

**สถานะของ handoff** (เก็บใน state ของ module เป็น record เดียวที่มี id ไม่ซ้ำกัน): `none` → `pending` → `committed` → `none` การยกเลิกทำได้เฉพาะตอน `pending` (ก่อน `finalize` สั่ง clear)

plugin ไม่เห็นคำสั่งของตัวเองใน hook ของตัวเอง (spike 4) ข้อความเริ่มต้นและ `/clear` ที่ mod สั่งจึงไม่ผ่าน hook `prompt.submit`/`command.run` ของ mod ถึงอย่างนั้น บรรทัดแรกของ hook `prompt.submit` ให้กรองไว้ด้วย: `if (e.origin.kind === 'plugin' && e.origin.name === $.plugin.name) return next(e)` เผื่อ engine เปลี่ยนพฤติกรรม

**ตอนเรียก tool** (ใน hook `tool.call`):
1. **ปฏิเสธ (ไม่เขียนไฟล์ ไม่ clear)** ในกรณีเหล่านี้:
   - ถูกเรียกจาก subagent (`e.agentId` มีค่า)
   - `e.content` ไม่ใช่ string หรือเป็น string ว่าง (input ของ MCP tool มาเป็น `unknown`)
   - `context.tokens` ต่ำกว่า 400K หรือไม่มีตัวเลข ให้ตอบว่า "context ยังไม่ถึง 400K ไม่ต้อง handoff" **(Claude เลือก)** กันกรณีที่ skill อื่นหรือคำว่า "เขียน handoff" ทำให้ Claude เรียก tool ตอนที่ผู้ใช้ยังใช้ session อยู่ แล้วโดน clear แบบไม่ทันตั้งตัว
   - กำลังงดเตือนอยู่หลัง clear (ข้อ 2) เพราะตัวเลขที่อ่านได้ยังเป็นของเก่า
   - สถานะไม่ใช่ `none` (เรียกซ้ำ)
   - **มี tool call อื่นใน response เดียวกัน**: hook `turn.step` (แบบ generator) ของ session หลักตั้ง `toolsThisRequest = 0` และ `promptsThisRequest = 0` ก่อนทุก model request แล้ว `return yield* next(e)` hook `tool.call` ที่เฝ้า context จะเพิ่ม `toolsThisRequest` ทุก call ของ session หลักที่ไม่ใช่ handoff (เพิ่มอย่างเดียว ไม่ลด จึงไม่รั่ว) handoff ปฏิเสธถ้า `toolsThisRequest > 0` ข้อนี้จับ sibling ที่รันก่อน handoff ส่วน sibling ที่รันหลัง handoff จะโดนกฎยกเลิกด้านล่าง hook `turn.step` เดียวกันนี้จด `e.turnId` ของ session หลักไว้ด้วย (ToolCallInput ไม่มี turnId) เพื่อใช้เป็น "turn ที่เรียก handoff"
   - **มีข้อความเข้ามาระหว่างที่ Claude กำลังเขียน handoff**: `prompt.submit` ยิงตอนกด Enter ไม่ใช่ตอนที่ model เห็น และข้อความจะถูกพับเข้า turn ที่รันอยู่ ถ้า `promptsThisRequest > 0` (hook `prompt.submit` เพิ่มให้) ให้ปฏิเสธด้วย "มีข้อความเข้ามาระหว่างเขียน handoff อ่านก่อน แล้วค่อยเรียกใหม่"
   - ยังมี subagent ที่ status เป็น `pending|running|waiting` (`$.agent.list()`) ให้ตอบว่า "รอให้ subagent ทำเสร็จก่อน แล้วค่อยเรียก handoff ใหม่"
2. หา git-dir ด้วย `git rev-parse --absolute-git-dir` แล้วเขียน `<git-dir>/kit-handoff/<YYYYMMDD-HHmmss>-g<gen>.md` (เวลาไทย) ถ้ามีไฟล์ชื่อนี้อยู่แล้วให้เติมเลขต่อท้าย ห้ามเขียนทับ ในไฟล์มี frontmatter `generation`, `mode`, `reason`, `created` แล้วตามด้วย `content` **ถ้าไม่ใช่ git repo หรือเขียนไม่สำเร็จ: ห้าม clear** ให้ตอบ Claude ว่า "บันทึก handoff ไม่ได้ ใส่ handoff เต็ม ๆ ลงในแชทแล้วหยุด"
   - ไฟล์ของ worktree อยู่ใต้ `.git/worktrees/<name>/` จึงหายไปพร้อมกับ `git worktree remove` ยอมรับข้อนี้ เพราะผู้ใช้เป็นคนลบ worktree เอง **(Claude เลือก)**
3. **เช็คซ้ำแบบไม่มี `await` คั่น** ก่อนตั้งสถานะ: `promptsThisRequest`, `toolsThisRequest`, `state === none` และ turn นี้ยังไม่ถูก abort (`next.signal.aborted` หรือ flag ที่ `turn.complete` แบบ `isAborted` ตั้งไว้ตาม turnId) ถ้ามีอะไรเปลี่ยนระหว่างที่รอ git หรือเขียนไฟล์ ให้ปฏิเสธเหมือนขั้น 1 (ไฟล์ที่เขียนไปแล้วเก็บไว้เป็นบันทึก)
4. ตั้งสถานะเป็น `pending` ด้วย record ใหม่ (`id`, `path`, `content`, `gen`, `mode`, `reason`, `turnId`, `userHasHandoff`, `userRepliedAfterCommit`, `turnBeforeClear` เริ่มเป็น false) แล้ว notify ผู้ใช้ทันทีแบบ best-effort ว่าบันทึก handoff ไว้ที่ไหน
5. ตอบ Claude: "บันทึก handoff ไว้ที่ <path> แล้ว จะ clear ทันทีที่จบ turn นี้ จบ turn เลย ห้ามเรียก tool อื่นอีก"

**กิจกรรมอื่นที่เกิดขึ้น** ได้แก่ `tool.call` ของ session หลักที่ไม่ใช่ `handoff`, `turn.start` ของ session หลักที่ `turnId` ไม่ตรงกับ record, `prompt.submit` ทุกตัว (ข้อความของผู้ใช้, task-notification ฯลฯ) `session.append` ของ session หลักที่ `door === 'delivery'` (จังหวะที่ model ได้รับข้อความที่ถูกพับเข้ามา ใช้ปิดช่องที่ `prompt.submit` ยิงก่อน `turn.step` รีเซ็ตตัวนับ) และ `turn.complete` ที่มี `isAborted` (ผู้ใช้กด Esc) hook ที่เฝ้าต้องนับและยกเลิก**ทันทีที่เข้า hook ก่อน `await` ใด ๆ** แล้วค่อยแนบ context ทีหลัง

- **ตอน `pending`: ยกเลิก** (สถานะกลับเป็น `none`) สิ่งที่เข้ามาถัดไป (ผลของ tool หรือข้อความนั้น) จะได้ context แนบว่า "handoff ที่ <path> เก่าแล้ว ยกเลิก clear อัตโนมัติ ถ้ายังต้องการให้เรียก handoff ใหม่" แล้ว notify ผู้ใช้แบบ best-effort
- **ตอน `committed`:** clear เกิดขึ้นหรือกำลังจะเกิด ยกเลิกไม่ได้แล้ว `prompt.submit` ที่เข้ามา (ทั้งข้อความผู้ใช้และ notification) จะได้ handoff ทั้งก้อนแนบเป็น context พร้อมคำสั่ง "มีข้อความเข้ามาก่อน handoff อย่าทำต่อเอง ถามผู้ใช้ก่อน" แล้วตั้ง `userHasHandoff = true` ใน record ถ้ามาจาก origin `composer`/`bridge` ให้ตั้ง `userRepliedAfterCommit = true` ด้วย ถ้า `turn.start` ของ session หลักยิงขณะ `committed` และ `command.run` ยังไม่ resolve (turn ของคนอื่นแทรกก่อน clear และจะถูก clear ทับ) ให้ตั้ง `turnBeforeClear = true` และเก็บข้อความที่ได้จาก `prompt.submit` ไว้ใน record

**ตอนจบ turn** (hook `turn.complete` ของ session หลักที่ `turnId` ตรงกับ record และไม่ใช่ `isAborted` สถานะยังเป็น `pending`): ตั้ง `$.clock.after(0, () => finalize(rec))` ตอนนี้ session ว่างแล้ว `/clear` จะรันทันที (spike 4 วัดได้ ~0.1 วินาทีหลัง `turn.complete`) `finalize` จับ record ของตัวเองไว้ ทุกขั้นหลัง `await` ทำต่อเฉพาะเมื่อ `state.rec === rec` และ try/finally คืนสถานะเป็น `none` เฉพาะเมื่อ `state.rec === rec` ทุกการ notify เป็นแบบ best-effort
1. ถ้าสถานะไม่ใช่ `pending` ของ record นี้แล้ว (ถูกยกเลิก) ให้หยุด
2. เช็ค `$.agent.list()` อีกรอบ ถ้ามี subagent กำลังทำงาน ให้ยกเลิก (ไม่เลื่อนไว้ทำทีหลัง เพราะรายงานของ subagent จะทำให้ handoff เก่า)
3. จด `$.session.id()` และ `usage().startedAt` แล้ว**ตั้งสถานะ `committed` แบบไม่มี `await` คั่น**ก่อน `$.command.run({ command: 'clear' })` (hook `command.run` ของ mod เองดักคำสั่งของตัวเองไม่ได้ จึงไม่มีจุดยกเลิกระหว่างคิว แต่ session ว่างอยู่ คิวจึงสั้นมาก)
4. ตรวจว่า clear สำเร็จ: session id **หรือ** `startedAt` เปลี่ยน (spike 4 เห็นทั้งสองค่าเปลี่ยน) ถ้า `command.run` reject หรือทั้งสองค่าไม่เปลี่ยน: **ห้าม submit** (บทสนทนาเก่ายังอยู่) แล้ว notify ผู้ใช้พร้อม path
5. ตั้ง generation ของบทสนทนาใหม่เป็น `gen` (หรือ 0 ถ้า `userRepliedAfterCommit`) เก็บไว้ใน `$.state` (ยังอยู่ตอน reload) แล้วเรียก `$.tool.register` ซ้ำในบล็อก try/catch แยก ถ้าล้มเหลวต้องไม่ทำให้ข้ามขั้นถัดไป (spike 4: tool ยังอยู่หลัง clear อยู่แล้ว การลงทะเบียนซ้ำเป็นแค่กันไว้)
6. ตัดสินด้วยกันชน (ข้อ 4) **ตอนนี้** ว่าจะ "ทำต่อเอง" หรือ "รอผู้ใช้"
7. ถ้า `turnBeforeClear` ให้ส่งข้อความเริ่มต้นแบบ**รอผู้ใช้**เสมอ โดยยกข้อความของผู้ใช้ที่ถูก clear ทับมาใส่ไว้ด้วย แล้ว notify ผู้ใช้ ถ้าไม่ใช่และ `userHasHandoff` ให้ข้ามการส่งข้อความเริ่มต้น ถ้าไม่เข้าทั้งสองกรณี ให้ `$.prompt.submit({ text: <ข้อความเริ่มต้น> })` แบบมีกรอบ ("The kit-checkpoint plugin sent a message") **ไม่ใช้ `asUser`** เพราะ handoff เป็นข้อความที่ Claude เขียน ไม่ควรมีน้ำหนักเท่าคำสั่งของผู้ใช้ (spike 4: Claude ทำตามข้อความแบบมีกรอบ) **(Claude เลือก)** ถ้า reject หรือได้ `{ drop }` กลับมา ให้ notify ผู้ใช้พร้อม path ช่องว่างระหว่างเช็ค `userHasHandoff` กับตอนที่ข้อความเริ่มต้นเข้าคิวมีไม่กี่มิลลิวินาที ยอมรับได้ เพราะถ้าเกิดขึ้น ข้อความของผู้ใช้ก็ยังได้ handoff แนบไปอยู่ดี
8. notify ว่าทำต่อเองหรือรอ (ถ้ารอ บอกว่ารอเรื่องอะไร)

### 4. กันชน (บังคับในโค้ด ไม่ได้ขึ้นกับ Claude)

ทำต่อเองได้ก็ต่อเมื่อผ่าน**ทุกข้อ** ถ้าข้อมูลขาดหรือ error ถือว่า "รอผู้ใช้":

1. `mode === "auto"`
2. **ตัวนับรุ่น**: บทสนทนามี generation `g` handoff ใหม่ได้ `g + 1` และทำต่อเองได้เฉพาะตอน `g + 1 ≤ 3` (clear แล้วทำต่อเองได้สูงสุด 3 รอบติดกันหลังข้อความล่าสุดของผู้ใช้) `g` ถูกตั้งใน `finalize` หลัง clear สำเร็จ (เก็บใน `$.state`) และรีเซ็ตตอนผู้ใช้ตอบ (ข้อ 6)
3. **limit**: ต้องมี `five_hour` และ `< 90` ต้องมี `seven_day` และ `< 85` ถ้า `usage().rateLimits` ว่าง ให้ใช้ค่าล่าสุดที่ไม่ว่างที่ hook `tool.call` เก็บไว้ ถ้าอายุไม่เกิน 15 นาที **(Claude เลือก)** ถ้าไม่มีเลยถือว่าไม่ผ่าน

ถ้าไม่ผ่านกันชน **ยังคง clear เหมือนเดิม** (ประหยัด limit ได้แม้ตอนต้องรอ) ต่างกันแค่ข้อความเริ่มต้น

### 5. ข้อความเริ่มต้นของบทสนทนาใหม่

ขึ้นต้นด้วย `[kit-checkpoint #<gen>]` ตามด้วย path ของไฟล์ เนื้อหา handoff ทั้งหมด และหมายเหตุว่า "ถ้ามี notification จาก task ที่เริ่มไว้ก่อน clear (เช่น Workflow, Bash background) เข้ามา ให้รายงานผู้ใช้ อย่าลงมือทำตาม" แล้วตามด้วยคำสั่งอย่างใดอย่างหนึ่ง:
- **ทำต่อเอง**: "ตรวจสภาพจริงก่อน (git status, test ที่เกี่ยวข้อง) แล้วทำต่อจาก 'ขั้นต่อไป'"
- **รอผู้ใช้**: "ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร (<reason>) แล้วรอ" ถ้าสาเหตุคือกันชน ให้บอกว่าติดข้อไหนด้วย

### 6. เมื่อผู้ใช้ตอบ (รีเซ็ตตัวนับ)

ทุก `prompt.submit` ที่ `origin.kind` เป็น `composer` หรือ `bridge` ให้ตั้ง generation เป็น 0 origin อื่นทั้งหมด (`task-notification`, `scheduled-trigger`, `unclassified` ฯลฯ) ไม่รีเซ็ตตัวนับ (แต่ทุก `prompt.submit` ทำให้ handoff ที่ `pending` ถูกยกเลิกตามข้อ 3)

## ทางที่พิจารณาแล้วไม่เลือก

- **spawn session ใหม่ใน Orca:** ใช้ได้เฉพาะใน Orca ต้องมีกลไกจองไฟล์และแยกข้อความแรก และเสี่ยงให้สอง session ทำงานใน worktree เดียวกัน (รีวิวรอบแรกเจอ blocker 1 ข้อ major 3 ข้อจากเรื่องนี้) clear + paste ประหยัด limit ได้เท่ากันโดยไม่มีปัญหาพวกนี้
- **compact + ยัด handoff ผ่าน hook `session.compact`:** บัญชี Team ใช้ไม่ได้ (spike 2) ทางเดียวที่จะใช้ได้คือให้องค์กรติดตั้ง plugin เป็น managed (`enabledPlugins` + `prependPlugins` ไว้ก่อน `sec-default@builtin` ใน managed settings) แต่นั่นทำให้ plugin มีสิทธิ์สูงสุดเหนือ `sec-default` ทุกเครื่องในทีม กิตเลือกไม่เอา
- **ปล่อยให้ compact ของ engine ทำงาน:** model สรุปเอง คุมคุณภาพของ handoff ไม่ได้ และแนบไฟล์กลับเข้ามาทั้งไฟล์
- **v1 แบบรอผู้ใช้อย่างเดียว ไม่มีทำต่อเอง:** ตัดตัวนับรุ่นกับกันชน limit ออกได้ (แต่การ clear อัตโนมัติและ race ทั้งหมดในข้อ 3 ยังอยู่) แต่กิตต้องการให้งานเดินต่อตอนไม่อยู่หน้าคอม จึงเก็บ auto ไว้

## ให้ builder ตัดสินใจเอง

- ถ้อยคำของข้อความทั้งหมด (ภาษาไทย สั้น อ่านบนมือถือได้ เรียก "ผู้ใช้")
- การแบ่งไฟล์ ชื่อฟังก์ชัน และรูปแบบของ frontmatter
- รายละเอียดของหน้าต่าง burn rate

## ต้องเช็คระหว่างทำ

- `$.fs.write` ลง git-dir ใน **linked worktree** (git-dir อยู่นอก cwd) ทำงานภายใต้ `sec-default` ไหม (spike 4 ลองแค่ checkout หลัก)
- ลำดับในคิว: ข้อความที่ผู้ใช้พิมพ์ระหว่าง `pending`/`committed` เข้ามาตอนไหน และการยกเลิก/การแนบในข้อ 3 จับได้ครบไหม
- ข้อความที่กิตพิมพ์จากมือถือผ่าน Orca มี `origin.kind` เป็นอะไร ถ้าเป็น `unclassified` ตัวนับจะไม่รีเซ็ต แล้ว auto จะหยุดหลัง 3 รอบ (ปลอดภัย แต่ต้องรู้ไว้ การยกเลิก clear ไม่ขึ้นกับ origin)
- `/clear` หยุด task ที่ `$.agent.list()` มองไม่เห็นหรือเปล่า (Bash background, Monitor, agent ของ Workflow) และ teammate ที่ `idle` รอด `/clear` ไหม ถ้าไม่รอด ให้เพิ่ม `idle` เข้าไปในสถานะที่ทำให้ปฏิเสธ ทั้งตอนเรียก tool (ข้อ 3 ขั้น 1) และใน `finalize` ขั้น 2
- `$.ui.notify` ไปถึงมือถือผ่าน Orca จริงไหม

## วิธีทดสอบ

- unit test (`claude plugin test`) สำหรับ logic ล้วน ๆ: การตัดสิน soft/hard + dedupe, burn rate, กันชนทุกข้อรวมกรณีข้อมูลขาดและ rateLimits ที่เก่าเกิน, เงื่อนไขปฏิเสธของ tool (ต่ำกว่า 400K, subagent, เรียกซ้ำ, มี tool call อื่นใน response เดียวกัน), การเปลี่ยนสถานะ `none/pending/committed` และเหตุที่ทำให้ยกเลิกหรือแนบ handoff, การงดเตือนหลัง clear, การสร้างข้อความเริ่มต้นทั้งสองแบบ, generation อยู่ใน `$.state` หลัง clear, การตัดสินเรื่องรีเซ็ตตัวนับตาม origin, ชื่อไฟล์ที่ไม่ชนกัน, frontmatter
- hook-level test ด้วย `claude plugin test` (ใช้ hook ฝั่ง test ทำตัวเป็น engine และ clock จำลอง): ยิง `prompt.submit` แทรกตอน `pending` และตอน `committed`, ยิง `tool.call` ของ sibling ก่อน handoff ใน request เดียวกัน, ยิง `prompt.submit` ระหว่างที่ handoff กำลังเขียนไฟล์, ยิง `turn.complete` แบบ `isAborted`, ยิง `prompt.submit` ระหว่าง request ที่มี handoff, เช็คว่าหลัง prompt แทรกตอน `committed` และหลัง submit ได้ `{ drop }` สถานะกลับเป็น `none` และ handoff ครั้งถัดไปถูกรับ, finalize ของ record เก่าต้องไม่แตะ record ใหม่ ถ้า test kit เปลี่ยน `startedAt` หรือ session id ไม่ได้ ให้ทดสอบส่วนนั้นตอนลองของจริงแทน
- ลองของจริงผ่าน `--plugin-dir` ใน terminal แยก (แบบเดียวกับ spike) โดยลดเกณฑ์ลงชั่วคราว ไล่ดูให้ครบ: เตือน → handoff → ไฟล์ → clear → ข้อความเริ่มต้น → ทำต่อ/รอ และดูว่ากันชนแต่ละข้อทำงาน
  - รุ่นที่ 4 ต้องรอ, rateLimits ว่างต้องรอ, ไม่ใช่ git repo ต้องไม่ clear
  - เรียก handoff พร้อม Agent ในข้อความเดียว ทั้งแบบ Agent มาก่อนและมาหลัง ต้องไม่ทำให้รายงานของ subagent หาย
  - notification ที่เข้ามาระหว่าง turn ของ handoff ต้องทำให้ยกเลิก
  - พิมพ์ระหว่างที่ Claude กำลังเขียน handoff, พิมพ์แทรกหลัง handoff, กด Esc, และพิมพ์ระหว่างที่กำลัง clear ต้องไม่ทำให้อะไรหาย
  - ข้อความแบบ ctrl+x enter (`wait: true`) ระหว่าง turn ของ handoff: ถ้าพบว่าถูกเก็บไว้จนจบ turn (ไม่ถูกพับเข้า request ถัดไปแบบ Enter ธรรมดา) ให้เพิ่มเงื่อนไขปฏิเสธด้วยข้อความ "จบ turn ไปก่อน ไม่ต้อง handoff ข้อความที่รอคิวจะเข้ามา"
  - รันใน linked worktree หนึ่งรอบ
- จากนั้นกิตลองใช้กับงานจริงสักสองสามวัน

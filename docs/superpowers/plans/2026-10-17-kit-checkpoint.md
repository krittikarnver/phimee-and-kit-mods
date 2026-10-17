# kit-checkpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** mod `kit-checkpoint` เตือน Claude ที่ 400K/500K, รับ tool `handoff`, เขียนไฟล์ลง `.git/kit-handoff/`, `/clear` ตอนจบ turn แล้วส่ง handoff เป็นข้อความแรก (ทำต่อเองเมื่อผ่านกันชน)

**Architecture:** hooks module ไฟล์เดียว (`hooks/register.ts`) ถือ state ในหน่วยความจำของ module ยกเว้น generation ที่อยู่ใน `$.state` logic ล้วน ๆ (เกณฑ์, dedupe, burn rate, กันชน, เงื่อนไขปฏิเสธ, ชื่อไฟล์, ข้อความทั้งหมด) อยู่ใน `hooks/logic.ts` ให้ unit test import ได้ race ทั้งหมดทดสอบด้วย hook-level test ที่ test ทำตัวเป็น engine

**Tech Stack:** Claude Code hooks module (engine 2.1.302), `claude-code/testing`, TypeScript ไม่มี dependency

**Spec:** `docs/superpowers/specs/2026-10-17-kit-checkpoint-design.md` (อ่านคู่กันเสมอ plan อ้างข้อในนั้นเป็น "spec ข้อ N")

## Global Constraints

- ข้อความที่ผู้ใช้หรือ model อ่านเป็นภาษาไทย ข้อความถึง model เรียก "ผู้ใช้" ไม่ใช่ "กิต" บรรทัด context ขึ้นต้นด้วย `[kit-checkpoint]`
- ห้าม deny หรือขวาง tool call/prompt ใด ๆ ยกเว้นการตอบ tool `handoff` ของตัวเอง hook ที่เฝ้าต้องคืนผลเดิมเสมอเมื่อ logic ของตัวเองพัง
- ห้าม `/clear` ถ้ายังเขียนไฟล์ไม่สำเร็จ ห้าม `/clear` ทับกิจกรรมที่เกิดหลังเขียน handoff ห้ามลบหรือเขียนทับไฟล์ handoff
- ถ้าไม่แน่ใจ (ข้อมูลขาด, error) ให้ "รอผู้ใช้" ไม่ทำต่อเอง
- ค่าคงที่ (ไม่มี config): `SOFT = 400_000`, `HARD = 500_000`, `STEP = 25_000`, `MAX_AUTO_GEN = 3`, `five_hour < 90`, `seven_day < 85`, rateLimits ที่เก็บไว้ใช้ได้ไม่เกิน 15 นาที, burn rate ดู 10 tool call ล่าสุด, subagent ที่ถือว่าทำงานอยู่: `pending|running|waiting`
- ชื่อ tool: `handoff` (model เห็นเป็น `mcp__kit-checkpoint__handoff`) ลงทะเบียนด้วย `isDeferred: false`
- เวลาเป็น Asia/Bangkok (UTC+7 คงที่)
- helper ที่รับ `$` ต้องประกาศระดับบนสุดของไฟล์ (`claude plugin validate` บังคับ) ชนิดของ `$` คือ `EngineInterface` จาก `'claude-code'`
- `$.state` เก็บแค่ `gen` (ประกาศใน `types/index.d.ts`) ที่เหลืออยู่ในหน่วยความจำของ module
- version เริ่ม `0.1.0` commit subject ขึ้นต้น `kit-checkpoint 0.1.0:` ห้าม commit `docs/kit-checkpoint-handoff.md`

## ข้อเท็จจริงของ test kit (probe ใน session ที่เขียน plan นี้)

- test `$` เรียก event ผ่าน hook ของ plugin แล้วลงไปที่ `on(...)` ของ test ที่อยู่ข้างล่าง op ของ plugin (`session.usage`, `session.id`, `agent.list`, `process.run`, `fs.exists`, `fs.write`, `ui.notify`, `tool.register`) test ตอบด้วย `{ value }`
- `$.command.run` และ `$.prompt.submit` ของ plugin ลงไปถึง `on('command.run')` / `on('prompt.submit')` ของ test (`origin.kind === 'plugin'`) และ hook `prompt.submit` ของ plugin เองไม่เห็น ตรงกับ spike 4 test เปลี่ยน session id/`startedAt` หลัง `command.run` ได้
- test อ่านตัวแปรใน module ไม่ได้ (import ได้ instance คนละตัว) ต้องดูผลผ่านสิ่งที่ plugin เรียก `$` เท่านั้น
- test ต้องตอบเองทุก event ที่เรียก: `turn.step` (generator คืน `TurnStepResult`), `turn.complete` (คืน `{ text }`), `session.start` (คืน `{ cwd }`), `turn.start` (คืน `{ turnId }`) ส่วน `session.append` kit ตอบให้เอง
- `$.prompt.submit` ของ test ต้องใส่ `origin` และ `wait` ครบ `$.tool.call` ของ MCP tool ใส่ input บน object ตรง ๆ (`{ tool, content, mode, reason }`)

## Review Focus

1. `reason` หรือ `content` มีขึ้นบรรทัดใหม่, `:` หรือ `---` ต้องไม่ทำ frontmatter พัง → Task 3 `handoffDoc one-lines and quotes reason`
2. อ่าน usage พังตอนเรียก handoff ต้องได้คำตอบที่ปลอดภัย ไม่ใช่ error ว่าไม่มี hook ตอบ → Task 5 `handoff with usage failure refuses`
3. ผู้ใช้พิมพ์ `/clear` เองตอน context สูง แล้ว Claude เรียก handoff ทันที ต้องปฏิเสธเพราะตัวเลขยังเก่า → Task 5 `refuses right after a user clear`
4. `command.run` reject (ไม่ใช่แค่ id ไม่เปลี่ยน) ต้องไม่ submit, แจ้ง path, และ handoff ครั้งถัดไปต้องรับ → Task 6 `clear rejects: no submit, next handoff accepted`
5. `$.ui.notify` reject ทุกครั้ง flow ต้องเดินต่อจนจบ → Task 6 `notify failures never stop the flow`

ข้อที่ test kit จำลองไม่ได้ (ลำดับคิวจริง, origin จากมือถือ, task ที่ `$.agent.list()` มองไม่เห็น) อยู่ใน Task 8

---

## File Structure

```
plugins/kit-checkpoint/
  .claude-plugin/plugin.json   name, version 0.1.0, description ไทย, author Kit, "types": "./types/index.d.ts"
  hooks/hooks.json             { "modules": ["./register.ts"] }
  hooks/logic.ts               ค่าคงที่ + ฟังก์ชันล้วน + MSG (ข้อความทั้งหมด)
  hooks/logic.test.ts
  hooks/register.ts            hooks + state ของ module
  hooks/register.test.ts       hook-level tests
  tsconfig.json                { "extends": "./.claude-plugin/types/tsconfig.json" }
  types/index.d.ts             PluginState 'kit-checkpoint': { gen: number }
.claude-plugin/marketplace.json   + entry
README.md                          + บรรทัดติดตั้ง + section
```

---

### Task 1: เช็ค `$.fs.write` ลง git-dir ของ linked worktree (spec "ต้องเช็คระหว่างทำ" ข้อ 1)

ถูกที่สุดและถ้าไม่ผ่าน design เปลี่ยน จึงทำก่อน ไม่มี commit

**Files:** ทั้งหมดอยู่ใน scratchpad ของ session (ไม่ใช่ใน repo)

- [ ] **Step 1: สร้าง probe mod** `<scratch>/wt-probe/` มี `plugin.json` (`name: "wt-probe"`), `hooks/hooks.json`, `hooks/register.ts` ที่มีแค่ hook `session.start`: `$.process.run(['git', 'rev-parse', '--absolute-git-dir'])` แล้ว `$.fs.write(\`${gitDir}/kit-handoff/probe.md\`, 'ok')` (โฟลเดอร์ `kit-handoff/` ต้องยังไม่มี เพื่อเช็คว่าสร้างโฟลเดอร์ให้ด้วย) แล้ว `return next(e)`
- [ ] **Step 2: สร้าง linked worktree แล้วรัน**

```bash
git worktree add <scratch>/wt-probe-tree -b kit-wt-probe
cd <scratch>/wt-probe-tree && claude -p 'ตอบคำว่า ok' --plugin-dir <scratch>/wt-probe --debug 2>&1 | tail -5
ls "$(git -C <scratch>/wt-probe-tree rev-parse --absolute-git-dir)/kit-handoff/probe.md"
```

Expected: `ls` เจอไฟล์ (path อยู่ใต้ `.git/worktrees/wt-probe-tree/kit-handoff/`) ถ้า `-p` ไม่โหลด plugin เพราะ workspace ไม่ trusted ให้รันแบบ interactive แทน

- [ ] **Step 3: เก็บกวาด** `git worktree remove <scratch>/wt-probe-tree && git branch -D kit-wt-probe`
- [ ] **Step 4: ถ้าเขียนไม่ได้: หยุด** รายงานผู้ใช้พร้อมบรรทัดจาก debug log ห้ามทำ Task ถัดไป (ต้องแก้ spec ข้อ 3 ขั้น 2 ก่อน)

---

### Task 2: โครง plugin + logic ของคำเตือน

**Files:**
- Create: `plugins/kit-checkpoint/.claude-plugin/plugin.json`, `hooks/hooks.json`, `tsconfig.json`, `types/index.d.ts`
- Create: `plugins/kit-checkpoint/hooks/logic.ts`, `hooks/logic.test.ts`
- Create: `plugins/kit-checkpoint/hooks/register.ts` (ตอนนี้แค่ `export const register: Register = () => {}`)

**Interfaces:**
- Produces (`logic.ts`):
  - `SOFT`, `HARD`, `STEP`, `BURN_CALLS = 10` (number)
  - `type Level = 'soft' | 'hard'`, `type Burn = { grew: number; calls: number }`
  - `formatK(tokens: number): string` (คัดจาก `kit-usage/hooks/format.ts` บรรทัดเดียว plugin ติดตั้งแยกกัน import ข้ามไม่ได้)
  - `warnLevel(tokens: number | undefined, lastWarned: number | null): Level | null`
  - `burn(history: readonly number[]): Burn | null` (history เรียงเก่าไปใหม่ ใช้ `BURN_CALLS + 1` ตัวท้าย)
  - `warnText(level: Level, tokens: number, b: Burn | null): string`
  - `MSG.soft`, `MSG.hard` (copy ด้านล่าง)

กฎ `warnLevel`: `undefined` หรือ `< SOFT` → `null` · `lastWarned === null` → เตือน · `tokens >= lastWarned + STEP` → เตือน · `tokens >= HARD && lastWarned < HARD` → เตือน ระดับคือ `tokens >= HARD ? 'hard' : 'soft'`

Copy (ตาม spec ข้อ 2):
- `MSG.soft = 'ทำชิ้นปัจจุบันต่อได้ ประเมินว่างานชิ้นถัดไปจะทำทันก่อน 500K ไหม ถ้าไม่ทันให้หยุดที่ checkpoint ถัดไป (จุดที่ถ้าหยุดแล้วเริ่มใหม่ งานไม่พัง) แล้วเรียก tool handoff'`
- `MSG.hard = 'หยุดทันทีที่หยุดได้อย่างปลอดภัย ถ้ากำลังแก้ไฟล์อยู่ให้ทำให้เสร็จจนอยู่ในสภาพที่ใช้ได้ก่อน แล้วเรียก tool handoff'`
- `warnText` = `` `[kit-checkpoint] context ${formatK(t)} · เหลือ ${formatK(max(0, HARD - t))} ก่อนถึง 500k · ${burnPart} · ${MSG[level]}` `` โดย `burnPart` = `` `โต ${formatK(grew)} ใน ${calls} tool call ล่าสุด` `` หรือ `'ยังไม่มี burn rate'`

- [ ] **Step 1: เขียน scaffold** (plugin.json, hooks.json, tsconfig.json แบบ kit-usage) และ `types/index.d.ts`:

```ts
export type Generation = number

declare module 'claude-code' {
  interface PluginState {
    'kit-checkpoint': { gen: Generation }
  }
}
```

- [ ] **Step 2: เขียน test ที่ fail** `hooks/logic.test.ts`

```ts
test('warn levels and dedupe', () => {
  expect(warnLevel(undefined, null)).toBeNull()
  expect(warnLevel(399_999, null)).toBeNull()
  expect(warnLevel(400_000, null)).toBe('soft')
  expect(warnLevel(410_000, 400_000)).toBeNull()
  expect(warnLevel(425_000, 400_000)).toBe('soft')
  expect(warnLevel(500_000, 490_000)).toBe('hard') // ข้าม 500K เตือนทันทีแม้ยังไม่ครบ +25K
  expect(warnLevel(510_000, 500_000)).toBeNull()
  expect(warnLevel(525_000, 500_000)).toBe('hard')
})

test('burn over the last 10 calls', () => {
  expect(burn([])).toBeNull()
  expect(burn([400_000])).toBeNull()
  expect(burn([100, 200, 350])).toEqual({ grew: 250, calls: 2 })
  expect(burn(Array.from({ length: 15 }, (_, i) => i * 1000))).toEqual({ grew: 10_000, calls: 10 })
})

test('warn text', () => {
  expect(warnText('soft', 430_000, { grew: 40_000, calls: 10 })).toBe(
    `[kit-checkpoint] context 430k · เหลือ 70k ก่อนถึง 500k · โต 40k ใน 10 tool call ล่าสุด · ${MSG.soft}`)
  expect(warnText('hard', 520_000, null)).toBe(
    `[kit-checkpoint] context 520k · เหลือ 0k ก่อนถึง 500k · ยังไม่มี burn rate · ${MSG.hard}`)
})
```

- [ ] **Step 3:** `claude plugin test ./plugins/kit-checkpoint` → FAIL (ยังไม่มี export)
- [ ] **Step 4: เขียน `logic.ts`** ตาม Interfaces
- [ ] **Step 5:** `claude plugin test ./plugins/kit-checkpoint` → PASS และ `claude plugin validate ./plugins/kit-checkpoint` ไม่มี error
- [ ] **Step 6: Commit** `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: scaffold and warning logic"`

---

### Task 3: logic ของ handoff (ปฏิเสธ, กันชน, ไฟล์, ข้อความ)

**Files:** Modify `plugins/kit-checkpoint/hooks/logic.ts`, `hooks/logic.test.ts`

**Interfaces:**
- Consumes: `SOFT` จาก Task 2
- Produces (`logic.ts`):
  - `TOOL_NAME = 'handoff'`, `TOOL = 'mcp__kit-checkpoint__handoff'`, `MAX_AUTO_GEN = 3`, `RATE_MAX_AGE_MS = 15 * 60_000`, `BUSY: readonly string[] = ['pending', 'running', 'waiting']`
  - `type Phase = 'none' | 'pending' | 'committed'`
  - `type Rate = { kind: string; percentUsed: number }`
  - `type CallFacts = { agentId?: string; content: unknown; tokens?: number; quiet: boolean; phase: Phase; tools: number; prompts: number; busyAgents: number }`
  - `refusal(f: CallFacts): string | null` ตรวจตามลำดับ spec ข้อ 3 ขั้น 1: subagent → content → tokens → quiet → phase → tools → prompts → busyAgents
  - `type Verdict = { auto: true } | { auto: false; blocked?: string }`
  - `pickLimits(current: readonly Rate[], cached: { limits: readonly Rate[]; at: number } | null, now: number): readonly Rate[] | null` (current ไม่ว่าง → current; ว่างและ cache อายุ ≤ 15 นาที → cache; ไม่งั้น `null`)
  - `guard(mode: 'auto' | 'wait', gen: number, limits: readonly Rate[] | null): Verdict` (`wait` → `{ auto: false }` ไม่มี blocked; ข้ออื่นที่ไม่ผ่าน → `blocked` เป็นเหตุผลภาษาไทยบอกว่าติดข้อไหน)
  - `stamp(now: number): string` → `YYYYMMDD-HHmmss` เวลาไทย
  - `handoffPath(gitDir: string, now: number, gen: number, n: number): string` → `<gitDir>/kit-handoff/<stamp>-g<gen>.md`, `n >= 2` เติม `-<n>` ก่อน `.md`
  - `handoffDoc(h: { gen: number; mode: 'auto' | 'wait'; reason: string; now: number; content: string }): string`
  - `type StartInput = { gen: number; path: string; content: string; reason: string }`
  - `startText(h: StartInput, v: Verdict, overwritten?: readonly string[]): string`
  - `resetsGen(kind: string): boolean` (`composer`, `bridge` → true)
  - `MSG` เพิ่ม key ด้านล่าง ฟังก์ชันที่รับ path/content เป็น `(x: string) => string`

Copy (ข้อความที่ spec ระบุไว้ใช้ตามนั้น ข้อที่เหลือ builder ปรับคำได้ แต่ test อ้าง key เสมอ):
- `notYet: 'context ยังไม่ถึง 400K ไม่ต้อง handoff'`
- `fromSubagent: 'เรียก handoff ได้จาก session หลักเท่านั้น'`
- `noContent: 'content ว่าง ใส่ handoff ทั้งก้อนแล้วเรียกใหม่'`
- `justCleared: 'เพิ่ง clear ไป ตัวเลข context ยังเป็นของเก่า ไม่ต้อง handoff'`
- `already: 'มี handoff ค้างอยู่แล้ว จบ turn เลย'`
- `siblings: 'handoff ต้องเป็น tool call เดียวของข้อความนั้น เรียกใหม่โดยไม่มี tool อื่น'`
- `promptArrived: 'มีข้อความเข้ามาระหว่างเขียน handoff อ่านก่อน แล้วค่อยเรียกใหม่'`
- `agentsBusy: 'รอให้ subagent ทำเสร็จก่อน แล้วค่อยเรียก handoff ใหม่'`
- `saveFailed: 'บันทึก handoff ไม่ได้ ใส่ handoff เต็ม ๆ ลงในแชทแล้วหยุด'`
- `saved: p => \`บันทึก handoff ไว้ที่ ${p} แล้ว จะ clear ทันทีที่จบ turn นี้ จบ turn เลย ห้ามเรียก tool อื่นอีก\``
- `stale: p => \`[kit-checkpoint] handoff ที่ ${p} เก่าแล้ว ยกเลิก clear อัตโนมัติ ถ้ายังต้องการให้เรียก handoff ใหม่\``
- `committed: c => \`[kit-checkpoint] มีข้อความเข้ามาก่อน handoff อย่าทำต่อเอง ถามผู้ใช้ก่อน\n\n${c}\``
- `bgNote: 'ถ้ามี notification จาก task ที่เริ่มไว้ก่อน clear (เช่น Workflow, Bash background) เข้ามา ให้รายงานผู้ใช้ อย่าลงมือทำตาม'`
- `goOn: 'ตรวจสภาพจริงก่อน (git status, test ที่เกี่ยวข้อง) แล้วทำต่อจาก "ขั้นต่อไป"'`
- `stay: r => \`ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร (${r}) แล้วรอ\``
- `overwrittenBlock: 'มีข้อความของผู้ใช้ถูก clear ทับ'`

รูปแบบ `startText`: `` `[kit-checkpoint #${gen}] ${path}\n\n${content}\n\n---\n${MSG.bgNote}\n` `` แล้วต่อด้วย `MSG.goOn` (auto) หรือ `MSG.stay(reason)` ตามด้วย `` ` · ทำต่อเองไม่ได้เพราะ: ${blocked}` `` เมื่อมี blocked ถ้ามี `overwritten` ต่อท้ายด้วยบรรทัด `ข้อความของผู้ใช้ที่ถูก clear ทับ:` และแต่ละข้อความเป็น `> ...`

รูปแบบ `handoffDoc` (ตรงกับไฟล์ handoff ที่ใช้อยู่ใน `.git/kit-handoff/`):

```
---
generation: 1
mode: auto
reason: "<reason ยุบเป็นบรรทัดเดียว แล้ว JSON.stringify>"
created: 2026-10-17 18:55 (Asia/Bangkok)
---

<content>
```

- [ ] **Step 1: เขียน test ที่ fail**

```ts
const ok: CallFacts = { content: 'x', tokens: 450_000, quiet: false, phase: 'none', tools: 0, prompts: 0, busyAgents: 0 }
const both = [{ kind: 'five_hour', percentUsed: 10 }, { kind: 'seven_day', percentUsed: 10 }]
const now = Date.UTC(2026, 9, 17, 11, 55, 7) // 18:55:07 Bangkok

test('refusal reasons in order', () => {
  expect(refusal(ok)).toBeNull()
  expect(refusal({ ...ok, agentId: 'a1' })).toBe(MSG.fromSubagent)
  expect(refusal({ ...ok, content: '' })).toBe(MSG.noContent)
  expect(refusal({ ...ok, content: 42 })).toBe(MSG.noContent)
  expect(refusal({ ...ok, tokens: undefined })).toBe(MSG.notYet)
  expect(refusal({ ...ok, tokens: 399_999 })).toBe(MSG.notYet)
  expect(refusal({ ...ok, quiet: true })).toBe(MSG.justCleared)
  expect(refusal({ ...ok, phase: 'pending' })).toBe(MSG.already)
  expect(refusal({ ...ok, tools: 1 })).toBe(MSG.siblings)
  expect(refusal({ ...ok, prompts: 1 })).toBe(MSG.promptArrived)
  expect(refusal({ ...ok, busyAgents: 1 })).toBe(MSG.agentsBusy)
  expect(refusal({ ...ok, agentId: 'a1', tokens: 1 })).toBe(MSG.fromSubagent)
})

test('limits: current, fresh cache, stale cache', () => {
  expect(pickLimits(both, null, now)).toBe(both)
  expect(pickLimits([], { limits: both, at: now - 14 * 60_000 }, now)).toBe(both)
  expect(pickLimits([], { limits: both, at: now - 16 * 60_000 }, now)).toBeNull()
  expect(pickLimits([], null, now)).toBeNull()
})

test('guard', () => {
  expect(guard('auto', 1, both)).toEqual({ auto: true })
  expect(guard('auto', 3, both)).toEqual({ auto: true })
  expect(guard('wait', 1, both)).toEqual({ auto: false })
  for (const v of [
    guard('auto', 4, both),
    guard('auto', 1, null),
    guard('auto', 1, [both[0]]),
    guard('auto', 1, [both[1]]),
    guard('auto', 1, [{ kind: 'five_hour', percentUsed: 90 }, both[1]]),
    guard('auto', 1, [both[0], { kind: 'seven_day', percentUsed: 85 }]),
  ]) {
    expect(v.auto).toBe(false)
    expect('blocked' in v && typeof v.blocked).toBe('string')
  }
  expect(guard('auto', 1, [{ kind: 'five_hour', percentUsed: 89.9 }, both[1]])).toEqual({ auto: true })
})

test('file names never collide', () => {
  expect(stamp(now)).toBe('20261017-185507')
  expect(handoffPath('/repo/.git', now, 1, 1)).toBe('/repo/.git/kit-handoff/20261017-185507-g1.md')
  expect(handoffPath('/repo/.git', now, 1, 2)).toBe('/repo/.git/kit-handoff/20261017-185507-g1-2.md')
})

test('handoffDoc one-lines and quotes reason', () => {
  const doc = handoffDoc({ gen: 2, mode: 'wait', reason: 'a: b\n---\nc', now, content: '# งาน\n---\nต่อ' })
  expect(doc).toBe('---\ngeneration: 2\nmode: wait\nreason: "a: b --- c"\ncreated: 2026-10-17 18:55 (Asia/Bangkok)\n---\n\n# งาน\n---\nต่อ')
})

test('start text', () => {
  const h = { gen: 2, path: '/repo/.git/kit-handoff/x.md', content: '# งาน', reason: 'รอเลือก API' }
  const auto = startText(h, { auto: true })
  expect(auto.startsWith('[kit-checkpoint #2] /repo/.git/kit-handoff/x.md\n\n# งาน')).toBe(true)
  expect(auto).toContain(MSG.bgNote)
  expect(auto).toContain(MSG.goOn)
  const wait = startText(h, { auto: false, blocked: 'ทำต่อเองครบ 3 รอบแล้ว' }, ['แก้ตรงนี้ด้วย'])
  expect(wait).toContain(MSG.stay('รอเลือก API'))
  expect(wait).toContain('ทำต่อเองครบ 3 รอบแล้ว')
  expect(wait).toContain('> แก้ตรงนี้ด้วย')
  expect(wait).not.toContain(MSG.goOn)
})

test('which origins reset the generation', () => {
  expect(resetsGen('composer')).toBe(true)
  expect(resetsGen('bridge')).toBe(true)
  for (const k of ['task-notification', 'scheduled-trigger', 'unclassified', 'plugin', 'sdk']) expect(resetsGen(k)).toBe(false)
})
```

- [ ] **Step 2:** `claude plugin test ./plugins/kit-checkpoint` → FAIL
- [ ] **Step 3: เขียนฟังก์ชันใน `logic.ts`** ตาม Interfaces เวลาไทยใช้วิธีเดียวกับ `formatReset` ใน kit-usage (`+7h` แล้วอ่าน `getUTC*`)
- [ ] **Step 4:** `claude plugin test ./plugins/kit-checkpoint` → PASS
- [ ] **Step 5: Commit** `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: handoff rules, file naming and messages"`

---

### Task 4: เฝ้า context (spec ข้อ 2)

**Files:** Modify `plugins/kit-checkpoint/hooks/register.ts` · Create `hooks/register.test.ts`

**Interfaces:**
- Consumes: `warnLevel`, `burn`, `warnText`, `SOFT`, `BURN_CALLS`, `TOOL`, `Rate` จาก Task 2–3
- Produces (`register.ts` ระดับบนสุด ใช้ต่อใน Task 5–6):
  - `const gen = atom({ plugin: 'kit-checkpoint', key: 'gen' } as const, 0)`
  - `const s` state ของ module: `lastWarned: number | null`, `history: number[]`, `rate: { limits: Rate[]; at: number } | null`, `startedAt: number | null`, `quiet: boolean` (Task 5 เพิ่ม `rec`, `tools`, `prompts`, `turnId`, `aborted: Set<string>`, `note: string | null`)
  - `async function observe($: EngineInterface): Promise<SessionUsage>`: อ่าน `$.session.usage()` · `startedAt` เปลี่ยนจากที่เคยเห็น → `quiet = true`, ล้าง `history` และ `lastWarned` · `rateLimits` ไม่ว่าง → เก็บลง `s.rate` พร้อม `$.clock.now()` · `tokens < SOFT` → `quiet = false`, `lastWarned = null`
  - `function warningFor(tokens: number | undefined): string | null`: `null` ถ้า `quiet` (ครอบช่วง `committed` ด้วย เพราะ finalize ตั้ง `quiet` ตอน commit) ไม่งั้น `warnLevel` + `warnText` ผู้เรียกตั้ง `s.lastWarned = tokens` **เฉพาะตอนแนบได้จริง**

Hooks:
- `tool.call` (ตัวเดียว ไม่ใช้ matcher): `e.tool === TOOL` → Task 5 (ตอนนี้คืน `next(e)`; ต้องมาก่อนเช็ค `agentId` เพราะ handoff ต้องปฏิเสธ subagent เอง) · `agentId` มีค่า → `next(e)` · ที่เหลือ: `r = await next(e)` → ถ้า `r.deny` คืน `r` → `observe` → push `tokens` ลง `history` (ตัดเหลือ `BURN_CALLS + 1`) → แนบ `warningFor` ถ้ามี ลงทะเบียนด้วย `.catch(($, e, next) => e.tool === TOOL ? { result: MSG.saveFailed } : next(e))` (ผลไม่หาย tool ไม่รันซ้ำ และ handoff ที่พังกลางทางได้คำตอบเสมอ ไม่ตกไปเป็น "no hook answers")
- `prompt.submit`: บรรทัดแรก `if (e.origin.kind === 'plugin' && e.origin.name === $.plugin.name) return next(e)` แล้ว `observe` + แนบ `warningFor` เข้า `e.context` (dedupe ชุดเดียวกับ tool.call) `.catch(($, e, next) => next(e))`

- [ ] **Step 1: เขียน harness + test ที่ fail** `hooks/register.test.ts` harness ใช้ทั้งไฟล์ (Task 5–6 ใช้ต่อ):

```ts
import { test, expect, mock } from 'claude-code/testing'
import type { On } from 'claude-code'
import { MSG, TOOL } from './logic'

const T0 = Date.UTC(2026, 9, 17, 12, 0, 0) // 19:00:00 Bangkok

function world(on: On) {
  const w = {
    tokens: 450_000 as number | undefined, sid: 'sid-1', startedAt: 1,
    rate: [{ kind: 'five_hour', percentUsed: 10 }, { kind: 'seven_day', percentUsed: 10 }],
    agents: [] as { id: string; status: string }[],
    files: new Map<string, string>(), commands: [] as string[], submits: [] as string[], notes: [] as string[],
    toolsRan: [] as string[], git: true, clear: 'works' as 'works' | 'noop' | 'reject', submit: 'ok' as 'ok' | 'drop',
    holdWrite: 0, holdClear: 0, holdList: 0, usageThrows: false, notifyThrows: false, writeThrows: false,
  }
  const clock = mock.clock(on, { now: T0 })
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('tool.register', async () => ({ value: {} }))
  on('session.usage', async () => {
    if (w.usageThrows) throw new Error('usage')
    return { value: { startedAt: w.startedAt, context: { tokens: w.tokens, window: 1_000_000 }, rateLimits: w.rate } }
  })
  on('session.id', async () => ({ value: w.sid }))
  on('agent.list', async () => { if (w.holdList) await clock.sleep(w.holdList); return { value: w.agents } })
  on('process.run', async () => ({ value: w.git
    ? { stdout: '/repo/.git\n', stderr: '', exitCode: 0 }
    : { stdout: '', stderr: 'fatal: not a git repository', exitCode: 128 } }))
  on('fs.exists', async (_$, e) => ({ value: w.files.has(e.path) }))
  on('fs.write', async (_$, e) => {
    if (w.holdWrite) await clock.sleep(w.holdWrite)
    if (w.writeThrows) throw new Error('EACCES')
    w.files.set(e.path, e.text)
    return { value: undefined }
  })
  on('command.run', async (_$, e) => {
    w.commands.push(e.command)
    if (w.holdClear) await clock.sleep(w.holdClear)
    if (w.clear === 'reject') throw new Error('clear failed')
    if (w.clear === 'works') { w.sid += '+'; w.startedAt += 1; w.tokens = 20_000 }
    return {}
  })
  on('ui.notify', async (_$, e) => {
    w.notes.push(e.text)
    if (w.notifyThrows) throw new Error('notify')
    return { value: { isSent: true, channel: 'test' } }
  })
  on('prompt.submit', async (_$, e) => {
    if (e.origin.kind !== 'plugin') return { text: e.text, context: e.context }
    w.submits.push(e.text)
    return w.submit === 'drop' ? { drop: 'test' } : { text: e.text }
  })
  on('tool.call', async (_$, e) => { w.toolsRan.push(e.tool); return e.tool === 'Denied' ? { deny: 'no' } : { result: `ran ${e.tool}` } })
  on('turn.start', async (_$, e) => ({ turnId: e.turnId }))
  on('turn.step', async function* (_$, e) {
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  on('turn.complete', async () => ({ text: '' }))
  return { w, clock }
}

// drivers: the test plays the engine
const step = async ($, turnId: string, agentId?: string) => { for await (const _ of $.turn.step({ turnId, index: 0, model: 'test', agentId })) {} }
const user = ($, text: string, kind = 'composer') => $.prompt.submit({ text, origin: { kind }, wait: false })
const done = ($, turnId: string, isAborted = false) =>
  $.turn.complete({ turnId, answer: '', durationMs: 1, isAborted, reason: isAborted ? 'aborted' : 'answer' })
const bash = ($, agentId?: string) => $.tool.call({ tool: 'Bash', input: { command: 'ls' }, agentId })
const handoff = ($, mode = 'auto', content = '# งาน\nขั้นต่อไป: X') => $.tool.call({ tool: TOOL, content, mode, reason: 'ทดสอบ' })
const ctx = (r: { context?: readonly string[] }) => (r.context ?? []).join('\n')
```

(ใส่ type/`as` ให้ `tsc` ผ่านตามที่ types บังคับ) test ของ Task นี้:

```ts
test('warns at 400K, again at +25K, hard at 500K', async ($, on) => {
  const { w } = world(on)
  w.tokens = 410_000; expect(ctx(await bash($))).toContain(MSG.soft)
  w.tokens = 420_000; expect(ctx(await bash($))).toBe('')
  w.tokens = 436_000; expect(ctx(await bash($))).toContain(MSG.soft)
  w.tokens = 501_000; expect(ctx(await bash($))).toContain(MSG.hard)
})

test('denied result gets no warning, the next result does', async ($, on) => {
  const { w } = world(on)
  w.tokens = 410_000
  expect((await $.tool.call({ tool: 'Denied', input: {} })).context).toBeUndefined()
  expect(ctx(await bash($))).toContain(MSG.soft)
})

test('prompts share the dedupe', async ($, on) => {
  const { w } = world(on)
  w.tokens = 410_000; expect(ctx(await user($, 'hi'))).toContain(MSG.soft)
  w.tokens = 415_000; expect(ctx(await bash($))).toBe('')
})

test('quiet after startedAt changes until a reading below 400K', async ($, on) => {
  const { w } = world(on)
  w.tokens = 410_000; await bash($)
  w.startedAt = 2; w.tokens = 450_000; expect(ctx(await bash($))).toBe('')
  w.tokens = 30_000; await bash($)
  w.tokens = 410_000; expect(ctx(await bash($))).toContain(MSG.soft)
})

test('subagent calls are not watched', async ($, on) => {
  const { w } = world(on)
  w.tokens = 450_000; expect(ctx(await bash($, 'agent-1'))).toBe('')
})

test('usage failure keeps the tool result and runs the tool once', async ($, on) => {
  const { w } = world(on)
  w.usageThrows = true
  expect((await bash($)).result).toBe('ran Bash')
  expect(w.toolsRan).toEqual(['Bash'])
})
```

- [ ] **Step 2:** `claude plugin test ./plugins/kit-checkpoint` → test ใหม่ FAIL
- [ ] **Step 3: เขียน hooks + `observe` + `warningFor`** ตาม Interfaces
- [ ] **Step 4:** `claude plugin test ./plugins/kit-checkpoint` → PASS ทั้งหมด, `claude plugin validate ./plugins/kit-checkpoint` ผ่าน (เช็คว่า `gen` ตรงกับ contract)
- [ ] **Step 5: Commit** `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: watch context and warn at 400K/500K"`

---

### Task 5: tool `handoff` และการยกเลิก (spec ข้อ 3 จนถึง "กิจกรรมอื่นที่เกิดขึ้น" ตอน `pending`)

**Files:** Modify `plugins/kit-checkpoint/hooks/register.ts`, `hooks/register.test.ts`

**Interfaces:**
- Consumes: `refusal`, `handoffPath`, `handoffDoc`, `MSG`, `BUSY`, `TOOL_NAME`, `TOOL`, `CallFacts` (Task 3); `observe`, `s`, `gen` (Task 4)
- Produces:
  - `type Rec = { phase: 'pending' | 'committed'; path: string; content: string; gen: number; mode: 'auto' | 'wait'; reason: string; turnId: string | undefined; userHasHandoff: boolean; userRepliedAfterCommit: boolean; turnBeforeClear: boolean; overwritten: string[]; cleared: boolean }` (record คือ object identity ไม่ต้องมี id)
  - `s.rec: Rec | null` (`null` = `none`), `s.tools`, `s.prompts`, `s.turnId`, `s.aborted: Set<string>`, `s.note: string | null`
  - `function cancel($: EngineInterface): void` (sync): ถ้า `s.rec?.phase === 'pending'` → `s.note = MSG.stale(path)`, `s.rec = null`, notify path แบบไม่ await
  - `async function registerTool($: EngineInterface): Promise<void>` (Task 6 เรียกซ้ำ)
  - `async function handoffCall($, e, next): Promise<ToolCallResult>`
  - `function notify($, text: string): Promise<unknown>` = `$.ui.notify(text, { title: 'kit-checkpoint' }).catch(() => {})`

Tool spec (`registerTool` เรียกใน `session.start` แล้ว `next(e)`): `name: TOOL_NAME`, `isDeferred: false`, `inputSchema` มี `content` (string), `mode` (enum `auto|wait`), `reason` (string) required ครบ description ภาษาไทยบอก: เรียกเฉพาะหลังได้คำเตือน `[kit-checkpoint]` · ต้องเป็น tool call เดียวของข้อความ · เรียกแล้วจบ turn ทันที · content มีหัวข้อ เป้าหมาย / ทำเสร็จแล้ว / ค้างอยู่ตรงไหน / ตัดสินใจอะไรไปแล้วและเพราะอะไร / ไฟล์ที่เกี่ยวข้อง / ขั้นต่อไป · `auto` = ขั้นต่อไปชัดใน plan ไปต่อเองได้, `wait` = ต้องให้ผู้ใช้ตัดสินใจ

`handoffCall` (spec ข้อ 3 ขั้น 1–5):
1. `observe` (ถ้า throw ให้ถือว่า `tokens` ไม่มี) + `$.agent.list()` นับ status ใน `BUSY` (throw → นับเป็น 1) → `refusal(facts)` ไม่ใช่ `null` → `{ result: msg }`
2. `mode = e.mode === 'auto' ? 'auto' : 'wait'`, `reason` = string หรือ `''`, `g = (await read($, gen)) + 1` · git-dir จาก `$.process.run` (`exitCode !== 0` หรือ throw → `{ result: MSG.saveFailed }`) · หา `n` แรกที่ `!(await $.fs.exists(path))` · `$.fs.write(path, handoffDoc(...))` (throw → `MSG.saveFailed`)
3. เช็คซ้ำแบบ sync: `s.prompts > 0` → `MSG.promptArrived` · `s.tools > 0` → `MSG.siblings` · `s.rec !== null` → `MSG.already` · `next.signal.aborted || s.aborted.has(s.turnId)` → `MSG.promptArrived` (ไฟล์เก็บไว้)
4. `s.rec = { phase: 'pending', ..., turnId: s.turnId }`, `s.note = null` (note ของ record เก่าห้ามรั่วไปบทสนทนาใหม่) แล้ว `void notify($, <บันทึก handoff ไว้ที่ path>)`
5. `{ result: MSG.saved(path) }` (ไม่แนบคำเตือน)

hook ที่เพิ่ม/แก้ (ทุกตัวทำส่วน sync ก่อน `await` แรก):
- `turn.step` (generator) ของ session หลัก: `s.tools = 0; s.prompts = 0; s.turnId = e.turnId` แล้ว `return yield* next(e)`
- `tool.call` ที่ไม่ใช่ handoff ของ session หลัก: `s.tools++` และ `cancel($)` ก่อน `next` ตอนแนบ context ให้ดึง `s.note` มาแนบก่อนคำเตือน (แนบแม้ไม่มีคำเตือน) แล้วล้าง
- `prompt.submit` (หลังบรรทัดกรอง origin): `s.prompts++`, `cancel($)` ดึง `s.note` แนบเข้า `e.context`
- `session.append` ของ session หลักที่ `door === 'delivery'`: `s.prompts++`, `cancel($)`, `next(e)`
- `turn.start` ของ session หลัก: ถ้า `s.rec && s.rec.turnId !== e.turnId` → `cancel($)` (Task 6 เพิ่มกรณี committed)
- `turn.complete` ของ session หลัก: `isAborted` → `s.aborted.add(e.turnId)`, `cancel($)` (Task 6 เพิ่มการ finalize)

- [ ] **Step 1: เขียน test ที่ fail** (ใช้ harness Task 4 ไฟล์ handoff ของ T0 คือ `/repo/.git/kit-handoff/20261017-190000-g1.md`)

```ts
const P1 = '/repo/.git/kit-handoff/20261017-190000-g1.md'

test('registers the tool up front', async ($, on) => {
  const specs: unknown[] = []
  on('tool.register', async (_$, e) => { specs.push(e); return { value: {} } }) // ลงทะเบียนก่อน world เพื่อให้เห็น call
  world(on)
  await $.session.start({ cwd: '/repo', surface: null, isInteractive: true })
  expect(specs).toEqual([expect.objectContaining({ name: 'handoff', isDeferred: false })])
})

test('saves the file and answers', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1')
  const r = await handoff($)
  expect(r.result).toBe(MSG.saved(P1))
  expect(r.context).toBeUndefined() // ไม่แนบคำเตือนกับผลของ handoff
  expect(w.files.get(P1)).toContain('generation: 1\nmode: auto\nreason: "ทดสอบ"')
  await clock.settle() // notify ยิงแบบไม่ await
  expect(w.notes.some(n => n.includes(P1))).toBe(true)
})

test('never overwrites an existing file', async ($, on) => {
  const { w } = world(on)
  w.files.set(P1, 'old')
  await step($, 'T1')
  expect((await handoff($)).result).toBe(MSG.saved(P1.replace('.md', '-2.md')))
  expect(w.files.get(P1)).toBe('old')
})

test('refusals write nothing', async ($, on) => {
  const { w } = world(on)
  await step($, 'T1')
  w.tokens = 300_000; expect((await handoff($)).result).toBe(MSG.notYet)
  w.tokens = 450_000
  expect((await $.tool.call({ tool: TOOL, content: 'x', mode: 'auto', reason: '', agentId: 'a1' })).result).toBe(MSG.fromSubagent)
  w.agents = [{ id: 'a1', status: 'running' }]; expect((await handoff($)).result).toBe(MSG.agentsBusy)
  w.agents = []
  await bash($); expect((await handoff($)).result).toBe(MSG.siblings) // sibling ก่อน handoff ใน request เดียวกัน
  expect(w.files.size).toBe(0)
})

test('a prompt in the same request refuses', async ($, on) => {
  world(on)
  await step($, 'T1')
  await user($, 'เดี๋ยวก่อน')
  expect((await handoff($)).result).toBe(MSG.promptArrived)
})

test('a prompt while the file is being written refuses and keeps the file', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1')
  w.holdWrite = 10
  const call = handoff($)
  await clock.settle()
  await user($, 'เดี๋ยวก่อน')
  await clock.advance(10)
  expect((await call).result).toBe(MSG.promptArrived)
  expect(w.files.has(P1)).toBe(true)
})

test('second call while pending', async ($, on) => {
  world(on)
  await step($, 'T1'); await handoff($)
  await step($, 'T1'); expect((await handoff($)).result).toBe(MSG.already)
})

test('not a git repo, or the write fails: answer and never clear', async ($, on) => {
  const { w, clock } = world(on)
  w.git = false
  await step($, 'T1')
  expect((await handoff($)).result).toBe(MSG.saveFailed)
  w.git = true; w.writeThrows = true
  await step($, 'T1')
  expect((await handoff($)).result).toBe(MSG.saveFailed)
  await done($, 'T1'); await clock.settle()
  expect(w.commands).toEqual([])
})

test('a sibling that starts while the file is being written refuses', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1')
  w.holdWrite = 10
  const call = handoff($)
  await clock.settle()
  await bash($) // เช่น Agent ที่เริ่มระหว่างเขียนไฟล์ ตอนนั้นยังไม่มี record ให้ cancel
  await clock.advance(10)
  expect((await call).result).toBe(MSG.siblings)
})

test('own plugin prompts never cancel', async ($, on) => {
  world(on)
  await step($, 'T1'); await handoff($)
  await $.prompt.submit({ text: 'x', origin: { kind: 'plugin', name: 'kit-checkpoint' }, wait: false })
  expect((await handoff($)).result).toBe(MSG.already) // record ยัง pending อยู่
})

test('handoff with usage failure refuses', async ($, on) => {
  const { w } = world(on)
  w.usageThrows = true
  await step($, 'T1')
  expect((await handoff($)).result).toBe(MSG.notYet)
})

test('refuses right after a user clear', async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.startedAt = 2 // ผู้ใช้พิมพ์ /clear เอง ตัวเลขยังเป็นของเก่า
  await step($, 'T1')
  expect((await handoff($)).result).toBe(MSG.justCleared)
})

test('activity after the handoff marks it stale', async ($, on) => {
  const { w } = world(on)
  await step($, 'T1'); await handoff($)
  expect(ctx(await bash($))).toContain(MSG.stale(P1)) // sibling ที่รันหลัง handoff
  await step($, 'T2'); await handoff($) // P1 มีอยู่แล้ว ได้ชื่อ -2
  expect(ctx(await user($, 'แก้ตรงนี้'))).toContain(MSG.stale(P1.replace('.md', '-2.md')))
})
```

- [ ] **Step 2:** `claude plugin test ./plugins/kit-checkpoint` → test ใหม่ FAIL
- [ ] **Step 3: เขียน `handoffCall`, `registerTool`, `cancel`, `notify` และ hook ที่ระบุ**
- [ ] **Step 4:** `claude plugin test ./plugins/kit-checkpoint` → PASS ทั้งหมด
- [ ] **Step 5: Commit** `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: handoff tool, refusals and stale cancellation"`

---

### Task 6: finalize, กันชน, ข้อความเริ่มต้น, ตอน `committed`, รีเซ็ตตัวนับ (spec ข้อ 3 "ตอนจบ turn" + ข้อ 4–6)

**Files:** Modify `plugins/kit-checkpoint/hooks/register.ts`, `hooks/register.test.ts`

**Interfaces:**
- Consumes: `guard`, `pickLimits`, `startText`, `resetsGen`, `MSG`, `BUSY` (Task 3); `Rec`, `s`, `gen`, `cancel`, `registerTool`, `notify` (Task 5)
- Produces: `async function finalize($: EngineInterface, mine: Rec): Promise<void>`

`finalize` ทำตาม spec ข้อ 3 "ตอนจบ turn" ขั้น 1–8 ทุกขั้นหลัง `await` ทำต่อเฉพาะเมื่อ `s.rec === mine` และ `try/finally` ตั้ง `s.rec = null` เฉพาะเมื่อ `s.rec === mine` จุดที่ต้องตรงเป๊ะ:
- ขั้น 3: อ่าน `$.session.id()` + `startedAt` (usage ดิบ ไม่ผ่าน `observe`) → เช็ค `s.rec === mine` → `mine.phase = 'committed'; s.quiet = true` → เรียก `$.command.run({ command: 'clear' })` ทันทีโดยไม่มี `await` อื่นคั่น เมื่อ resolve หรือ reject ตั้ง `mine.cleared = true`
- ขั้น 4: อ่าน `$.session.id()` และ usage หลัง clear (`after`) ไม่สำเร็จ = reject หรือทั้ง id และ `startedAt` ไม่เปลี่ยน → `s.quiet = false`, notify พร้อม path, จบ (ห้าม submit)
- ขั้น 5: `update($, gen, () => mine.userRepliedAfterCommit ? 0 : mine.gen)` แล้ว `registerTool` ใน try/catch ของตัวเอง
- ขั้น 6: `guard(mine.mode, mine.gen, pickLimits(after.rateLimits, s.rate, await $.clock.now()))`
- ขั้น 7: `turnBeforeClear` → `startText(mine, { auto: false, blocked: MSG.overwrittenBlock }, mine.overwritten)` + notify · `userHasHandoff` → ไม่ submit · ไม่งั้น `startText(mine, verdict)` submit ด้วย `$.prompt.submit({ text })` (ไม่ใช้ `asUser`) reject หรือได้ `drop` → notify พร้อม path
- ขั้น 8: `void notify(...)` ว่าทำต่อเองหรือรอ (บอก reason หรือ blocked) ห้าม await เพื่อไม่ให้ `committed` ค้างเข้าไปใน turn แรกของบทสนทนาใหม่
- ทั้งตัวครอบ `catch`: notify พร้อม path และถ้ายังไม่ยืนยันว่า clear สำเร็จ ให้ `s.quiet = false`

hook ที่เพิ่ม:
- `turn.complete` ของ session หลัก ไม่ใช่ `isAborted`, `s.rec?.phase === 'pending'` และ `s.rec.turnId === e.turnId` → `const mine = s.rec; $.clock.after(0, () => finalize($, mine))`
- `prompt.submit` ตอน `s.rec?.phase === 'committed'` (sync ก่อน await): `userHasHandoff = true`, `resetsGen(kind)` → `userRepliedAfterCommit = true`, push `e.text` ลง `overwritten`, แนบ `MSG.committed(content)` (อ่าน usage ด้วย `observe($).catch(() => null)` เพื่อให้แนบได้เสมอแม้ usage พัง)
- `prompt.submit` ทุกตัวที่ `resetsGen(kind)` ไม่ว่าสถานะไหน → `update($, gen, () => 0)` (หลังส่วน sync)
- `turn.start` ตอน `committed` และ `!s.rec.cleared` และ turnId ไม่ตรง → `turnBeforeClear = true`

- [ ] **Step 1: เขียน test ที่ fail** เพิ่ม helper ในไฟล์ test:

```ts
// one full handoff cycle in turn `t`: high context, handoff, end of turn, timers run
async function cycle($, w, clock, t: string, mode = 'auto') {
  w.tokens = 30_000; await bash($) // reading below 400K lifts the post-clear quiet
  w.tokens = 450_000
  await step($, t)
  const r = await handoff($, mode)
  await clock.settle(); w.notes.length = 0 // notify ตอนบันทึกมี path อยู่แล้ว ล้างทิ้งให้ test เห็นเฉพาะ notify ของ finalize
  await done($, t)
  await clock.settle()
  return r
}
```

```ts
test('auto: clear then framed start message', async ($, on) => {
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1')
  expect(w.commands).toEqual(['clear'])
  expect(w.submits).toHaveLength(1)
  expect(w.submits[0].startsWith(`[kit-checkpoint #1] ${P1}\n\n# งาน`)).toBe(true)
  expect(w.submits[0]).toContain(MSG.goOn)
})

test('wait mode asks the user', async ($, on) => {
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1', 'wait')
  expect(w.submits[0]).toContain(MSG.stay('ทดสอบ'))
})

test('fourth generation waits; a user reply resets it', async ($, on) => {
  const { w, clock } = world(on)
  for (const t of ['T1', 'T2', 'T3']) await cycle($, w, clock, t)
  await cycle($, w, clock, 'T4')
  expect(w.submits.map(x => x.slice(0, 18))).toEqual(['[kit-checkpoint #1', '[kit-checkpoint #2', '[kit-checkpoint #3', '[kit-checkpoint #4'])
  expect(w.submits[3]).not.toContain(MSG.goOn)
  await user($, 'ไปต่อ')
  await cycle($, w, clock, 'T5')
  expect(w.submits[4].startsWith('[kit-checkpoint #1]')).toBe(true)
})

test('task notifications do not reset the generation', async ($, on) => {
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1')
  await user($, '<task-notification>', 'task-notification')
  await cycle($, w, clock, 'T2')
  expect(w.submits[1].startsWith('[kit-checkpoint #2]')).toBe(true)
})

test('rate limits: missing waits, fresh cache passes, stale cache waits', async ($, on) => {
  const { w, clock } = world(on)
  w.rate = [] // ไม่มีตัวเลขและไม่มี cache
  await cycle($, w, clock, 'T1'); expect(w.submits[0]).not.toContain(MSG.goOn)
  w.rate = [{ kind: 'five_hour', percentUsed: 10 }, { kind: 'seven_day', percentUsed: 10 }]
  await bash($) // cache the limits now
  w.rate = []
  await cycle($, w, clock, 'T2'); expect(w.submits[1]).toContain(MSG.goOn)
  await clock.advance(16 * 60_000)
  await cycle($, w, clock, 'T3'); expect(w.submits[2]).not.toContain(MSG.goOn)
})

test('aborted turn cancels and never clears', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1'); await handoff($)
  await done($, 'T1', true); await clock.settle()
  expect(w.commands).toEqual([])
  expect(ctx(await bash($))).toContain(MSG.stale(P1)) // note ที่ค้างไว้มากับผลถัดไป
})

test('a prompt while finalize is checking cancels before the clear', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1'); await handoff($)
  w.holdList = 10
  await done($, 'T1'); await clock.settle() // finalize waits on agent.list
  await user($, 'เดี๋ยว')
  await clock.advance(10)
  expect(w.commands).toEqual([])
})

test('delivery and a foreign turn cancel', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1'); await handoff($)
  await $.session.append({ door: 'delivery', message: { type: 'user', message: { role: 'user', content: 'x' } } })
  await done($, 'T1'); await clock.settle()
  await step($, 'T2'); await handoff($)
  await $.turn.start({ text: 'อีกเรื่อง', turnId: 'T3' })
  await done($, 'T2'); await clock.settle()
  expect(w.commands).toEqual([])
})

test('busy subagent at finalize cancels', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1'); await handoff($)
  await clock.settle(); w.notes.length = 0
  w.agents = [{ id: 'a1', status: 'running' }]
  await done($, 'T1'); await clock.settle()
  expect(w.commands).toEqual([])
  expect(w.notes.some(n => n.includes(P1))).toBe(true)
})

test('clear that changes nothing: no submit', async ($, on) => {
  const { w, clock } = world(on)
  w.clear = 'noop'
  await cycle($, w, clock, 'T1')
  expect(w.submits).toEqual([])
  expect(w.notes.some(n => n.includes(P1))).toBe(true)
})

test('clear rejects: no submit, next handoff accepted', async ($, on) => {
  const { w, clock } = world(on)
  w.clear = 'reject'
  await cycle($, w, clock, 'T1')
  expect(w.submits).toEqual([])
  expect(w.notes.some(n => n.includes(P1))).toBe(true)
  // context ยังอยู่ ~450K ไม่มีค่าต่ำกว่า 400K มาช่วยปลด quiet: finalize ต้องปลดเอง
  w.clear = 'works'
  expect(ctx(await bash($))).toContain(MSG.soft)
  await step($, 'T2')
  expect((await handoff($)).result).toContain('บันทึก handoff ไว้ที่')
  await done($, 'T2'); await clock.settle()
  expect(w.submits).toHaveLength(1)
})

test('a prompt while committed gets the handoff and suppresses the start message', async ($, on) => {
  const { w, clock } = world(on)
  w.holdClear = 10
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle() // finalize is now waiting on command.run
  expect(ctx(await user($, 'ถามหน่อย'))).toContain(MSG.committed('# งาน\nขั้นต่อไป: X'))
  await clock.advance(10)
  expect(w.submits).toEqual([])
  await cycle($, w, clock, 'T2') // userRepliedAfterCommit → gen 0 → next is #1
  expect(w.submits[0].startsWith('[kit-checkpoint #1]')).toBe(true)
})

test('a turn that slips in before the clear gets quoted in a wait message', async ($, on) => {
  const { w, clock } = world(on)
  w.holdClear = 10
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle()
  await user($, 'แก้ตรงนี้ด้วย') // engine ยิง prompt.submit ก่อน turn.start
  await $.turn.start({ text: 'แก้ตรงนี้ด้วย', turnId: 'T9' })
  await clock.advance(10)
  expect(w.submits).toHaveLength(1)
  expect(w.submits[0]).toContain('> แก้ตรงนี้ด้วย')
  expect(w.submits[0]).not.toContain(MSG.goOn)
})

test('dropped start message: state returns to none', async ($, on) => {
  const { w, clock } = world(on)
  w.submit = 'drop'
  await cycle($, w, clock, 'T1')
  expect(w.notes.some(n => n.includes(P1))).toBe(true)
  w.submit = 'ok'
  await clock.advance(1000)
  expect((await cycle($, w, clock, 'T2')).result).toContain('บันทึก handoff ไว้ที่')
})

test('an old finalize never touches a newer record', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1'); await handoff($); await done($, 'T1') // finalize(A) scheduled, not run yet
  await user($, 'เดี๋ยว') // cancels A (ห้าม advance ตรงนี้ ไม่งั้น finalize(A) รันก่อน B เกิด)
  await step($, 'T2'); const b = await handoff($) // B pending
  await clock.settle() // finalize(A) runs and must bail
  expect(w.commands).toEqual([])
  await done($, 'T2'); await clock.settle()
  expect(w.commands).toEqual(['clear'])
  expect(w.submits[0]).toContain(b.result.match(/\/repo\S+\.md/)![0])
})

test('notify failures never stop the flow', async ($, on) => {
  const { w, clock } = world(on)
  w.notifyThrows = true
  expect((await cycle($, w, clock, 'T1')).result).toBe(MSG.saved(P1))
  expect(w.commands).toEqual(['clear'])
  expect(w.submits).toHaveLength(1)
  w.tokens = 30_000; await bash($); w.tokens = 450_000
  await step($, 'T2'); await handoff($)
  w.agents = [{ id: 'a1', status: 'running' }] // finalize ยกเลิก: notify แล้ว return
  await done($, 'T2'); await clock.settle()
  w.agents = []
  expect((await cycle($, w, clock, 'T3')).result).toContain('บันทึก handoff ไว้ที่') // สถานะกลับเป็น none
  expect(w.commands).toEqual(['clear', 'clear'])
})
```

- [ ] **Step 2:** `claude plugin test ./plugins/kit-checkpoint` → test ใหม่ FAIL
- [ ] **Step 3: เขียน `finalize` และ hook ที่ระบุ**
- [ ] **Step 4:** `claude plugin test ./plugins/kit-checkpoint` → PASS ทั้งหมด, `claude plugin validate ./plugins/kit-checkpoint` ผ่าน
- [ ] **Step 5: Commit** `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: clear, guard and start message"`

---

### Task 7: ติดตั้งผ่าน marketplace + README + type-check

**Files:** Modify `.claude-plugin/marketplace.json`, `README.md`

- [ ] **Step 1: marketplace entry** ต่อจาก `kit-update`: `{ "name": "kit-checkpoint", "source": "./plugins/kit-checkpoint", "description": "<ไทย บรรทัดเดียว: เตือน Claude ตอน context เกิน 400K/500K ให้เขียน handoff แล้ว clear และทำงานต่อเอง>" }`
- [ ] **Step 2: README** เพิ่ม `/plugin install kit-checkpoint@phimee-and-kit-mods` ในหัว "ติดตั้ง" และ section `### kit-checkpoint` (ไทย) บอก: ทำอะไร (400K soft, 500K hard, handoff → `.git/kit-handoff/` → `/clear` → ส่ง handoff ต่อ) · ใช้กับ model window 1M (window 200K ไม่มีวันถึงเกณฑ์) · ทำต่อเองได้สูงสุด 3 รอบติดกันหลังข้อความล่าสุดของผู้ใช้ และต้องมีตัวเลข 5 ชม. < 90%, 7 วัน < 85% · ไฟล์ของ worktree หายไปพร้อม `git worktree remove` · `/clear` อาจหยุด task ที่ mod มองไม่เห็น (agent ของ Workflow, Bash background, Monitor) ก่อนเรียก handoff ควรรอให้จบ
- [ ] **Step 3: type-check** โหลด mod หนึ่งครั้งให้ engine เขียน types (`claude --plugin-dir ./plugins/kit-checkpoint -p 'ok'`) แล้ว `tsc -p ./plugins/kit-checkpoint` → ไม่มี error (แก้ type ใน test/harness ตามที่ฟ้อง) ถ้า `-p` ไม่เขียน `.claude-plugin/types/` ให้ใช้ `tsconfig.json` จาก header ของ `claude-code.d.ts` ที่ skill `plugin-authoring` ชี้ให้ วางไว้นอกโฟลเดอร์ mod
- [ ] **Step 4:** `claude plugin validate ./plugins/kit-checkpoint` และ `claude plugin test ./plugins/kit-checkpoint` → ผ่าน
- [ ] **Step 5: Commit** `git add .claude-plugin/marketplace.json README.md plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: marketplace entry and README"`

---

### Task 8: ลองของจริงกับผู้ใช้ (spec "วิธีทดสอบ" ข้อ 3 + "ต้องเช็คระหว่างทำ")

ต้องมีผู้ใช้ช่วยพิมพ์/กด Esc ทำใน terminal แยกด้วย `claude --plugin-dir ./plugins/kit-checkpoint` แบบเดียวกับ spike

- [ ] **Step 1: ลดเกณฑ์ชั่วคราว** ใน `logic.ts` เช่น `SOFT = 60_000`, `HARD = 80_000`, `STEP = 5_000` (ห้าม commit ค่านี้) และเพิ่ม log ชั่วคราวของ `e.origin` ใน `prompt.submit` ลงไฟล์ใน scratchpad
- [ ] **Step 2: ไล่ checklist** จด ผ่าน/ไม่ผ่าน ทีละข้อ:
  - เตือน → handoff → ไฟล์ → clear → ข้อความเริ่มต้น → ทำต่อ (auto) และ → รอ (wait)
  - รุ่นที่ 4 รอ · rateLimits ว่างรอ · โฟลเดอร์ที่ไม่ใช่ git repo ไม่ clear
  - handoff พร้อม Agent ในข้อความเดียว ทั้ง Agent มาก่อนและหลัง: รายงานของ subagent ต้องไม่หาย
  - notification เข้ามาระหว่าง turn ของ handoff → ยกเลิก
  - พิมพ์ระหว่าง Claude เขียน handoff, พิมพ์หลัง handoff, กด Esc, พิมพ์ระหว่างกำลัง clear → ไม่มีอะไรหาย (ดูลำดับคิวจริง)
  - ctrl+x enter (`wait: true`) ระหว่าง turn ของ handoff
  - รันใน linked worktree หนึ่งรอบ
  - origin ของข้อความที่พิมพ์จากมือถือผ่าน Orca (จาก log)
  - `/clear` หยุด Bash background / Monitor / agent ของ Workflow ไหม, teammate ที่ `idle` รอด `/clear` ไหม
  - `$.ui.notify` ไปถึงมือถือผ่าน Orca ไหม
- [ ] **Step 3: แก้ตามผล** (แต่ละข้อมี test ใน `register.test.ts` ก่อนแก้):
  - teammate `idle` ไม่รอด → เพิ่ม `'idle'` ใน `BUSY`
  - ctrl+x enter ถูกเก็บไว้จนจบ turn → เพิ่มเงื่อนไขปฏิเสธเมื่อเห็น `prompt.submit` ที่ `wait: true` ใน turn นี้ ด้วย `'จบ turn ไปก่อน ไม่ต้อง handoff ข้อความที่รอคิวจะเข้ามา'`
  - origin จากมือถือเป็น `unclassified` → บันทึกใน README (ตัวนับจะไม่รีเซ็ต auto หยุดหลัง 3 รอบ)
- [ ] **Step 4: คืนเกณฑ์จริง ลบ log ชั่วคราว** `git diff plugins/kit-checkpoint/hooks/logic.ts` ต้องไม่มีค่าที่ลดไว้ แล้ว `claude plugin test ./plugins/kit-checkpoint` → PASS
- [ ] **Step 5: Commit** (ถ้ามีการแก้) `git add plugins/kit-checkpoint && git commit -m "kit-checkpoint 0.1.0: fixes from live trial"` แล้วสรุปผล checklist ให้ผู้ใช้

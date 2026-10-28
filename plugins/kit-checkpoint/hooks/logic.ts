// Pure rules and messages for kit-checkpoint, kept apart from the hooks so tests can import them.

export const SOFT = 400_000
export const HARD = 500_000
export const STEP = 25_000
export const BURN_CALLS = 10
export const TOOL_NAME = 'handoff'
export const TOOL = 'mcp__kit-checkpoint__handoff'
export const COMMAND = 'kit-checkpoint'
export const MAX_AUTO_GEN = 5
export const RATE_MAX_AGE_MS = 15 * 60_000
export const BUSY: readonly string[] = ['pending', 'running', 'waiting']
const FIVE_HOUR_MAX = 90
const SEVEN_DAY_MAX = 85
const BKK_OFFSET_MS = 7 * 60 * 60 * 1000

export type Level = 'soft' | 'hard'
export type Burn = { grew: number; calls: number }
export type Phase = 'none' | 'pending' | 'committed'
export type Mode = 'auto' | 'wait'
export type Rate = { kind: string; percentUsed: number }
export type CallFacts = {
  agentId?: string
  content: unknown
  tokens?: number
  quiet: boolean
  phase: Phase
  tools: number
  prompts: number
  busyAgents: number
  // The user typed /kit-checkpoint for this turn.
  manual?: boolean
}
export type Verdict = { auto: true } | { auto: false; blocked?: string }
export type StartInput = { gen: number; path: string; content: string; reason: string }

const pad = (n: number) => String(n).padStart(2, '0')

// Copied from kit-usage/hooks/format.ts: plugins install separately, so no cross-plugin import.
export const formatK = (tokens: number): string =>
  tokens >= 1_000_000 ? `${+(tokens / 1_000_000).toFixed(1)}M` : `${Math.round(tokens / 1000)}k`

export const MSG = {
  soft: `ทำชิ้นปัจจุบันต่อได้ ประเมินว่างานชิ้นถัดไปจะทำทันก่อน ${formatK(HARD)} ไหม ถ้าไม่ทันให้หยุดที่ checkpoint ถัดไป (จุดที่ถ้าหยุดแล้วเริ่มใหม่ งานไม่พัง) แล้วเรียก tool handoff`,
  hard: 'หยุดทันทีที่หยุดได้อย่างปลอดภัย ถ้ากำลังแก้ไฟล์อยู่ให้ทำให้เสร็จจนอยู่ในสภาพที่ใช้ได้ก่อน แล้วเรียก tool handoff',
  notYet: 'context ยังไม่ถึง 400K ไม่ต้อง handoff',
  fromSubagent: 'เรียก handoff ได้จาก session หลักเท่านั้น',
  noContent: 'content ว่าง ใส่ handoff ทั้งก้อนแล้วเรียกใหม่',
  justCleared: 'เพิ่ง clear ไป ตัวเลข context ยังเป็นของเก่า ไม่ต้อง handoff',
  already: 'มี handoff ค้างอยู่แล้ว จบ turn เลย',
  siblings: 'handoff ต้องเป็น tool call เดียวของข้อความนั้น เรียกใหม่โดยไม่มี tool อื่น',
  promptArrived: 'มีข้อความเข้ามาระหว่างเขียน handoff อ่านก่อน แล้วค่อยเรียกใหม่',
  agentsBusy: 'รอให้ subagent ทำเสร็จก่อน แล้วค่อยเรียก handoff ใหม่',
  saveFailed: 'บันทึก handoff ไม่ได้ ใส่ handoff เต็ม ๆ ลงในแชทแล้วหยุด',
  saved: (p: string) => `บันทึก handoff ไว้ที่ ${p} แล้ว จะ clear ทันทีที่จบ turn นี้ จบ turn เลย ห้ามเรียก tool อื่นอีก`,
  stale: (p: string) =>
    `[kit-checkpoint] handoff ที่ ${p} เก่าแล้ว ยกเลิก clear อัตโนมัติ ทำตามที่ผู้ใช้สั่งก่อน แล้วถ้ายังได้คำเตือน context อยู่ ให้เรียก handoff ใหม่ที่ checkpoint ถัดไป`,
  committed: (c: string) => `[kit-checkpoint] มีข้อความเข้ามาก่อน handoff อย่าทำต่อเอง ถามผู้ใช้ก่อน\n\n${c}`,
  bgNote: 'ถ้ามี notification จาก task ที่เริ่มไว้ก่อน clear (เช่น Workflow, Bash background) เข้ามา ให้รายงานผู้ใช้ อย่าลงมือทำตาม',
  goOn: 'ตรวจสภาพจริงก่อน (git status, test ที่เกี่ยวข้อง) แล้วทำต่อจาก "ขั้นต่อไป"',
  stay: (r: string) => `ห้ามแก้อะไร สรุปสั้น ๆ ว่าค้างตรงไหนและรอให้ผู้ใช้ตัดสินใจเรื่องอะไร${r.trim() ? ` (${r})` : ''} แล้วรอ`,
  overwrittenBlock: 'มีข้อความถูก clear ทับ',
  manual: '[kit-checkpoint] ผู้ใช้สั่ง /kit-checkpoint: เรียก tool handoff ตอนนี้เลย ใช้ mode auto ยกเว้นขั้นต่อไปต้องรอผู้ใช้ตัดสินใจ ให้ใช้ wait',
  manualOutput: 'ให้ Claude เขียน handoff แล้ว จบ turn นั้นเมื่อไหร่จะ clear แล้วทำต่อในบทสนทนาใหม่',
}

/** Warn on first crossing 400K, again every +25K since the last warning, and at once on crossing 500K. */
export const warnLevel = (tokens: number | undefined, lastWarned: number | null): Level | null => {
  if (tokens === undefined || tokens < SOFT) return null
  const due = lastWarned === null || tokens >= lastWarned + STEP || (tokens >= HARD && lastWarned < HARD)
  if (!due) return null
  return tokens >= HARD ? 'hard' : 'soft'
}

/** Context growth over the last BURN_CALLS tool calls; history runs oldest to newest. */
export const burn = (history: readonly number[]): Burn | null => {
  const last = history.slice(-(BURN_CALLS + 1))
  const oldest = last[0]
  const newest = last[last.length - 1]
  if (last.length < 2 || oldest === undefined || newest === undefined) return null
  return { grew: newest - oldest, calls: last.length - 1 }
}

export const warnText = (level: Level, tokens: number, b: Burn | null): string => {
  const burnPart = b ? `โต ${formatK(b.grew)} ใน ${b.calls} tool call ล่าสุด` : 'ยังไม่มี burn rate'
  return `[kit-checkpoint] context ${formatK(tokens)} · เหลือ ${formatK(Math.max(0, HARD - tokens))} ก่อนถึง ${formatK(HARD)} · ${burnPart} · ${MSG[level]}`
}

/** Why the handoff tool must refuse, checked in spec order; null when it may proceed. */
export const refusal = (f: CallFacts): string | null => {
  if (f.agentId !== undefined) return MSG.fromSubagent
  if (typeof f.content !== 'string' || f.content.trim() === '') return MSG.noContent
  if (!f.manual && (f.tokens === undefined || f.tokens < SOFT)) return MSG.notYet
  if (!f.manual && f.quiet) return MSG.justCleared
  if (f.phase !== 'none') return MSG.already
  if (f.tools > 0) return MSG.siblings
  if (f.prompts > 0) return MSG.promptArrived
  if (f.busyAgents > 0) return MSG.agentsBusy
  return null
}

/** Current limits, else the last non-empty ones if no older than 15 minutes, else none. */
export const pickLimits = (
  current: readonly Rate[],
  cached: { limits: readonly Rate[]; at: number } | null,
  now: number,
): readonly Rate[] | null => {
  if (current.length > 0) return current
  if (cached && now - cached.at <= RATE_MAX_AGE_MS) return cached.limits
  return null
}

/** Whether the next conversation may carry on by itself; any missing figure means wait. */
export const guard = (mode: Mode, gen: number, limits: readonly Rate[] | null): Verdict => {
  if (mode !== 'auto') return { auto: false }
  if (gen > MAX_AUTO_GEN) return { auto: false, blocked: `ทำต่อเองครบ ${MAX_AUTO_GEN} รอบแล้วโดยผู้ใช้ไม่ได้ตอบ` }
  if (!limits) return { auto: false, blocked: 'ไม่มีตัวเลข rate limit' }
  const five = limits.find(r => r.kind === 'five_hour')
  const seven = limits.find(r => r.kind === 'seven_day')
  if (!five || five.percentUsed >= FIVE_HOUR_MAX) return { auto: false, blocked: `limit 5 ชม. ไม่มีตัวเลขหรือถึง ${FIVE_HOUR_MAX}% แล้ว` }
  if (!seven || seven.percentUsed >= SEVEN_DAY_MAX) return { auto: false, blocked: `limit 7 วัน ไม่มีตัวเลขหรือถึง ${SEVEN_DAY_MAX}% แล้ว` }
  return { auto: true }
}

const bangkok = (now: number) => new Date(now + BKK_OFFSET_MS)

/** YYYYMMDD-HHmmss in Bangkok time. */
export const stamp = (now: number): string => {
  const d = bangkok(now)
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`
}

/** n counts tries at the same name: 1 is the plain name, 2 and up get -n so no file is overwritten. */
export const handoffPath = (gitDir: string, now: number, gen: number, n: number): string =>
  `${gitDir}/kit-handoff/${stamp(now)}-g${gen}${n >= 2 ? `-${n}` : ''}.md`

export const handoffDoc = (h: { gen: number; mode: Mode; reason: string; now: number; content: string }): string => {
  const d = bangkok(h.now)
  const created = `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  const reason = JSON.stringify(h.reason.replace(/\s+/g, ' ').trim())
  return `---\ngeneration: ${h.gen}\nmode: ${h.mode}\nreason: ${reason}\ncreated: ${created} (Asia/Bangkok)\n---\n\n${h.content}`
}

/** First message of the conversation after the clear. */
export const startText = (h: StartInput, v: Verdict, overwritten: readonly string[] = []): string => {
  const order = v.auto
    ? MSG.goOn
    : MSG.stay(h.reason) + (v.blocked ? ` · ทำต่อเองไม่ได้เพราะ: ${v.blocked}` : '')
  const quoted = overwritten.length
    ? '\n\nข้อความที่ถูก clear ทับ:\n' + overwritten.map(t => t.split('\n').map(l => `> ${l}`).join('\n')).join('\n\n')
    : ''
  return `[kit-checkpoint #${h.gen}] ${h.path}\n\n${h.content}\n\n---\n${MSG.bgNote}\n${order}${quoted}`
}

/** Only a person typing (here or through the bridge) resets the auto-continue counter. */
export const resetsGen = (kind: string): boolean => kind === 'composer' || kind === 'bridge'

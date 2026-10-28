import { atom, read, update } from 'claude-code'
import type { EngineInterface, Next, Register, SessionUsage, ToolCallInput, ToolCallResult } from 'claude-code'

import {
  BURN_CALLS, BUSY, COMMAND, MSG, SOFT, TOOL, TOOL_NAME,
  burn, guard, handoffDoc, handoffPath, pickLimits, refusal, resetsGen, startText, warnLevel, warnText,
} from './logic'
import type { Mode, Rate, Verdict } from './logic'

// The generation of the current conversation; kept in $.state so it outlives a reload.
const gen = atom({ plugin: 'kit-checkpoint', key: 'gen' } as const, 0)

/** One handoff on its way to a clear; compared by identity, so a stale finalize never touches a newer one. */
type Rec = {
  phase: 'pending' | 'committed'
  path: string
  content: string
  gen: number
  mode: Mode
  reason: string
  turnId: string | undefined
  userHasHandoff: boolean
  userRepliedAfterCommit: boolean
  turnBeforeClear: boolean
  overwritten: string[]
  cleared: boolean
}

const fresh = () => ({
  lastWarned: null as number | null,
  history: [] as number[],
  rate: null as { limits: Rate[]; at: number } | null,
  startedAt: null as number | null,
  // No warnings (and no handoff) until a reading below 400K: the figures may still be the old conversation's.
  quiet: false,
  rec: null as Rec | null,
  // Main-session tool calls and prompts since the last model request, and that request's turn.
  tools: 0,
  prompts: 0,
  turnId: undefined as string | undefined,
  // Recent aborted turns; a handoff call only ever asks about its own, so a few are enough.
  aborted: [] as string[],
  // A stale-handoff line waiting for the next result or prompt to carry it.
  note: null as string | null,
  // The user typed /kit-checkpoint, and the turn of the prompt it sent: that turn's handoff skips the 400K and just-cleared checks.
  asked: false,
  manualTurn: undefined as string | undefined,
})

// Module state; register() starts it over, as a reload starts the module's variables over.
let s = fresh()

const TOOL_SPEC = {
  name: TOOL_NAME,
  isDeferred: false,
  description:
    'บันทึก handoff ลง .git แล้ว /clear บทสนทนานี้ตอนจบ turn และส่ง handoff เป็นข้อความแรกของบทสนทนาใหม่ ' +
    'เรียกเฉพาะหลังได้คำเตือนหรือคำสั่ง [kit-checkpoint] เท่านั้น ต้องเป็น tool call เดียวของข้อความนั้น และเรียกแล้วให้จบ turn ทันที ' +
    'content ต้องมีหัวข้อ: เป้าหมาย / ทำเสร็จแล้ว / ค้างอยู่ตรงไหน / ตัดสินใจอะไรไปแล้วและเพราะอะไร / ไฟล์ที่เกี่ยวข้อง / ขั้นต่อไป ' +
    'agent ที่ตั้งชื่อไว้และรอข้อความอยู่จะหายไปตอน clear จึงห้ามเขียนให้บทสนทนาใหม่ส่ง SendMessage หา agent พวกนั้น',
  inputSchema: {
    type: 'object',
    properties: {
      content: { type: 'string', description: 'handoff ทั้งก้อน เป็น markdown' },
      mode: {
        type: 'string',
        enum: ['auto', 'wait'],
        description: 'auto = ขั้นต่อไปชัดอยู่ใน plan แล้ว ไปต่อเองได้ · wait = ต้องให้ผู้ใช้ตัดสินใจ',
      },
      reason: { type: 'string', description: 'บรรทัดเดียว ทำไมหยุด หรือทำไมต้องรอ' },
    },
    required: ['content', 'mode', 'reason'],
  },
}

async function registerTool($: EngineInterface): Promise<void> {
  await $.tool.register(TOOL_SPEC)
}

/** Something happened after the handoff was written: a pending one is stale, so no clear. */
function cancel(): void {
  if (s.rec?.phase !== 'pending') return
  s.note = MSG.stale(s.rec.path)
  s.rec = null
}

/** Takes the waiting stale line, if any, for whatever reaches the model next. */
function takeNote(): string[] {
  const note = s.note
  s.note = null
  return note ? [note] : []
}

async function observe($: EngineInterface): Promise<SessionUsage> {
  const u = await $.session.usage()
  if (s.startedAt !== null && u.startedAt !== s.startedAt) {
    s.quiet = true
    s.history = []
    s.lastWarned = null
  }
  s.startedAt = u.startedAt
  if (u.rateLimits.length > 0) s.rate = { limits: [...u.rateLimits], at: await $.clock.now() }
  if (u.context.tokens !== undefined && u.context.tokens < SOFT) {
    s.quiet = false
    s.lastWarned = null
  }
  return u
}

/** The warning due at this reading, if any; the caller sets lastWarned only once it is attached. */
function warningFor(tokens: number | undefined): string | null {
  if (s.quiet || tokens === undefined) return null
  const level = warnLevel(tokens, s.lastWarned)
  return level && warnText(level, tokens, burn(s.history))
}

async function handoffCall($: EngineInterface, e: ToolCallInput, next: Next<'tool.call'>): Promise<ToolCallResult> {
  const turnId = s.turnId
  const input = e as { content?: unknown; mode?: unknown; reason?: unknown }

  const tokens = await observe($).then(u => u.context.tokens, () => undefined)
  const busyAgents = await $.agent.list().then(
    list => list.filter(a => BUSY.includes(a.status)).length,
    () => 1,
  )
  const no = refusal({
    agentId: e.agentId,
    content: input.content,
    tokens,
    quiet: s.quiet,
    phase: s.rec?.phase ?? 'none',
    tools: s.tools,
    prompts: s.prompts,
    busyAgents,
    manual: turnId !== undefined && turnId === s.manualTurn,
  })
  if (no) return { result: no }

  const content = input.content as string
  const mode: Mode = input.mode === 'auto' ? 'auto' : 'wait'
  const reason = typeof input.reason === 'string' ? input.reason : ''
  const g = (await read($, gen)) + 1

  let path: string
  try {
    const git = await $.process.run(['git', 'rev-parse', '--absolute-git-dir'])
    if (git.exitCode !== 0) return { result: MSG.saveFailed }
    const dir = git.stdout.trim()
    const now = await $.clock.now()
    let n = 1
    while (await $.fs.exists(handoffPath(dir, now, g, n))) n++
    path = handoffPath(dir, now, g, n)
    await $.fs.write(path, handoffDoc({ gen: g, mode, reason, now, content }))
  } catch {
    return { result: MSG.saveFailed }
  }

  // Re-check with no await in between: anything that arrived while git ran or the file was written wins.
  if (s.prompts > 0) return { result: MSG.promptArrived }
  if (s.tools > 0) return { result: MSG.siblings }
  if (s.rec !== null) return { result: MSG.already }
  if (next.signal.aborted || (turnId !== undefined && s.aborted.includes(turnId))) return { result: MSG.promptArrived }

  s.rec = {
    phase: 'pending', path, content, gen: g, mode, reason, turnId,
    userHasHandoff: false, userRepliedAfterCommit: false, turnBeforeClear: false, overwritten: [], cleared: false,
  }
  s.note = null
  return { result: MSG.saved(path) }
}

/** At the end of the handoff's turn: clear, then send the handoff as the new conversation's first message. */
async function finalize($: EngineInterface, mine: Rec): Promise<void> {
  let confirmed = false
  try {
    // Identity is enough: turn.complete only schedules a finalize while the record is pending.
    if (s.rec !== mine) return

    const sid = await $.session.id()
    const startedAt = (await $.session.usage()).startedAt
    if (s.rec !== mine) return

    // Last await before the commit, so a subagent has the least time to start unseen.
    const busy = await $.agent.list().then(list => list.some(a => BUSY.includes(a.status)), () => true)
    if (s.rec !== mine) return
    if (busy) return cancel()

    // No await between committing and queueing the clear: nothing can slip in between.
    mine.phase = 'committed'
    s.quiet = true
    const ran = await $.command.run({ command: 'clear' }).then(() => true, () => false)
    mine.cleared = true

    // The conversation may already be gone: a failed read here must not stop the handoff from being sent.
    const sidAfter = await $.session.id().catch(() => sid)
    const after = await $.session.usage().catch(() => null)
    if (!ran || (sidAfter === sid && (after === null || after.startedAt === startedAt))) {
      s.quiet = false
      return
    }
    confirmed = true

    let verdict: Verdict
    try {
      await update($, gen, () => (mine.userRepliedAfterCommit ? 0 : mine.gen))
      verdict = guard(mine.mode, mine.gen, pickLimits(after?.rateLimits ?? [], s.rate, await $.clock.now()))
    } catch {
      // Without a saved generation the auto-continue cap cannot hold, so wait.
      verdict = { auto: false, blocked: 'บันทึกตัวนับรุ่นไม่ได้' }
    }
    try {
      await registerTool($)
    } catch {
      // The tool survives /clear anyway; registering again is only a safeguard.
    }

    if (mine.turnBeforeClear) {
      await $.prompt.submit({ text: startText(mine, { auto: false, blocked: MSG.overwrittenBlock }, mine.overwritten) })
      return
    }
    // The user's prompt already carries the handoff.
    if (mine.userHasHandoff) return

    await $.prompt.submit({ text: startText(mine, verdict) })
  } catch {
    if (!confirmed) s.quiet = false
  } finally {
    if (s.rec === mine) s.rec = null
  }
}

export const register: Register = on => {
  s = fresh()

  on('session.start', async ($, e, next) => {
    await registerTool($)
    await $.command.register({ name: COMMAND, description: 'เขียน handoff ลง .git แล้ว clear ตอนนี้เลย ไม่ต้องรอ context ถึง 400K' })
    return next(e)
  }).catch(($, e, next) => next(e))

  on('command.run', { command: COMMAND }, async $ => {
    s.asked = true
    // Submitting from inside command.run would wait on the turn this hook holds, so do it after.
    $.clock.after(0, () => void $.prompt.submit({ text: MSG.manual }).catch(() => {}))
    return { text: MSG.manualOutput }
  })

  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      s.tools = 0
      s.prompts = 0
      s.turnId = e.turnId
    }
    const r = yield* next(e)
    // A model response since startedAt changed means usage() now reads the new conversation.
    if (e.agentId === undefined && s.rec?.phase !== 'committed') s.quiet = false
    return r
  })

  on('turn.start', async ($, e, next) => {
    // Only the turn of the prompt /kit-checkpoint sent, not one queued ahead of it; the engine wraps a plugin's text.
    if (e.agentId === undefined && s.asked && e.text.includes(MSG.manual)) {
      s.asked = false
      s.manualTurn = e.turnId
    }
    if (e.agentId === undefined && s.rec && s.rec.turnId !== e.turnId) {
      // Someone else's turn got in before the clear ran: it will be cleared away, so quote it after.
      if (s.rec.phase === 'committed' && !s.rec.cleared) {
        s.rec.turnBeforeClear = true
        // Its prompt may have been queued before the commit, so prompt.submit never quoted it.
        if (e.text && !s.rec.overwritten.includes(e.text)) s.rec.overwritten.push(e.text)
      }
      cancel()
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && e.isAborted) {
      s.aborted = [...s.aborted, e.turnId].slice(-10)
      cancel()
    } else if (e.agentId === undefined && s.rec?.phase === 'pending' && s.rec.turnId === e.turnId) {
      const mine = s.rec
      $.clock.after(0, () => void finalize($, mine))
    }
    return next(e)
  })

  on('session.append', async ($, e, next) => {
    if (e.agentId === undefined && e.door === 'delivery') {
      s.prompts++
      cancel()
    }
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    if (e.tool === TOOL) return handoffCall($, e, next)
    if (e.agentId !== undefined) return next(e)

    s.tools++
    cancel()

    const r = await next(e)
    if (r.deny !== undefined) return r

    const tokens = (await observe($)).context.tokens
    if (tokens !== undefined) s.history = [...s.history, tokens].slice(-(BURN_CALLS + 1))
    const warning = warningFor(tokens)
    const lines = [...takeNote(), ...(warning ? [warning] : [])]
    if (lines.length === 0) return r

    if (warning) s.lastWarned = tokens ?? null
    return { ...r, context: [...(r.context ?? []), ...lines] }
  }).catch(($, e, next) => (e.tool === TOOL ? { result: MSG.saveFailed } : next(e)))

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'plugin' && e.origin.name === $.plugin.name) return next(e)

    s.prompts++
    cancel()
    // Too late to cancel: the clear is under way, so this prompt carries the handoff instead.
    const committed = s.rec?.phase === 'committed' ? s.rec : null
    // A slash command may never reach the model, so it cannot carry the handoff: the start message still goes.
    const carries = committed !== null && e.command === undefined
    if (committed) {
      if (carries) committed.userHasHandoff = true
      if (resetsGen(e.origin.kind)) committed.userRepliedAfterCommit = true
      committed.overwritten.push(e.text)
    }

    // A failed reset only makes the auto-continue cap stricter; it must not cost the prompt its handoff.
    if (resetsGen(e.origin.kind)) await update($, gen, () => 0).catch(() => {})
    const tokens = (await observe($).catch(() => null))?.context.tokens
    const warning = warningFor(tokens)
    const lines = [...(carries ? [MSG.committed(committed.content)] : []), ...takeNote(), ...(warning ? [warning] : [])]
    if (lines.length === 0) return next(e)

    if (warning) s.lastWarned = tokens ?? null
    return next({ ...e, context: [...(e.context ?? []), ...lines] })
  }).catch(($, e, next) => next(e))
}

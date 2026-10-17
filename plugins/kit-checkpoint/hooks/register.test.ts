import { test, expect, mock } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { AgentStatus, On, PromptOrigin } from 'claude-code'

import { MSG, TOOL } from './logic'

const T0 = Date.UTC(2026, 9, 17, 12, 0, 0) // 19:00:00 Bangkok
const DENIED = 'ListSkills' // a tool whose call the world refuses

// The world beneath the plugin: every op it calls on $, answered from `w`.
function world(on: On) {
  const w = {
    tokens: 450_000 as number | undefined, sid: 'sid-1', startedAt: 1,
    rate: [{ kind: 'five_hour', percentUsed: 10 }, { kind: 'seven_day', percentUsed: 10 }],
    agents: [] as { id: string; status: AgentStatus }[],
    files: new Map<string, string>(), commands: [] as string[], submits: [] as string[], notes: [] as string[], specs: [] as unknown[],
    toolsRan: [] as string[], git: true, clear: 'works' as 'works' | 'noop' | 'reject', submit: 'ok' as 'ok' | 'drop',
    holdWrite: 0, holdClear: 0, holdList: 0, usageThrows: false, notifyThrows: false, writeThrows: false,
  }
  const clock = mock.clock(on, { now: T0 })
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('tool.register', async (_$, e) => { w.specs.push(e); return { value: { tool: e.name } } })
  on('session.usage', async () => {
    if (w.usageThrows) throw new Error('usage')
    return { value: { startedAt: w.startedAt, context: { tokens: w.tokens, window: 1_000_000 }, rateLimits: w.rate } }
  })
  on('session.id', async () => ({ value: w.sid }))
  on('agent.list', async () => { if (w.holdList) await clock.sleep(w.holdList); return { value: w.agents.map(a => ({ description: '', type: 'test', ...a })) } })
  on('process.run', async () => ({ value: w.git
    ? { stdout: '/repo/.git\n', stderr: '', exitCode: 0, isStdoutTruncated: false, isStderrTruncated: false }
    : { stdout: '', stderr: 'fatal: not a git repository', exitCode: 128, isStdoutTruncated: false, isStderrTruncated: false } }))
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
    return { value: { isSent: true as const, channel: 'ghostty' as const } }
  })
  on('prompt.submit', async (_$, e) => {
    if (e.origin.kind !== 'plugin') return { text: e.text, context: e.context }
    w.submits.push(e.text)
    return w.submit === 'drop' ? { drop: 'test' } : { text: e.text }
  })
  on('tool.call', async (_$, e) => { w.toolsRan.push(e.tool); return e.tool === DENIED ? { deny: 'no' } : { result: `ran ${e.tool}` } })
  on('turn.start', async (_$, e) => ({ turnId: e.turnId }))
  on('turn.step', async function* (_$, e) {
    return { turnId: e.turnId, index: e.index, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  on('turn.complete', async () => ({ text: '' }))
  return { w, clock }
}

type World = ReturnType<typeof world>

// drivers: the test plays the engine
const step = async ($: Engine, turnId: string, agentId?: string) => { for await (const _ of $.turn.step({ turnId, index: 0, model: 'test', messageCount: 1, agentId })) {} }
const user = ($: Engine, text: string, kind: PromptOrigin['kind'] = 'composer') =>
  $.prompt.submit({ text, origin: { kind } as PromptOrigin, wait: false })
const done = ($: Engine, turnId: string, isAborted = false) =>
  $.turn.complete({ turnId, answer: '', durationMs: 1, isAborted, reason: isAborted ? 'aborted' : 'answer' })
// agentId is how the engine marks a subagent's call; the test's $.tool.call types leave it out
const bash = ($: Engine, agentId?: string) => $.tool.call({ tool: 'Bash', command: 'ls', agentId } as { tool: 'Bash'; command: string })
const handoff = ($: Engine, mode = 'auto', content = '# งาน\nขั้นต่อไป: X') => $.tool.call({ tool: TOOL, content, mode, reason: 'ทดสอบ' })
const ctx = (r: { context?: readonly string[] }) => (r.context ?? []).join('\n')

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
  expect((await $.tool.call({ tool: DENIED })).context).toBeUndefined()
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

const P1 = '/repo/.git/kit-handoff/20261017-190000-g1.md'

test('registers the tool up front', async ($, on) => {
  const { w } = world(on)
  await $.session.start({ cwd: '/repo', surface: null, isInteractive: true })
  expect(w.specs).toEqual([expect.objectContaining({ name: 'handoff', isDeferred: false })])
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

test('Esc while the file is being written refuses and never clears', async ($, on) => {
  const { w, clock } = world(on)
  await step($, 'T1')
  w.holdWrite = 10
  const call = handoff($)
  await clock.settle()
  await done($, 'T1', true)
  await clock.advance(10)
  expect((await call).result).toBe(MSG.promptArrived)
  await clock.settle()
  expect(w.commands).toEqual([])
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

// one full handoff cycle in turn `t`: high context, handoff, end of turn, timers run
async function cycle($: Engine, w: World["w"], clock: World["clock"], t: string, mode = 'auto') {
  w.tokens = 30_000; await bash($) // reading below 400K lifts the post-clear quiet
  w.tokens = 450_000
  await step($, t)
  const r = await handoff($, mode)
  await clock.settle(); w.notes.length = 0 // notify ตอนบันทึกมี path อยู่แล้ว ล้างทิ้งให้ test เห็นเฉพาะ notify ของ finalize
  await done($, t)
  await clock.settle()
  return r
}

test('auto: clear then framed start message', async ($, on) => {
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1')
  expect(w.commands).toEqual(['clear'])
  expect(w.submits).toHaveLength(1)
  expect(w.submits[0]?.startsWith(`[kit-checkpoint #1] ${P1}\n\n# งาน`)).toBe(true)
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
  expect(w.submits[4]?.startsWith('[kit-checkpoint #1]')).toBe(true)
})

test('task notifications do not reset the generation', async ($, on) => {
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1')
  await user($, '<task-notification>', 'task-notification')
  await cycle($, w, clock, 'T2')
  expect(w.submits[1]?.startsWith('[kit-checkpoint #2]')).toBe(true)
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
  await $.session.append({ door: 'delivery', origin: { kind: 'task-notification' }, uuid: 'u1', message: { type: 'user', role: 'user', content: [{ type: 'text', text: 'x' }] } })
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
  w.holdClear = 0
  await cycle($, w, clock, 'T2') // userRepliedAfterCommit → gen 0 → next is #1
  expect(w.submits[0]?.startsWith('[kit-checkpoint #1]')).toBe(true)
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

test('a turn queued before the commit gets quoted when it slips in', async ($, on) => {
  const { w, clock } = world(on)
  w.holdClear = 10
  await user($, 'คิวไว้ก่อน') // prompt.submit ก่อน step ของ handoff จึงไม่ได้ cancel และไม่ได้อยู่ใน overwritten
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle()
  await $.turn.start({ text: 'คิวไว้ก่อน', turnId: 'T9' })
  await clock.advance(10)
  expect(w.submits[0]).toContain('> คิวไว้ก่อน')
})

test('a slash command while committed still gets the start message', async ($, on) => {
  const { w, clock } = world(on)
  w.holdClear = 10
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle()
  const r = await $.prompt.submit({ text: '/model', command: { name: 'model', args: '' }, origin: { kind: 'composer' }, wait: false })
  expect(ctx(r)).not.toContain(MSG.committed('# งาน\nขั้นต่อไป: X'))
  await clock.advance(10)
  expect(w.submits).toHaveLength(1)
})

test('a failed generation reset still attaches the committed handoff', async ($, on) => {
  on('state.set', async () => ({ deny: 'policy' }))
  const { w, clock } = world(on)
  w.holdClear = 10
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle()
  expect(ctx(await user($, 'ถามหน่อย'))).toContain(MSG.committed('# งาน\nขั้นต่อไป: X'))
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
  expect(w.submits[0]).toContain(String(b.result).match(/\/repo\S+\.md/)![0])
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

test('a usage failure after the clear still sends the handoff', async ($, on) => {
  const { w, clock } = world(on)
  w.holdClear = 5
  await step($, 'T1'); await handoff($); await done($, 'T1')
  await clock.settle() // finalize waits on command.run
  w.usageThrows = true
  await clock.advance(5)
  expect(w.sid).toBe('sid-1+')
  expect(w.submits).toHaveLength(1)
})

test('a failed generation write still sends the handoff, but waits', async ($, on) => {
  on('state.set', async () => ({ deny: 'policy' }))
  const { w, clock } = world(on)
  await cycle($, w, clock, 'T1')
  expect(w.commands).toEqual(['clear'])
  expect(w.submits).toHaveLength(1)
  expect(w.submits[0]).not.toContain(MSG.goOn)
})

test('startedAt change at high context lifts quiet after the next model response', async ($, on) => {
  const { w } = world(on)
  w.tokens = 120_000; await bash($)
  w.startedAt = 99; w.tokens = 450_000 // เช่น /resume เข้าบทสนทนาใหญ่
  expect(ctx(await bash($))).toBe('')
  await step($, 'T1')
  w.tokens = 520_000
  expect(ctx(await bash($))).toContain(MSG.hard)
})

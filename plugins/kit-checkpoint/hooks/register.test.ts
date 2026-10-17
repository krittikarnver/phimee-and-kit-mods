import { test, expect, mock } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { MSG, TOOL } from './logic'

const T0 = Date.UTC(2026, 9, 17, 12, 0, 0) // 19:00:00 Bangkok

// The world beneath the plugin: every op it calls on $, answered from `w`.
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
const step = async ($: Engine, turnId: string, agentId?: string) => { for await (const _ of $.turn.step({ turnId, index: 0, model: 'test', agentId })) {} }
const user = ($: Engine, text: string, kind = 'composer') => $.prompt.submit({ text, origin: { kind }, wait: false })
const done = ($: Engine, turnId: string, isAborted = false) =>
  $.turn.complete({ turnId, answer: '', durationMs: 1, isAborted, reason: isAborted ? 'aborted' : 'answer' })
const bash = ($: Engine, agentId?: string) => $.tool.call({ tool: 'Bash', input: { command: 'ls' }, agentId })
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

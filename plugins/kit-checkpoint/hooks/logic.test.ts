import { test, expect } from 'claude-code/testing'

import type { CallFacts, Rate } from './logic'
import { MSG, burn, guard, handoffDoc, handoffPath, pickLimits, refusal, resetsGen, stamp, startText, warnLevel, warnText } from './logic'

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

const ok: CallFacts = { content: 'x', tokens: 450_000, quiet: false, phase: 'none', tools: 0, prompts: 0, busyAgents: 0 }
const both: [Rate, Rate] = [{ kind: 'five_hour', percentUsed: 10 }, { kind: 'seven_day', percentUsed: 10 }]
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
  expect(startText({ ...h, reason: '' }, { auto: false })).not.toContain('()')
})

test('which origins reset the generation', () => {
  expect(resetsGen('composer')).toBe(true)
  expect(resetsGen('bridge')).toBe(true)
  for (const k of ['task-notification', 'scheduled-trigger', 'unclassified', 'plugin', 'sdk']) expect(resetsGen(k)).toBe(false)
})

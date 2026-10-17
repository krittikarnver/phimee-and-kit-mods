import { test, expect } from 'claude-code/testing'

import { MSG, burn, warnLevel, warnText } from './logic'

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

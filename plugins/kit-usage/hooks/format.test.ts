import { test, expect } from 'claude-code/testing'

import { bandText, contextLine, formatK, formatReset } from './format'

const now = Date.UTC(2026, 9, 12, 6, 0) // 13:00 Bangkok

test('formats token counts', () => {
  expect(formatK(144_321)).toBe('144k')
  expect(formatK(1_000_000)).toBe('1M')
})

test('formats reset time in Bangkok', () => {
  expect(formatReset('2026-10-12T08:00:00Z', now)).toBe('15:00')
  expect(formatReset('2026-10-15T08:00:00Z', now)).toBe('15 ต.ค. 15:00')
})

test('context line with rate limits and cost', () => {
  const u = {
    context: { tokens: 144_000, window: 200_000, percent: 72 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 41, resetsAt: '2026-10-12T08:00:00Z' },
      { kind: 'seven_day', percentUsed: 18.5 },
    ],
    cost: { usd: 3.456 },
  }
  expect(contextLine(u, now)).toBe('[kit-usage] context 72% (144k/200k) · 5 ชม. 41% รีเซ็ต 15:00 · 7 วัน 18.5% · $3.46')
})

test('warns near compaction', () => {
  const u = { context: { tokens: 180_000, window: 200_000, percent: 90 }, rateLimits: [] }
  expect(contextLine(u, now)).toContain('ใกล้ compact แล้ว')
  expect(bandText(u, now)).toBe('⚠️ context 90% (180k/200k)')
})

test('no figures yet', () => {
  const u = { context: { window: 200_000 }, rateLimits: [] }
  expect(contextLine(u, now)).toBe('[kit-usage] context ยังไม่มีตัวเลข (เต็มที่ 200k)')
})

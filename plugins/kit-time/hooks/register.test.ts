import { test, expect } from 'claude-code/testing'

import { bandText, formatBangkok, formatGap } from './register'

test('formats Bangkok time with Thai weekday and BE year', () => {
  expect(formatBangkok(Date.UTC(2026, 9, 10, 12, 30))).toBe('วันเสาร์ที่ 10 ต.ค. 2569 (2026) เวลา 19:30 น.')
})

test('rolls over to the next day in Bangkok', () => {
  expect(formatBangkok(Date.UTC(2026, 9, 10, 18, 5))).toBe('วันอาทิตย์ที่ 11 ต.ค. 2569 (2026) เวลา 01:05 น.')
})

test('formats gaps', () => {
  expect(formatGap(30_000)).toBe('ไม่ถึงนาที')
  expect(formatGap(12 * 60_000)).toBe('12 นาที')
  expect(formatGap(3 * 3_600_000 + 5 * 60_000)).toBe('3 ชม. 5 นาที')
  expect(formatGap(26 * 3_600_000)).toBe('1 วัน 2 ชม.')
})

test('band text', () => {
  const last = Date.UTC(2026, 9, 10, 11, 19)
  expect(bandText(last, last + 10_000)).toBe('🕰 ข้อความล่าสุด 18:19 · เมื่อกี้ · ตอนนี้ 18:19')
  expect(bandText(last, last + 5 * 60_000)).toBe('🕰 ข้อความล่าสุด 18:19 · 5 นาทีที่แล้ว · ตอนนี้ 18:24')
})

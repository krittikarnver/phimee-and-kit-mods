// Pure rules and messages for kit-checkpoint, kept apart from the hooks so tests can import them.

export const SOFT = 400_000
export const HARD = 500_000
export const STEP = 25_000
export const BURN_CALLS = 10

export type Level = 'soft' | 'hard'
export type Burn = { grew: number; calls: number }

// Copied from kit-usage/hooks/format.ts: plugins install separately, so no cross-plugin import.
export const formatK = (tokens: number): string =>
  tokens >= 1_000_000 ? `${+(tokens / 1_000_000).toFixed(1)}M` : `${Math.round(tokens / 1000)}k`

export const MSG = {
  soft: 'ทำชิ้นปัจจุบันต่อได้ ประเมินว่างานชิ้นถัดไปจะทำทันก่อน 500K ไหม ถ้าไม่ทันให้หยุดที่ checkpoint ถัดไป (จุดที่ถ้าหยุดแล้วเริ่มใหม่ งานไม่พัง) แล้วเรียก tool handoff',
  hard: 'หยุดทันทีที่หยุดได้อย่างปลอดภัย ถ้ากำลังแก้ไฟล์อยู่ให้ทำให้เสร็จจนอยู่ในสภาพที่ใช้ได้ก่อน แล้วเรียก tool handoff',
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
  if (last.length < 2) return null
  return { grew: last[last.length - 1] - last[0], calls: last.length - 1 }
}

export const warnText = (level: Level, tokens: number, b: Burn | null): string => {
  const burnPart = b ? `โต ${formatK(b.grew)} ใน ${b.calls} tool call ล่าสุด` : 'ยังไม่มี burn rate'
  return `[kit-checkpoint] context ${formatK(tokens)} · เหลือ ${formatK(Math.max(0, HARD - tokens))} ก่อนถึง 500k · ${burnPart} · ${MSG[level]}`
}

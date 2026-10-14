// Pure formatting for kit-usage, kept apart from the hooks so tests can import it.

export type ContextFigures = { tokens?: number; window: number; percent?: number }
export type RateFigures = { kind: string; percentUsed: number; resetsAt?: string }
export type UsageFigures = { context: ContextFigures; rateLimits: RateFigures[]; cost?: { usd: number } }

export const WARN_PERCENT = 85
const BKK_OFFSET_MS = 7 * 60 * 60 * 1000
const MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']
const KIND_NAMES: Record<string, string> = { five_hour: '5 ชม.', seven_day: '7 วัน', spend_limit: 'วงเงิน' }

const pad = (n: number) => String(n).padStart(2, '0')

export const formatK = (tokens: number): string =>
  tokens >= 1_000_000 ? `${+(tokens / 1_000_000).toFixed(1)}M` : `${Math.round(tokens / 1000)}k`

export const formatReset = (iso: string, now: number): string | null => {
  const at = Date.parse(iso)
  if (Number.isNaN(at)) return null

  const d = new Date(at + BKK_OFFSET_MS)
  const clock = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  const today = new Date(now + BKK_OFFSET_MS)
  const sameDay =
    d.getUTCFullYear() === today.getUTCFullYear() &&
    d.getUTCMonth() === today.getUTCMonth() &&
    d.getUTCDate() === today.getUTCDate()

  return sameDay ? clock : `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${clock}`
}

export const contextPart = (c: ContextFigures): string => {
  if (c.percent === undefined || c.tokens === undefined) return `context ยังไม่มีตัวเลข (เต็มที่ ${formatK(c.window)})`

  return `context ${c.percent}% (${formatK(c.tokens)}/${formatK(c.window)})`
}

export const ratePart = (r: RateFigures, now: number): string => {
  const name = KIND_NAMES[r.kind] ?? r.kind
  const reset = r.resetsAt ? formatReset(r.resetsAt, now) : null

  return reset ? `${name} ${r.percentUsed}% รีเซ็ต ${reset}` : `${name} ${r.percentUsed}%`
}

export const isNearCompact = (c: ContextFigures): boolean => (c.percent ?? 0) >= WARN_PERCENT

/** The line Claude reads with each prompt. */
export const contextLine = (u: UsageFigures, now: number): string => {
  const parts = [contextPart(u.context), ...u.rateLimits.map(r => ratePart(r, now))]
  if (u.cost) parts.push(`$${u.cost.usd.toFixed(2)}`)

  const warn = isNearCompact(u.context)
    ? ' · ใกล้ compact แล้ว: เตือนผู้ใช้ให้จดเรื่องสำคัญไว้ก่อน'
    : ''

  return `[kit-usage] ${parts.join(' · ')}${warn}`
}

/** The shorter band above the prompt. */
export const bandText = (u: UsageFigures, now: number): string => {
  const parts = [contextPart(u.context), ...u.rateLimits.map(r => ratePart(r, now))]
  return `${isNearCompact(u.context) ? '⚠️' : '📊'} ${parts.join(' · ')}`
}

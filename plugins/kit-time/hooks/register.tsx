import type { Register } from 'claude-code'

const LAST_KEY = 'lastPromptAt'
const BKK_OFFSET_MS = 7 * 60 * 60 * 1000 // Asia/Bangkok, UTC+7, no DST
const DAYS = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์']
const MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']

const pad = (n: number) => String(n).padStart(2, '0')

export const formatClock = (ms: number): string => {
  const d = new Date(ms + BKK_OFFSET_MS)

  return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
}

export const formatBangkok = (ms: number): string => {
  const d = new Date(ms + BKK_OFFSET_MS)
  const day = DAYS[d.getUTCDay()]
  const year = d.getUTCFullYear()

  return `วัน${day}ที่ ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${year + 543} (${year}) เวลา ${formatClock(ms)} น.`
}

export const formatGap = (ms: number): string => {
  const minutes = Math.floor(ms / 60_000)

  if (minutes < 1) return 'ไม่ถึงนาที'
  if (minutes < 60) return `${minutes} นาที`

  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60

  if (hours < 24) return rest ? `${hours} ชม. ${rest} นาที` : `${hours} ชม.`

  return `${Math.floor(hours / 24)} วัน ${hours % 24} ชม.`
}

export const register: Register = on => {
  on('prompt.submit', async ($, e, next) => {
    const now = await $.clock.now()
    const last = await $.store.get(LAST_KEY)
    await $.store.set(LAST_KEY, now)

    const gap = typeof last === 'number' ? `ห่างจากข้อความก่อนหน้า ${formatGap(now - last)}` : 'ข้อความแรกที่ mod เห็น'
    const stamp = `[kit-time] ตอนนี้ ${formatBangkok(now)} เวลาไทย · ${gap}`

    return next({ ...e, context: [...(e.context ?? []), stamp] })
  })
}

import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

const LAST_KEY = 'lastPromptAt'
const BKK_OFFSET_MS = 7 * 60 * 60 * 1000 // Asia/Bangkok, UTC+7, no DST
const DAYS = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัส', 'ศุกร์', 'เสาร์']
const MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']

const lastAt = atom({ plugin: 'kit-time', key: 'lastAt' } as const, null)
const nowAtom = atom({ plugin: 'kit-time', key: 'now' } as const, 0)

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

export const bandText = (last: number, now: number): string => {
  const gap = now - last
  const ago = gap < 60_000 ? 'เมื่อกี้' : `${formatGap(gap)}ที่แล้ว`

  return `🕰 ข้อความล่าสุด ${formatClock(last)} · ${ago} · ตอนนี้ ${formatClock(now)}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const stored = await $.store.get(LAST_KEY)

    if (typeof stored === 'number') {
      await update($, lastAt, () => stored)
    }

    const now = await $.clock.now()
    await update($, nowAtom, () => now)

    $.clock.every(30_000, async () => {
      const tick = await $.clock.now()
      await update($, nowAtom, () => tick)
    })

    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const now = await $.clock.now()
    const last = await $.store.get(LAST_KEY)
    await $.store.set(LAST_KEY, now)
    await update($, lastAt, () => now)
    await update($, nowAtom, () => now)

    const gap = typeof last === 'number' ? `ห่างจากข้อความก่อนหน้า ${formatGap(now - last)}` : 'ข้อความแรกที่ mod เห็น'
    const stamp = `[kit-time] ตอนนี้ ${formatBangkok(now)} เวลาไทย · ${gap}`

    return next({ ...e, context: [...(e.context ?? []), stamp] })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const last = await read($, lastAt)
    const now = await read($, nowAtom)

    if (e.props.hasSurvey || last === null || now === 0) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text dimColor>{bandText(last, Math.max(now, last))}</Text>
      </Box>
    )
  })
}

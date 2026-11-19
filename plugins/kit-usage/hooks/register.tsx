import type { Register } from 'claude-code'

import { contextLine, isNearCompact } from './format'

export const register: Register = on => {
  let warned = false

  on('session.measure', async ($, e, next) => {
    if (isNearCompact(e.context) && !warned) {
      warned = true
      $.ui.toast('context ใกล้เต็มแล้ว อีกไม่นานจะโดน compact จดเรื่องสำคัญไว้ก่อนนะ')
    } else if (!isNearCompact(e.context)) {
      warned = false
    }

    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    try {
      const usage = await $.session.usage()
      const now = await $.clock.now()

      return next({ ...e, context: [...(e.context ?? []), contextLine(usage, now)] })
    } catch {
      // Never hold a prompt back over a missing reading.
      return next(e)
    }
  })
}

import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import { bandText, contextLine, isNearCompact } from './format'

const line = atom({ plugin: 'kit-usage', key: 'line' } as const, null)

export const register: Register = on => {
  let warned = false

  on('session.measure', async ($, e, next) => {
    const now = await $.clock.now()
    await update($, line, () => bandText(e, now))

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
      await update($, line, () => bandText(usage, now))

      return next({ ...e, context: [...(e.context ?? []), contextLine(usage, now)] })
    } catch {
      // Never hold a prompt back over a missing reading.
      return next(e)
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = await read($, line)

    if (e.props.hasSurvey || text === null) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text dimColor>{text}</Text>
      </Box>
    )
  })
}

import { atom } from 'claude-code'
import type { EngineInterface, Register, SessionUsage } from 'claude-code'

import { BURN_CALLS, MSG, SOFT, TOOL, burn, warnLevel, warnText } from './logic'
import type { Rate } from './logic'

// The generation of the current conversation; kept in $.state so it outlives a reload.
const gen = atom({ plugin: 'kit-checkpoint', key: 'gen' } as const, 0)

const fresh = () => ({
  lastWarned: null as number | null,
  history: [] as number[],
  rate: null as { limits: Rate[]; at: number } | null,
  startedAt: null as number | null,
  // No warnings (and no handoff) until a reading below 400K: the figures may still be the old conversation's.
  quiet: false,
})

// Module state; register() starts it over, as a reload starts the module's variables over.
let s = fresh()

async function observe($: EngineInterface): Promise<SessionUsage> {
  const u = await $.session.usage()
  if (s.startedAt !== null && u.startedAt !== s.startedAt) {
    s.quiet = true
    s.history = []
    s.lastWarned = null
  }
  s.startedAt = u.startedAt
  if (u.rateLimits.length > 0) s.rate = { limits: [...u.rateLimits], at: await $.clock.now() }
  if (u.context.tokens !== undefined && u.context.tokens < SOFT) {
    s.quiet = false
    s.lastWarned = null
  }
  return u
}

/** The warning due at this reading, if any; the caller sets lastWarned only once it is attached. */
function warningFor(tokens: number | undefined): string | null {
  if (s.quiet || tokens === undefined) return null
  const level = warnLevel(tokens, s.lastWarned)
  return level && warnText(level, tokens, burn(s.history))
}

export const register: Register = on => {
  s = fresh()

  on('tool.call', async ($, e, next) => {
    if (e.tool === TOOL) return next(e)
    if (e.agentId !== undefined) return next(e)

    const r = await next(e)
    if (r.deny !== undefined) return r

    const tokens = (await observe($)).context.tokens
    if (tokens !== undefined) s.history = [...s.history, tokens].slice(-(BURN_CALLS + 1))
    const warning = warningFor(tokens)
    if (!warning || tokens === undefined) return r

    s.lastWarned = tokens
    return { ...r, context: [...(r.context ?? []), warning] }
  }).catch(($, e, next) => (e.tool === TOOL ? { result: MSG.saveFailed } : next(e)))

  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'plugin' && e.origin.name === $.plugin.name) return next(e)

    const tokens = (await observe($)).context.tokens
    const warning = warningFor(tokens)
    if (!warning || tokens === undefined) return next(e)

    s.lastWarned = tokens
    return next({ ...e, context: [...(e.context ?? []), warning] })
  }).catch(($, e, next) => next(e))
}

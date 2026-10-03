// ABOUTME: turn-timer mod: a label in the prompt footer's mode area with the running turn's elapsed
// ABOUTME: time, then the last turn's duration once it ends. Subagent turns are ignored.

import { atom, read, update } from 'claude-code'
import type { Register, Timer } from 'claude-code'

const label = atom({ plugin: 'turn-timer', key: 'label' } as const, null)

export const formatDuration = (ms: number): string => {
  const seconds = Math.floor(ms / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m${String(seconds % 60).padStart(2, '0')}s`
  return `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, '0')}m`
}

export const register: Register = on => {
  let tick: Timer | undefined

  on('turn.start', async ($, e, next) => {
    tick?.cancel()
    const startedAt = await $.clock.now()
    await update($, label, () => 'turn 0s')
    tick = $.clock.every(1000, async () => {
      const elapsed = formatDuration((await $.clock.now()) - startedAt)
      await update($, label, () => `turn ${elapsed}`)
    })

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      tick?.cancel()
      tick = undefined
      const verb = e.isAborted ? 'interrupted after' : 'last turn'
      await update($, label, () => `${verb} ${formatDuration(e.durationMs)}`)
    }

    return next(e)
  })

  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    const text = await read($, label)
    if (text === null) return next(e)

    return next({ ...e, props: { ...e.props, modes: [...e.props.modes, text] } })
  })
}

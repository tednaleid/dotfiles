// ABOUTME: context-bar mod: a stacked bar above the prompt showing the context window by /context category.
// ABOUTME: Refreshes after each turn and compaction; /context-bar toggles it on and off.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { cellWidths, formatTokens, toSnapshot } from './bar'

const COMMAND = 'context-bar'
const snapshot = atom({ plugin: 'context-bar', key: 'snapshot' } as const, null)
const isShown = atom({ plugin: 'context-bar', key: 'isShown' } as const, true)

const refresh = async ($: EngineInterface) => {
  const usage = await $.session.usage({ breakdown: 'summary' })
  const breakdown = usage.context.breakdown
  if (breakdown) await update($, snapshot, () => toSnapshot(breakdown))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: COMMAND,
      description: 'Toggle the context window bar above the prompt',
    })
    const result = await next(e)
    await refresh($)

    return result
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    await refresh($)

    return result
  })

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    await refresh($)

    return result
  })

  on('command.run', { command: COMMAND }, async $ => {
    const shown = await update($, isShown, value => !value)
    if (shown) await refresh($)

    return { text: shown ? 'Context bar shown.' : 'Context bar hidden.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    if (e.props.hasSurvey || !snap || !(await read($, isShown))) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)
    const label = ` ${formatTokens(snap.usedTokens)}/${formatTokens(snap.maxTokens)} (${snap.percentage}%)`
    // The band draws its [-] collapse marker at the right edge of the first row.
    const widths = cellWidths(snap.segments, Math.max(10, e.props.bodyColumns - label.length - 5))
    const used = snap.segments.filter(s => s.kind === 'used')

    return (
      <Box flexDirection="column">
        <Box key="bar">
          {snap.segments.map((s, i) => (
            <Text color={s.color} dimColor={s.kind !== 'used'}>
              {(s.kind === 'used' ? '█' : s.kind === 'buffer' ? '▒' : '░').repeat(widths[i] ?? 0)}
            </Text>
          ))}
          <Text dimColor>{label}</Text>
        </Box>
        <Box key="legend" flexWrap="wrap" columnGap={2}>
          {used.map(s => (
            <Text>
              <Text color={s.color}>■</Text>
              <Text dimColor> {s.name} {formatTokens(s.tokens)}</Text>
            </Text>
          ))}
        </Box>
      </Box>
    )
  })
}

// ABOUTME: Tests for the turn-timer mod: duration formatting, the live tick while a turn runs,
// ABOUTME: and the label it adds to the prompt footer's mode area.

import type { RenderElement, TurnCompleteInput } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { formatDuration } from '../hooks/register'

const COMPLETE: TurnCompleteInput = {
  reason: 'answer',
  answer: 'done',
  durationMs: 72_400,
  isAborted: false,
  turnId: 't1',
}

const FOOTER = { component: 'SessionMode', props: { modes: ['focus'] } } as const

test('formats seconds, minutes and hours', () => {
  expect(formatDuration(999)).toBe('0s')
  expect(formatDuration(42_000)).toBe('42s')
  expect(formatDuration(72_400)).toBe('1m12s')
  expect(formatDuration(3_725_000)).toBe('1h02m')
})

test('adds the running and then the final turn time to the footer modes', async ($, on) => {
  const clock = mock.clock(on, { now: 1_000_000 })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: 'done' }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const modes = e.component === 'SessionMode' ? e.props.modes : []
    return h(Text, {}, modes.join(' & ')) as RenderElement
  })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'turn-timer', surface, ...FOOTER })
    expect((await ui.find({ type: 'Text' }))?.text).toBe('focus')
    await ui.unmount()
  }

  await $.turn.start({ text: 'hi', turnId: 't1' })
  await clock.advance(42_000)
  const ui = await $.ui.mount({ plugin: 'turn-timer', surface: 'terminal', ...FOOTER })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('focus & turn 42s')

  await $.turn.complete({ ...COMPLETE, agentId: 'sub-1' })
  await clock.advance(1_000)
  expect((await ui.find({ type: 'Text' }))?.text).toBe('focus & turn 43s')

  await $.turn.complete(COMPLETE)
  await clock.advance(5_000)
  expect((await ui.find({ type: 'Text' }))?.text).toBe('focus & last turn 1m12s')
  await ui.unmount()
})

test('says when a turn was interrupted', async ($, on) => {
  on('turn.complete', () => ({ text: '' }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    const modes = e.component === 'SessionMode' ? e.props.modes : []
    return h(Text, {}, modes.join(' & ')) as RenderElement
  })

  await $.turn.complete({ ...COMPLETE, reason: 'aborted', isAborted: true, durationMs: 5_000 })
  const ui = await $.ui.mount({ plugin: 'turn-timer', surface: 'terminal', component: 'SessionMode', props: { modes: [] } })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('interrupted after 5s')
})
